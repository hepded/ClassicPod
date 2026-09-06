import Foundation
import PodCore

struct SpotifyImage: Decodable, Sendable { let url: URL }
struct SpotifyArtist: Decodable, Sendable { let name: String }
struct SpotifyAlbum: Decodable, Sendable { let name: String; let images: [SpotifyImage]? }
struct SpotifyTrackDTO: Decodable, Sendable {
    let id: String?
    let uri: String
    let name: String
    let artists: [SpotifyArtist]?
    let album: SpotifyAlbum?
    let duration_ms: Double?
    let is_playable: Bool?
    let is_local: Bool?
    let type: String?
    var track: Track? {
        guard type == nil || type == "track", is_playable != false, is_local != true, uri.hasPrefix("spotify:track:") else { return nil }
        return Track(id: uri, title: name, artist: artists?.map(\.name).joined(separator: ", ") ?? "Spotify", album: album?.name ?? "", duration: (duration_ms ?? 0) / 1000, artworkURL: album?.images?.first?.url, location: .spotify(uri: uri))
    }
}
struct SpotifyItem: Decodable, Sendable { let track: SpotifyTrackDTO?; let item: SpotifyTrackDTO?; var value: Track? { (item ?? track)?.track } }
struct SpotifyPage<Item: Decodable & Sendable>: Decodable, Sendable { let items: [Item]; let next: URL? }
struct SpotifyPlaylist: Decodable, Sendable { let id: String; let name: String }
struct SpotifyDevice: Decodable, Sendable {
    let id: String?; let name: String; let is_active: Bool?; let is_restricted: Bool?; let volume_percent: Int?; let supports_volume: Bool?
}
struct SpotifyState: Decodable, Sendable {
    let is_playing: Bool; let progress_ms: Double?; let item: SpotifyTrackDTO?; let device: SpotifyDevice?
    struct Actions: Decodable, Sendable { let disallows: [String: Bool]? }
    let actions: Actions?
}
@MainActor protocol SpotifyTokenProviding {
    func accessToken(force: Bool) async throws -> String
}
extension SpotifyOAuth: SpotifyTokenProviding {}
@MainActor final class SpotifyWebAPI {
    let oauth: any SpotifyTokenProviding
    private let session: URLSession
    private var rateLimitUntil = Date.distantPast
    init(oauth: any SpotifyTokenProviding, session: URLSession = .shared) { self.oauth = oauth; self.session = session }
    func request(_ path: String, method: String = "GET", body: Data? = nil) async throws -> Data {
        guard let url = URL(string: path.hasPrefix("https://") ? path : "https://api.spotify.com/v1/\(path)"), url.scheme == "https", url.host == "api.spotify.com", url.path.hasPrefix("/v1/") else { throw PodError.message(L10n.text("Недопустимый адрес Spotify API")) }
        guard Date() >= rateLimitUntil else { throw PodError.message(L10n.format("Spotify: повторите через %@ с", String(Int(ceil(rateLimitUntil.timeIntervalSinceNow))))) }
        var token = try await oauth.accessToken(force: false)
        for attempt in 0...1 {
            var request = URLRequest(url: url); request.httpMethod = method; request.httpBody = body; request.timeoutInterval = 15
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else { throw PodError.message(L10n.text("Нет ответа Spotify")) }
            switch response.statusCode {
            case 200...299: return data
            case 401 where attempt == 0: token = try await oauth.accessToken(force: true)
            case 403: throw PodError.message(L10n.text("Spotify: доступ запрещён. Проверьте Premium, scopes, allowlist и ограничения Development Mode."))
            case 404: throw PodError.message(L10n.text("Spotify: нет доступного устройства или контента. Откройте клиент и выберите устройство."))
            case 429:
                let seconds = max(1, Double(response.value(forHTTPHeaderField: "Retry-After") ?? "5") ?? 5)
                rateLimitUntil = Date().addingTimeInterval(seconds)
                throw PodError.message(L10n.format("Spotify ограничил частоту запросов: ожидание %@ с", String(Int(seconds))))
            default: throw PodError.message("Spotify HTTP \(response.statusCode)")
            }
        }
        throw PodError.message(L10n.text("Spotify: авторизуйтесь повторно"))
    }
    func all<Item: Decodable & Sendable>(_ path: String, as type: Item.Type) async throws -> [Item] {
        var next: String? = path; var result: [Item] = []; var visited = Set<String>()
        while let path = next {
            try Task.checkCancellation()
            guard visited.insert(path).inserted else { throw PodError.message(L10n.text("Spotify вернул циклическую пагинацию")) }
            let page = try JSONDecoder().decode(SpotifyPage<Item>.self, from: await request(path))
            result.append(contentsOf: page.items); next = page.next?.absoluteString
        }
        return result
    }
    func liked() async throws -> [Track] { try await all("me/tracks?limit=50", as: SpotifyItem.self).compactMap(\.value) }
    func playlists() async throws -> [SpotifyPlaylist] { try await all("me/playlists?limit=50", as: SpotifyPlaylist.self) }
    func tracks(playlist: String) async throws -> [Track] {
        guard playlist.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { throw PodError.message(L10n.text("Недопустимый ID плейлиста")) }
        return try await all("playlists/\(playlist)/items?limit=50", as: SpotifyItem.self).compactMap(\.value)
    }
    func devices() async throws -> [SpotifyDevice] {
        struct Reply: Decodable { let devices: [SpotifyDevice] }
        return try JSONDecoder().decode(Reply.self, from: await request("me/player/devices")).devices
    }
    func state() async throws -> SpotifyState? {
        let data = try await request("me/player")
        return data.isEmpty ? nil : try JSONDecoder().decode(SpotifyState.self, from: data)
    }
    func command(_ name: String, method: String = "PUT", device: String?, parameters: [String: String] = [:], json: [String: Any]? = nil) async throws {
        var components = URLComponents(string: "https://api.spotify.com/v1/me/player/\(name)")!
        var parameters = parameters; if let device { parameters["device_id"] = device }
        components.queryItems = parameters.map { URLQueryItem(name: $0.key, value: $0.value) }
        let body = try json.map { try JSONSerialization.data(withJSONObject: $0) }
        _ = try await request(components.url!.absoluteString, method: method, body: body)
    }
}
