import AVFoundation
import MediaPlayer
import AppKit
import PodCore

@MainActor final class LocalPlaybackService: PlaybackBackend {
    let player = AVQueuePlayer()
    private(set) var snapshot = PlaybackSnapshot(source: .local)
    var onChange: ((PlaybackSnapshot) -> Void)?
    private var tracks: [Track] = []
    private var index = 0
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var failedObserver: NSObjectProtocol?
    private var statusObserver: NSKeyValueObservation?
    private var remoteTargets: [(MPRemoteCommand, Any)] = []
    private let systemIntegration: Bool
    init(systemIntegration: Bool = true) { self.systemIntegration = systemIntegration; snapshot.capabilities = .all; player.volume = 0.5 }
    func play(_ tracks: [Track], at index: Int) async throws {
        guard tracks.indices.contains(index) else { return }
        self.tracks = tracks; self.index = index
        try loadCurrent()
    }
    private func loadCurrent() throws {
        clearObservers()
        player.removeAllItems()
        var errors: [String] = []
        while tracks.indices.contains(index) {
            do {
                let url = try LibraryStore.resolve(tracks[index])
                let item = AVPlayerItem(url: url)
                player.actionAtItemEnd = .pause
                player.insert(item, after: nil)
                let itemID = ObjectIdentifier(item)
                snapshot.track = tracks[index]; snapshot.duration = tracks[index].duration; snapshot.position = 0
                snapshot.error = errors.isEmpty ? nil : errors.joined(separator: "\n")
                endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
                    Task { @MainActor in
                        guard let self, self.player.currentItem.map(ObjectIdentifier.init) == itemID else { return }
                        try? await self.next()
                    }
                }
                failedObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { [weak self] _ in
                    Task { @MainActor in
                        guard let self, self.player.currentItem.map(ObjectIdentifier.init) == itemID else { return }
                        self.skipFailed()
                    }
                }
                statusObserver = item.observe(\.status, options: [.new]) { [weak self] observed, _ in
                    if observed.status == .failed {
                        Task { @MainActor in
                            guard let self, self.player.currentItem.map(ObjectIdentifier.init) == itemID else { return }
                            self.skipFailed()
                        }
                    }
                }
                timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] _ in
                    Task { @MainActor in self?.publish() }
                }
                claimRemoteCommands()
                player.play(); publish(); return
            } catch { errors.append(error.localizedDescription); index += 1 }
        }
        snapshot.playing = false; snapshot.error = errors.joined(separator: "\n"); publish()
        throw PodError.message(errors.isEmpty ? L10n.text("Очередь пуста") : errors.joined(separator: "\n"))
    }
    private func skipFailed() {
        let message = L10n.format("Пропущен повреждённый файл: %@", snapshot.track?.title ?? "")
        index += 1
        if tracks.indices.contains(index) { try? loadCurrent() } else { player.pause(); clearObservers() }
        snapshot.error = message; publish()
    }
    func resume() async throws {
        guard player.currentItem != nil else { return }
        if timeObserver == nil, tracks.indices.contains(index) { try loadCurrent(); return }
        if player.currentTime().seconds >= snapshot.duration && snapshot.duration > 0 { try await seek(0) }
        claimRemoteCommands(); player.play(); publish()
    }
    func pause() async throws { player.pause(); publish() }
    func next() async throws {
        guard index + 1 < tracks.count else { player.pause(); clearObservers(); snapshot.position = snapshot.duration; publish(); return }
        index += 1; try loadCurrent()
    }
    func previous() async throws {
        if player.currentTime().seconds > 3 { try await seek(0) }
        else if index > 0 { index -= 1; try loadCurrent() }
        else { try await seek(0) }
    }
    func seek(_ seconds: Double) async throws {
        await player.seek(to: CMTime(seconds: min(max(0, seconds), snapshot.duration), preferredTimescale: 600))
        publish()
    }
    func setVolume(_ value: Double) async throws { player.volume = Float(min(1, max(0, value))); publish() }
    func stopObserving() { clearObservers(); releaseRemoteCommands() }
    private func clearObservers() {
        if let timeObserver { player.removeTimeObserver(timeObserver) }; timeObserver = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }; endObserver = nil
        if let failedObserver { NotificationCenter.default.removeObserver(failedObserver) }; failedObserver = nil
        statusObserver = nil
    }
    private func publish() {
        let position = player.currentTime().seconds
        snapshot.position = position.isFinite ? position : 0
        snapshot.playing = player.rate > 0; snapshot.volume = Double(player.volume)
        snapshot.sampledAt = ProcessInfo.processInfo.systemUptime
        if let duration = player.currentItem?.duration.seconds, duration.isFinite { snapshot.duration = duration }
        onChange?(snapshot)
        if !remoteTargets.isEmpty {
            var info: [String: Any] = [MPMediaItemPropertyTitle: snapshot.track?.title ?? "", MPMediaItemPropertyArtist: snapshot.track?.artist ?? "", MPMediaItemPropertyPlaybackDuration: snapshot.duration, MPNowPlayingInfoPropertyElapsedPlaybackTime: snapshot.position, MPNowPlayingInfoPropertyPlaybackRate: snapshot.playing ? 1.0 : 0.0]
            if let data = snapshot.track?.artwork, let image = NSImage(data: data) {
                info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            }
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
            MPNowPlayingInfoCenter.default().playbackState = snapshot.playing ? .playing : .paused
        }
    }
    func releaseRemoteCommands() {
        for (command, token) in remoteTargets { command.removeTarget(token) }
        remoteTargets.removeAll()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
    }
    private func claimRemoteCommands() {
        guard systemIntegration, remoteTargets.isEmpty else { return }
        let center = MPRemoteCommandCenter.shared()
        func add(_ command: MPRemoteCommand, action: @escaping @MainActor (LocalPlaybackService) async throws -> Void) {
            let token = command.addTarget { [weak self] _ in
                Task { @MainActor in if let self { try? await action(self) } }; return .success
            }
            remoteTargets.append((command, token))
        }
        add(center.playCommand) { try await $0.resume() }
        add(center.pauseCommand) { try await $0.pause() }
        add(center.togglePlayPauseCommand) { service in if service.snapshot.playing { try await service.pause() } else { try await service.resume() } }
        add(center.nextTrackCommand) { try await $0.next() }; add(center.previousTrackCommand) { try await $0.previous() }
        let token = center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let position = event.positionTime
            Task { @MainActor in try? await self?.seek(position) }; return .success
        }
        remoteTargets.append((center.changePlaybackPositionCommand, token))
    }
}
