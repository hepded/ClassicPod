import Foundation

public enum InputEvent: Sendable { case step(Int), menu, select, playPause, next, previous }
public enum PlaybackSource: String, Codable, Sendable { case local, spotify }
public enum TrackLocation: Codable, Sendable, Equatable {
    case local(bookmark: Data, path: String)
    case spotify(uri: String)
}
public struct Track: Codable, Identifiable, Sendable, Equatable {
    public var id: String
    public var title: String
    public var artist: String
    public var album: String
    public var duration: Double
    public var artwork: Data?
    public var artworkURL: URL?
    public var location: TrackLocation
    public var displayArtist: String { artist == "Неизвестный исполнитель" ? L10n.text(artist) : artist }
    public var displayAlbum: String { album == "Неизвестный альбом" ? L10n.text(album) : album }
    public init(id: String, title: String, artist: String = "Неизвестный исполнитель", album: String = "Неизвестный альбом", duration: Double = 0, artwork: Data? = nil, artworkURL: URL? = nil, location: TrackLocation) {
        self.id = id; self.title = title; self.artist = artist; self.album = album
        self.duration = duration; self.artwork = artwork; self.artworkURL = artworkURL; self.location = location
    }
}
public struct Capabilities: OptionSet, Sendable, Equatable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let seek = Self(rawValue: 1)
    public static let volume = Self(rawValue: 2)
    public static let skip = Self(rawValue: 4)
    public static let all: Self = [.seek, .volume, .skip]
}
public struct PlaybackSnapshot: Sendable {
    public var source: PlaybackSource
    public var track: Track?
    public var playing = false
    public var position: Double = 0
    public var duration: Double = 0
    public var volume: Double = 0.5
    public var capabilities: Capabilities = []
    public var error: String?
    public var sampledAt = ProcessInfo.processInfo.systemUptime
    public init(source: PlaybackSource) { self.source = source }
    public func position(at time: Double = ProcessInfo.processInfo.systemUptime) -> Double {
        min(max(0, duration), max(0, position + (playing ? max(0, time - sampledAt) : 0)))
    }
}
public enum PodError: LocalizedError, Sendable {
    case message(String)
    public var errorDescription: String? { if case .message(let message) = self { return message }; return nil }
}
