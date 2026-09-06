import Foundation

public enum MenuAction: Sendable, Equatable {
    case music, artists, albums, tracks, artist(String), album(String), play(String)
    case spotify, liked, playlists, playlist(String), devices, device(String), desktop
    case settings, nowPlaying, importFiles, authorize, logout
}
public struct MenuRow: Identifiable, Sendable, Equatable {
    public var id: String
    public var title: String
    public var action: MenuAction
    public var displayTitle: String {
        switch action {
        case .artist: return title == "Неизвестный исполнитель" ? L10n.text(title) : title
        case .album: return title == "Неизвестный альбом" ? L10n.text(title) : title
        case .play, .playlist, .device: return title
        default: return L10n.text(title)
        }
    }
    public init(_ title: String, action: MenuAction, id: String? = nil) { self.title = title; self.action = action; self.id = id ?? title }
}
public struct MenuPage: Sendable {
    public var title: String
    public var rows: [MenuRow]
    public var selected = 0
    public var offset = 0
    public var nowPlaying = false
    public var localizedTitle: Bool
    public var displayTitle: String { localizedTitle ? L10n.text(title) : title }
    public init(title: String, rows: [MenuRow], nowPlaying: Bool = false, localizedTitle: Bool = false) { self.title = title; self.rows = rows; self.nowPlaying = nowPlaying; self.localizedTitle = localizedTitle }
}
public struct MenuNavigator: Sendable {
    public private(set) var stack: [MenuPage] = [MenuPage(title: "ClassicPod", rows: [
        MenuRow("Музыка", action: .music), MenuRow("Spotify", action: .spotify),
        MenuRow("Сейчас играет", action: .nowPlaying), MenuRow("Настройки", action: .settings)
    ])]
    public var current: MenuPage { stack.last! }
    public init() {}
    public mutating func push(_ page: MenuPage) { stack.append(page) }
    public mutating func back() { if stack.count > 1 { stack.removeLast() } }
    public mutating func step(_ delta: Int) {
        guard !current.rows.isEmpty else { return }
        let index = stack.count - 1
        stack[index].selected = min(max(0, current.selected + delta), current.rows.count - 1)
        let selected = stack[index].selected
        stack[index].offset = min(max(stack[index].offset, selected - 5), selected)
    }
    public var selectedAction: MenuAction? { current.rows.indices.contains(current.selected) ? current.rows[current.selected].action : nil }
}
