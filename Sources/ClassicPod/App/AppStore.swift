import SwiftUI
import AppKit
import PodCore

@MainActor final class AppStore: ObservableObject {
    @Published var navigation = MenuNavigator()
    @Published var playback = PlaybackSnapshot(source: .local)
    @Published var tracks: [Track] = []
    @Published var message: String?
    @Published var busy = false
    @Published var modelRotated = false
    @Published var modelCoasting = false
    @Published var frontViewRevision = 0
    @Published var seeking = false
    @Published var clickSound = true
    @Published var rotationInertia = UserDefaults.standard.object(forKey: "rotationInertia") as? Bool ?? true {
        didSet { UserDefaults.standard.set(rotationInertia, forKey: "rotationInertia") }
    }
    @Published var alwaysOnTop = false
    @Published var spotifyConnected = false
    @Published var language = L10n.selection {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: L10n.preferenceKey)
            languageChanged?()
        }
    }
    var languageChanged: (() -> Void)?
    let library = LibraryStore()
    let oauth = SpotifyOAuth()
    let api: SpotifyWebAPI
    let coordinator: PlaybackCoordinator
    let click = ClickSound()
    var showSettings: (() -> Void)?
    private var trackCatalog: [String: Track] = [:]
    private var task: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?
    private var lastReportedError: String?
    init() {
        api = SpotifyWebAPI(oauth: oauth)
        coordinator = PlaybackCoordinator(spotify: SpotifyPlaybackService(api: api))
        spotifyConnected = oauth.signedIn
        coordinator.onChange = { [weak self] snapshot in
            self?.playback = snapshot
            if let error = snapshot.error, !error.isEmpty, error != self?.lastReportedError { self?.message = error }
            self?.lastReportedError = snapshot.error
        }
        coordinator.confirmUnstoppedSpotify = {
            let alert = NSAlert()
            alert.messageText = L10n.text("Остановка Spotify не подтверждена")
            alert.informativeText = L10n.text("Остановите Spotify вручную. Продолжайте только после остановки, иначе музыка может играть одновременно.")
            alert.addButton(withTitle: L10n.text("Отмена")); alert.addButton(withTitle: L10n.text("Я остановил Spotify"))
            return alert.runModal() == .alertSecondButtonReturn
        }
        loadTask = Task {
            do { tracks = try await library.load() } catch { message = error.localizedDescription }
        }
    }
    func input(_ event: InputEvent) {
        switch event {
        case .step(let delta):
            if clickSound { for _ in 0..<min(abs(delta), 12) { click.tick() } }
            if navigation.current.nowPlaying {
                enqueue {
                    let snapshot = self.coordinator.backend.snapshot
                    if self.seeking {
                        guard snapshot.capabilities.contains(.seek) else { return }
                        try await self.coordinator.backend.seek(snapshot.position() + Double(delta) * 5)
                    } else {
                        guard snapshot.capabilities.contains(.volume) else { return }
                        try await self.coordinator.backend.setVolume(snapshot.volume + Double(delta) * 0.04)
                    }
                }
            } else { navigation.step(delta) }
        case .menu:
            if busy { cancelTask() }
            else { navigation.back(); seeking = false }
        case .select:
            if navigation.current.nowPlaying { seeking.toggle() }
            else if !busy, let action = navigation.selectedAction { select(action) }
        case .playPause: enqueue { try await self.coordinator.toggle() }
        case .next: enqueue { try await self.coordinator.backend.next() }
        case .previous: enqueue { try await self.coordinator.backend.previous() }
        }
    }
    func frontView() { modelRotated = false; frontViewRevision += 1 }
    func escape() { if modelRotated || modelCoasting { frontView() } else { input(.menu) } }
    private func enqueue(_ action: @escaping @MainActor () async throws -> Void) {
        coordinator.serialized(action, failure: { [weak self] error in self?.message = error.localizedDescription })
    }
    private func push(_ title: String, _ rows: [MenuRow], localizedTitle: Bool = true) { navigation.push(MenuPage(title: title, rows: rows, localizedTitle: localizedTitle)) }
    private func trackPage(_ title: String, _ values: [Track], localizedTitle: Bool = false) {
        for track in values { trackCatalog[track.id] = track }
        push(title, values.map { MenuRow($0.title, action: .play($0.id), id: $0.id) }, localizedTitle: localizedTitle)
    }
    func select(_ action: MenuAction) {
        switch action {
        case .music: push("Музыка", [MenuRow("Исполнители", action: .artists), MenuRow("Альбомы", action: .albums), MenuRow("Треки", action: .tracks), MenuRow("Импортировать…", action: .importFiles)])
        case .artists: push("Исполнители", Set(tracks.map(\.artist)).sorted().map { MenuRow($0, action: .artist($0)) })
        case .albums: push("Альбомы", Set(tracks.map(\.album)).sorted().map { MenuRow($0, action: .album($0)) })
        case .artist(let artist): trackPage(artist, tracks.filter { $0.artist == artist }, localizedTitle: artist == "Неизвестный исполнитель")
        case .album(let album): trackPage(album, tracks.filter { $0.album == album }, localizedTitle: album == "Неизвестный альбом")
        case .tracks: trackPage("Треки", tracks, localizedTitle: true)
        case .play(let id):
            let values = navigation.current.rows.compactMap { row -> Track? in
                if case .play(let trackID) = row.action { return trackCatalog[trackID] }; return nil
            }
            guard let index = values.firstIndex(where: { $0.id == id }) else { return }
            enqueue { try await self.coordinator.play(values, at: index); self.nowPlaying() }
        case .nowPlaying: nowPlaying()
        case .settings: showSettings?()
        case .importFiles: importPanel()
        case .spotify:
            push("Spotify", [MenuRow("Liked Songs", action: .liked), MenuRow("Плейлисты", action: .playlists), MenuRow("Connect-устройства", action: .devices), MenuRow("Локальный мост (может открыть окно)", action: .desktop), MenuRow("Подключить аккаунт…", action: .authorize)])
        case .authorize: authorize()
        case .logout: logout()
        case .liked: run { self.trackPage("Liked Songs", try await self.api.liked()) }
        case .playlists: run { self.push("Плейлисты", try await self.api.playlists().map { MenuRow($0.name, action: .playlist($0.id), id: $0.id) }) }
        case .playlist(let id): run { self.trackPage("Spotify", try await self.api.tracks(playlist: id)) }
        case .devices:
            run { self.push("Устройства", try await self.api.devices().filter { $0.id != nil && $0.is_restricted != true }.map { MenuRow($0.name, action: .device($0.id!), id: $0.id) }) }
        case .device(let id):
            enqueue {
                try await self.coordinator.spotify.selectTransport(.connect(id))
                self.message = L10n.text("Connect-устройство выбрано. Выберите трек или нажмите Play.")
                try await self.coordinator.switchSource(.spotify)
            }
        case .desktop:
            enqueue {
                try await self.coordinator.spotify.selectTransport(.desktop)
                try await self.coordinator.switchSource(.spotify)
                try await self.coordinator.spotify.refresh()
                self.nowPlaying()
            }
        }
    }
    func nowPlaying() { if !navigation.current.nowPlaying { navigation.push(MenuPage(title: "Сейчас играет", rows: [], nowPlaying: true, localizedTitle: true)) }; seeking = false }
    func run(_ operation: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }; busy = true
        task = Task {
            defer { busy = false; task = nil }
            do { try await operation() } catch is CancellationError {} catch { message = error.localizedDescription }
        }
    }
    func cancelTask() { task?.cancel(); oauth.cancelAuthorization() }
    func authorize() { run { try await self.oauth.authorize(); self.spotifyConnected = true; self.message = L10n.text("Spotify подключён") } }
    func logout() {
        enqueue {
            if self.coordinator.source == .spotify { try await self.coordinator.switchSource(.local) }
            try self.oauth.logout(); self.spotifyConnected = false
        }
    }
    func importPanel() {
        let panel = NSOpenPanel(); panel.canChooseFiles = true; panel.canChooseDirectories = true; panel.allowsMultipleSelection = true
        panel.message = L10n.text("MP3, M4A, FLAC, WAV — файлы останутся на исходном месте")
        if panel.runModal() == .OK { importURLs(panel.urls) }
    }
    func importURLs(_ urls: [URL]) {
        run {
            await self.loadTask?.value
            let result = try await self.library.importURLs(urls)
            self.tracks = result.tracks
            self.message = result.errors.isEmpty ? L10n.format("Треков в библиотеке: %@", String(result.tracks.count)) : result.errors.joined(separator: "\n")
        }
    }
    func relocate(_ track: Track) {
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.message = L10n.format("Новый путь: %@", track.title)
        if panel.runModal() == .OK, let url = panel.url { run { self.tracks = try await self.library.relocate(id: track.id, to: url) } }
    }
    func shutdown() { task?.cancel(); loadTask?.cancel(); coordinator.shutdown(); click.stop() }
}
