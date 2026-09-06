import SwiftUI
import AppKit
import PodCore

@main struct ClassicPodApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene {
        Settings { SettingsView(store: delegate.store) }
            .commands {
                CommandGroup(replacing: .newItem) { ImportMenuCommand(store: delegate.store) }
            }
    }
}
struct ImportMenuCommand: View {
    @ObservedObject var store: AppStore
    var body: some View { Button(L10n.text("Импортировать музыку…")) { store.importPanel() }.keyboardShortcut("o") }
}
final class PodWindow: NSWindow {
    var handleKey: ((NSEvent) -> Bool)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, handleKey?(event) == true { return }
        super.sendEvent(event)
    }
}
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = AppStore()
    private var window: NSWindow?
    private var settings: NSWindowController?
    private var observers: [NSObjectProtocol] = []
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let available = NSScreen.main?.visibleFrame.size ?? NSSize(width: 760, height: 760)
        let side = min(720, max(480, min(available.width, available.height) - 40))
        let window = PodWindow(contentRect: NSRect(x: 0, y: 0, width: side, height: side), styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
        window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = false
        window.minSize = NSSize(width: 480, height: 480); window.contentAspectRatio = NSSize(width: 1, height: 1)
        window.title = "ClassicPod"; window.collectionBehavior = [.fullScreenAuxiliary]
        window.handleKey = { [weak store] event in
            guard let store, event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return false }
            switch event.keyCode {
            case 53: store.escape()
            case 36, 76: store.input(.select)
            case 49: store.input(.playPause)
            case 125: store.input(.step(1))
            case 126: store.input(.step(-1))
            case 123: store.input(.previous)
            case 124: store.input(.next)
            default: return false
            }
            return true
        }
        window.contentView = NSHostingView(rootView: PodRootView(store: store))
        window.center(); window.makeKeyAndOrderFront(nil); self.window = window
        store.showSettings = { [weak self] in self?.openSettings() }
        store.languageChanged = { [weak self] in self?.settings?.window?.title = L10n.text("ClassicPod — Настройки и библиотека") }
        NSApp.activate(ignoringOtherApps: true)
        observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let visible = self.window?.occlusionState.contains(.visible) == true
                if visible { self.store.coordinator.spotify.startObserving() } else { self.store.coordinator.spotify.suspendPolling() }
            }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.store.coordinator.spotify.suspendPolling(); self?.store.click.stop() }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.store.coordinator.spotify.startObserving() }
        })
    }
    func openSettings() {
        if settings == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 570, height: 620), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.title = L10n.text("ClassicPod — Настройки и библиотека")
            window.contentView = NSHostingView(rootView: SettingsView(store: store)); window.center()
            settings = NSWindowController(window: window)
        }
        settings?.showWindow(nil); settings?.window?.makeKeyAndOrderFront(nil)
    }
    func applicationWillTerminate(_ notification: Notification) {
        store.shutdown()
        for observer in observers { NotificationCenter.default.removeObserver(observer); NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }
}
struct PodRootView: View {
    @ObservedObject var store: AppStore
    var body: some View {
        SCNViewRepresentable(store: store)
            .contextMenu {
                Button(L10n.text("Импортировать музыку…")) { store.importPanel() }
                Button(L10n.text("Настройки и библиотека…")) { store.showSettings?() }
                Button(L10n.text("Вид спереди — Escape")) { store.frontView() }
                Toggle(L10n.text("Поверх окон"), isOn: $store.alwaysOnTop)
                Divider()
                Button(L10n.text("Выйти")) { NSApp.terminate(nil) }
            }
            .alert("ClassicPod", isPresented: Binding(get: { store.message != nil }, set: { if !$0 { store.message = nil } })) {
                Button("OK") { store.message = nil }
            } message: { Text(store.message ?? "") }
    }
}
struct SettingsView: View {
    @ObservedObject var store: AppStore
    @AppStorage("spotifyClientID") private var clientID = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("ClassicPod").font(.largeTitle.bold())
            Picker(L10n.text("Язык"), selection: $store.language) {
                Text(L10n.text("Системный")).tag(AppLanguage.system)
                Text("English").tag(AppLanguage.english)
                Text("Русский").tag(AppLanguage.russian)
            }
            Text(L10n.text("Локальная музыка · Spotify Connect · Desktop Bridge")).foregroundStyle(.secondary)
            HStack { Toggle(L10n.text("Щелчок колеса"), isOn: $store.clickSound); Toggle(L10n.text("Поверх окон"), isOn: $store.alwaysOnTop) }
            Toggle(L10n.text("Инерция вращения"), isOn: $store.rotationInertia)
                .help(L10n.text("Плавное затухание после отпускания. Отключается при уменьшении движения в macOS."))
            GroupBox("Spotify") {
                VStack(alignment: .leading, spacing: 8) {
                    TextField(L10n.text("Spotify Client ID (не secret)"), text: $clientID).disabled(store.spotifyConnected || store.busy)
                    Text("Redirect URI: \(LoopbackCallback.redirect)").font(.caption).textSelection(.enabled)
                    HStack {
                        Button(store.spotifyConnected ? L10n.text("Переподключить") : L10n.text("Авторизоваться")) { store.authorize() }.disabled(store.busy)
                        Button(L10n.text("Выйти из аккаунта")) { store.logout() }.disabled(!store.spotifyConnected || store.busy)
                        if store.busy { Button(L10n.text("Отмена")) { store.cancelTask() }; ProgressView().controlSize(.small) }
                    }
                    Button(L10n.text("Управлять Spotify на этом Mac")) { store.select(.desktop) }
                    Text(L10n.text("Для Web API нужен Premium и собственное приложение в Spotify Dashboard. Мост требует открытый Spotify и разрешение Automation.")).font(.caption).foregroundStyle(.secondary)
                }.padding(6)
            }
            HStack { Text(L10n.format("Библиотека: %@", String(store.tracks.count))).font(.headline); Spacer(); Button(L10n.text("Импортировать…")) { store.importPanel() }.disabled(store.busy) }
            List(store.tracks) { track in
                HStack {
                    VStack(alignment: .leading) { Text(track.title); Text(track.displayArtist).font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    Button(L10n.text("Найти файл…")) { store.relocate(track) }.font(.caption)
                }
            }.frame(minHeight: 130)
            Text(L10n.text("Корпус: вращение 360° · Option-drag: переместить окно · Escape: вид спереди / назад · Колесо: меню · Space: Play/Pause")).font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(minWidth: 490, minHeight: 480)
    }
}
