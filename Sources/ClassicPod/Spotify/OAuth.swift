import AppKit
import CryptoKit
import Network
import Security
import PodCore

struct SpotifyTokens: Codable, Sendable {
    var accessToken: String
    var refreshToken: String
    var expires: Date
}
enum TokenVault {
    static let service = "dev.classicpod.spotify"
    static func load() throws -> SpotifyTokens? {
        var item: CFTypeRef?
        let status = SecItemCopyMatching([kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: "oauth", kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne] as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw PodError.message("Keychain: \(status)") }
        return try JSONDecoder().decode(SpotifyTokens.self, from: data)
    }
    static func save(_ tokens: SpotifyTokens) throws {
        let query = [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: "oauth"] as [CFString: Any]
        let data = try JSONEncoder().encode(tokens)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
        if status == errSecItemNotFound {
            var attributes = query; attributes[kSecValueData] = data; attributes[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let added = SecItemAdd(attributes as CFDictionary, nil)
            guard added == errSecSuccess else { throw PodError.message("Keychain: \(added)") }
        } else if status != errSecSuccess { throw PodError.message("Keychain: \(status)") }
    }
    static func delete() throws {
        let status = SecItemDelete([kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: "oauth"] as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw PodError.message("Keychain: \(status)") }
    }
}
enum PKCE {
    static func random() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw PodError.message(L10n.text("Не удалось создать OAuth nonce")) }
        return base64(Data(bytes))
    }
    static func base64(_ data: Data) -> String { data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
    static func challenge(_ verifier: String) -> String { base64(Data(SHA256.hash(data: Data(verifier.utf8)))) }
}
@MainActor final class LoopbackCallback {
    static let redirect = "http://127.0.0.1:43821/callback"
    private var listener: NWListener?
    private var continuation: CheckedContinuation<String, Error>?
    private var timeout: Task<Void, Never>?
    private var connections: [NWConnection] = []
    func receive(state: String, open: @escaping @MainActor @Sendable () -> Void) async throws -> String {
        guard continuation == nil else { throw PodError.message(L10n.text("Авторизация уже выполняется")) }
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: 43821)
        let server = try NWListener(using: parameters)
        listener = server
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                server.stateUpdateHandler = { status in
                    Task { @MainActor in
                        switch status {
                        case .ready: open()
                        case .failed(let error): self.finish(.failure(error))
                        default: break
                        }
                    }
                }
                server.newConnectionHandler = { connection in
                    Task { @MainActor in
                        self.connections.append(connection)
                        connection.start(queue: .main)
                        self.read(connection, data: Data(), state: state)
                    }
                }
                server.start(queue: .main)
                timeout = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(120)); self?.finish(.failure(PodError.message(L10n.text("Время авторизации истекло")))) } catch {}
                }
            }
        } onCancel: { Task { @MainActor in self.cancel() } }
    }
    private func read(_ connection: NWConnection, data: Data, state: String) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { content, _, complete, error in
            Task { @MainActor in
                var buffer = data; buffer.append(content ?? Data())
                guard buffer.count <= 16384, error == nil else { connection.cancel(); return }
                let request = String(decoding: buffer, as: UTF8.self)
                guard request.contains("\r\n\r\n") else {
                    if complete { connection.cancel() } else { self.read(connection, data: buffer, state: state) }; return
                }
                let parts = request.components(separatedBy: "\r\n")[0].split(separator: " ")
                guard parts.count >= 2, parts[0] == "GET", let components = URLComponents(string: "http://127.0.0.1\(parts[1])"), components.path == "/callback" else { connection.cancel(); return }
                let values = components.queryItems ?? []
                guard values.filter({ $0.name == "state" }).count == 1, values.first(where: { $0.name == "state" })?.value == state else { connection.cancel(); return }
                let code = values.first(where: { $0.name == "code" })?.value
                let response = "HTTP/1.1 200 OK\r\nContent-Type: text/plain; charset=utf-8\r\nConnection: close\r\n\r\nReturn to ClassicPod. You may close this tab."
                connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
                    Task { @MainActor in
                        if let code { self.finish(.success(code)) }
                        else { self.finish(.failure(PodError.message(L10n.text("Авторизация отменена или отклонена Spotify")))) }
                    }
                })
            }
        }
    }
    func cancel() { finish(.failure(CancellationError())) }
    private func finish(_ result: Result<String, Error>) {
        guard let continuation else { return }
        self.continuation = nil; timeout?.cancel(); timeout = nil
        let server = listener; listener = nil
        connections.forEach { $0.cancel() }; connections.removeAll()
        if let server {
            server.newConnectionHandler = nil
            server.stateUpdateHandler = { status in
                if case .cancelled = status { continuation.resume(with: result) }
            }
            server.cancel()
        } else { continuation.resume(with: result) }
    }
}
@MainActor final class SpotifyOAuth {
    var clientID: String { UserDefaults.standard.string(forKey: "spotifyClientID") ?? "" }
    private var tokens: SpotifyTokens?
    private var refreshTask: Task<SpotifyTokens, Error>?
    private var generation = 0
    private let callback = LoopbackCallback()
    private let session: URLSession
    private let persistTokens: Bool
    var signedIn: Bool { tokens != nil }
    init(session: URLSession = .shared, initialTokens: SpotifyTokens? = nil, persistTokens: Bool = true) {
        self.session = session; self.persistTokens = persistTokens
        tokens = persistTokens ? (try? TokenVault.load()) : initialTokens
    }
    func authorize() async throws {
        guard !clientID.isEmpty else { throw PodError.message(L10n.text("Укажите Spotify Client ID в настройках")) }
        let verifier = try PKCE.random(), state = try PKCE.random()
        var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
        components.queryItems = ["client_id": clientID, "response_type": "code", "redirect_uri": LoopbackCallback.redirect,
                                "code_challenge_method": "S256", "code_challenge": PKCE.challenge(verifier), "state": state,
                                "scope": "user-read-private user-library-read playlist-read-private playlist-read-collaborative user-read-playback-state user-modify-playback-state"].map { URLQueryItem(name: $0.key, value: $0.value) }
        let capturedGeneration = generation
        let url = components.url!
        let code = try await callback.receive(state: state) { NSWorkspace.shared.open(url) }
        let result = try await exchange(["grant_type": "authorization_code", "code": code, "redirect_uri": LoopbackCallback.redirect, "code_verifier": verifier], previousRefresh: nil)
        guard generation == capturedGeneration else { throw CancellationError() }
        if persistTokens { try TokenVault.save(result) }; tokens = result
    }
    func accessToken(force: Bool = false) async throws -> String {
        if let refreshTask {
            let capturedGeneration = generation
            let result = try await refreshTask.value
            guard generation == capturedGeneration else { throw CancellationError() }
            return result.accessToken
        }
        guard let tokens else { throw PodError.message(L10n.text("Сначала подключите Spotify")) }
        if !force && tokens.expires.timeIntervalSinceNow > 60 { return tokens.accessToken }
        let capturedGeneration = generation
        let task = Task { try await self.exchange(["grant_type": "refresh_token", "refresh_token": tokens.refreshToken], previousRefresh: tokens.refreshToken) }
        refreshTask = task
        defer { if generation == capturedGeneration { refreshTask = nil } }
        let result = try await task.value
        guard generation == capturedGeneration else { throw CancellationError() }
        if persistTokens { try TokenVault.save(result) }; self.tokens = result
        return result.accessToken
    }
    func cancelAuthorization() { callback.cancel() }
    func logout() throws { generation += 1; callback.cancel(); refreshTask?.cancel(); refreshTask = nil; tokens = nil; if persistTokens { try TokenVault.delete() } }
    private func exchange(_ fields: [String: String], previousRefresh: String?) async throws -> SpotifyTokens {
        var fields = fields; fields["client_id"] = clientID
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let body = fields.sorted(by: { $0.key < $1.key }).map { "\($0.key.addingPercentEncoding(withAllowedCharacters: allowed)!)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed)!)" }.joined(separator: "&")
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"; request.httpBody = Data(body.utf8); request.timeoutInterval = 20
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw PodError.message(L10n.text("Spotify OAuth отклонил запрос. Проверьте Client ID, redirect URI и доступ аккаунта.")) }
        struct Reply: Decodable { var access_token: String; var refresh_token: String?; var expires_in: Double }
        let reply = try JSONDecoder().decode(Reply.self, from: data)
        guard let refresh = reply.refresh_token ?? previousRefresh else { throw PodError.message(L10n.text("Spotify не вернул refresh token")) }
        return SpotifyTokens(accessToken: reply.access_token, refreshToken: refresh, expires: Date().addingTimeInterval(reply.expires_in))
    }
}
