import Foundation
import PodCore

@MainActor final class PlaybackCoordinator {
    let local = LocalPlaybackService()
    let spotify: SpotifyPlaybackService
    private(set) var source: PlaybackSource = .local
    var onChange: ((PlaybackSnapshot) -> Void)?
    var confirmUnstoppedSpotify: (() async -> Bool)?
    private var commandTail: Task<Void, Never>?
    var backend: any PlaybackBackend { source == .local ? local : spotify }
    init(spotify: SpotifyPlaybackService) {
        self.spotify = spotify
        local.onChange = { [weak self] snapshot in if self?.source == .local { self?.onChange?(snapshot) } }
        spotify.onChange = { [weak self] snapshot in if self?.source == .spotify { self?.onChange?(snapshot) } }
    }
    func serialized(_ action: @escaping @MainActor () async throws -> Void, failure: @escaping @MainActor (Error) -> Void) {
        let previous = commandTail
        commandTail = Task {
            await previous?.value
            guard !Task.isCancelled else { return }
            do { try await action() } catch { failure(error) }
        }
    }
    func switchSource(_ target: PlaybackSource) async throws {
        guard target != source else { return }
        do { try await backend.pause() }
        catch {
            guard source == .spotify, await confirmUnstoppedSpotify?() == true else { throw error }
        }
        if source == .local { local.releaseRemoteCommands() } else { spotify.stopObserving() }
        source = target
        if target == .spotify { spotify.activate() }
        onChange?(backend.snapshot)
    }
    func play(_ tracks: [Track], at index: Int) async throws {
        guard tracks.indices.contains(index) else { return }
        let target: PlaybackSource
        switch tracks[index].location { case .local: target = .local; case .spotify: target = .spotify }
        try await switchSource(target); try await backend.play(tracks, at: index)
    }
    func toggle() async throws { if backend.snapshot.playing { try await backend.pause() } else { try await backend.resume() } }
    func shutdown() { commandTail?.cancel(); local.player.pause(); local.stopObserving(); spotify.stopObserving() }
}
