import Foundation
import PodCore

@MainActor final class SpotifyPlaybackService: PlaybackBackend {
    enum Transport: Equatable { case automatic, desktop, connect(String) }
    let api: SpotifyWebAPI
    let bridge = SpotifyAppleEventBridge()
    private(set) var transport: Transport = .automatic
    private(set) var snapshot = PlaybackSnapshot(source: .spotify)
    var onChange: ((PlaybackSnapshot) -> Void)?
    private var polling: Task<Void, Never>?
    private var queue: [Track] = []
    private var index = 0
    private var active = false
    init(api: SpotifyWebAPI) { self.api = api }
    var deviceID: String? { if case .connect(let id) = transport { return id }; return nil }
    private func resolveTransport() async throws {
        guard transport == .automatic else { return }
        let devices = try await api.devices().filter { $0.is_active == true && $0.is_restricted != true && $0.id != nil }
        guard devices.count == 1, let id = devices.first?.id else {
            throw PodError.message(L10n.text("Выберите Connect-устройство в меню Spotify или запустите воспроизведение в Spotify вручную. Локальный мост автоматически не используется."))
        }
        transport = .connect(id)
    }
    func selectTransport(_ value: Transport) async throws {
        if value == .desktop { try await bridge.authorize() }
        if active && value != transport { try await pause() }
        transport = value
        snapshot = PlaybackSnapshot(source: .spotify)
        if active { try await refresh(); startObserving() }
    }
    func play(_ tracks: [Track], at index: Int) async throws {
        guard tracks.indices.contains(index) else { return }
        try await resolveTransport()
        queue = tracks; self.index = index; active = true
        switch transport {
        case .desktop:
            guard case .spotify(let uri) = tracks[index].location else { return }
            try await perform { _ = try await self.bridge.execute(.playURI(uri)) }
        case .automatic, .connect:
            let uris = tracks.dropFirst(index).prefix(100).compactMap { track -> String? in
                if case .spotify(let uri) = track.location { return uri }; return nil
            }
            try await perform { try await self.api.command("play", device: self.deviceID, json: ["uris": uris]) }
        }
        startObserving()
    }
    func resume() async throws {
        try await resolveTransport()
        active = true
        try await perform {
            switch self.transport {
            case .desktop: _ = try await self.bridge.execute(.play)
            case .automatic, .connect: try await self.api.command("play", device: self.deviceID)
            }
        }
        startObserving()
    }
    func pause() async throws {
        guard transport != .automatic else { return }
        switch transport {
        case .desktop: _ = try await bridge.execute(.pause)
        case .automatic, .connect: try await api.command("pause", device: deviceID)
        }
        for _ in 0..<3 {
            try await Task.sleep(for: .milliseconds(200))
            try await refresh()
            if !snapshot.playing { return }
        }
        throw PodError.message(L10n.text("Остановка Spotify не подтверждена. Остановите его вручную и повторите смену источника."))
    }
    func next() async throws {
        try await resolveTransport()
        if transport == .desktop && queue.indices.contains(index + 1) { try await play(queue, at: index + 1); return }
        try await perform {
            switch self.transport {
            case .desktop: _ = try await self.bridge.execute(.next)
            case .automatic, .connect: try await self.api.command("next", method: "POST", device: self.deviceID)
            }
        }
    }
    func previous() async throws {
        try await resolveTransport()
        if snapshot.position() > 3 { try await seek(0); return }
        if transport == .desktop && index > 0 { try await play(queue, at: index - 1); return }
        try await perform {
            switch self.transport {
            case .desktop: _ = try await self.bridge.execute(.previous)
            case .automatic, .connect: try await self.api.command("previous", method: "POST", device: self.deviceID)
            }
        }
    }
    func seek(_ seconds: Double) async throws {
        guard snapshot.capabilities.contains(.seek) else { throw PodError.message(L10n.text("Перемотка недоступна")) }
        let value = min(snapshot.duration, max(0, seconds))
        try await perform {
            switch self.transport {
            case .desktop: _ = try await self.bridge.execute(.seek(value))
            case .automatic, .connect: try await self.api.command("seek", device: self.deviceID, parameters: ["position_ms": String(Int(value * 1000))])
            }
        }
    }
    func setVolume(_ value: Double) async throws {
        guard snapshot.capabilities.contains(.volume) else { throw PodError.message(L10n.text("Громкость регулируется на устройстве Spotify")) }
        let value = min(1, max(0, value))
        try await perform {
            switch self.transport {
            case .desktop: _ = try await self.bridge.execute(.volume(value))
            case .automatic, .connect: try await self.api.command("volume", device: self.deviceID, parameters: ["volume_percent": String(Int(value * 100))])
            }
        }
    }
    private func perform(_ operation: () async throws -> Void) async throws {
        do { try await operation() }
        catch { try? await refresh(); throw error }
        try await refresh()
    }
    func refresh() async throws {
        switch transport {
        case .automatic: return
        case .desktop:
            guard let state = try await bridge.execute(.state) else { return }
            snapshot = state
        case .connect(let selectedID):
            guard let state = try await api.state() else { snapshot = PlaybackSnapshot(source: .spotify); onChange?(snapshot); return }
            guard state.device?.id == selectedID else { throw PodError.message(L10n.text("Spotify играет на другом устройстве. Выберите его в меню устройств.")) }
            snapshot.track = state.item?.track; snapshot.playing = state.is_playing
            snapshot.position = (state.progress_ms ?? 0) / 1000; snapshot.duration = snapshot.track?.duration ?? 0
            snapshot.volume = Double(state.device?.volume_percent ?? 50) / 100
            snapshot.capabilities = []
            if state.actions?.disallows?["seeking"] != true { snapshot.capabilities.insert(.seek) }
            if state.actions?.disallows?["skipping_next"] != true && state.actions?.disallows?["skipping_prev"] != true { snapshot.capabilities.insert(.skip) }
            if state.device?.supports_volume == true { snapshot.capabilities.insert(.volume) }
            snapshot.error = nil
        }
        snapshot.sampledAt = ProcessInfo.processInfo.systemUptime
        onChange?(snapshot)
    }
    func startObserving() {
        guard active, polling == nil else { return }
        polling = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(self?.transport == .desktop ? 1 : 5)) } catch { break }
                guard let self else { break }
                do { try await self.refresh() }
                catch { self.snapshot.error = error.localizedDescription; self.onChange?(self.snapshot) }
            }
        }
    }
    func activate() { active = true; startObserving() }
    func suspendPolling() { polling?.cancel(); polling = nil }
    func stopObserving() { active = false; suspendPolling() }
}
