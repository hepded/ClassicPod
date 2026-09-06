import SpriteKit
import AppKit
import PodCore

@MainActor final class VirtualDisplay {
    let scene = SKScene(size: CGSize(width: 320, height: 240))
    private let rasterizer = SKView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
    private(set) var image = NSImage(size: NSSize(width: 320, height: 240))
    private var marquees: [(SKLabelNode, CGFloat, Double)] = []
    private let progress = SKSpriteNode(color: NSColor(calibratedRed: 0.13, green: 0.43, blue: 0.82, alpha: 1), size: CGSize(width: 0, height: 6))
    private let timeLabel = SKLabelNode(fontNamed: "Menlo")
    private var snapshot = PlaybackSnapshot(source: .local)
    private var pageIsNowPlaying = false
    private var signature = ""
    private var artworkTask: Task<Void, Never>?
    private let artworkCache = NSCache<NSURL, NSImage>()
    private(set) var hasAnimations = false
    var onVisualChange: (() -> Void)?
    init() {
        scene.backgroundColor = NSColor(calibratedWhite: 0.96, alpha: 1); scene.scaleMode = .resizeFill; artworkCache.countLimit = 30
        rasterizer.presentScene(scene); rasterizer.isPaused = true; scene.isPaused = true
    }
    private func capture() {
        guard let texture = rasterizer.texture(from: scene, crop: CGRect(origin: .zero, size: scene.size)) else { return }
        image = NSImage(cgImage: texture.cgImage(), size: scene.size)
        onVisualChange?()
    }
    func render(page: MenuPage, playback: PlaybackSnapshot, seeking: Bool, busy: Bool) {
        snapshot = playback; pageIsNowPlaying = page.nowPlaying
        let signature = "\(L10n.language.rawValue)|\(page.displayTitle)|\(page.selected)|\(page.offset)|\(page.rows.map(\.displayTitle))|\(page.nowPlaying)|\(playback.track?.id ?? "")|\(playback.playing)|\(seeking)|\(busy)|\(Int(playback.volume * 100))"
        guard signature != self.signature else { updateTime(); return }
        self.signature = signature; artworkTask?.cancel(); artworkTask = nil; marquees.removeAll(); scene.removeAllChildren(); hasAnimations = false
        defer { capture() }
        let header = SKSpriteNode(color: NSColor(calibratedWhite: 0.84, alpha: 1), size: CGSize(width: 320, height: 28))
        header.position = CGPoint(x: 160, y: 226); scene.addChild(header)
        label(page.displayTitle, x: 10, y: 220, size: 16, bold: true)
        label(busy ? "…" : (playback.playing ? "▶" : "Ⅱ"), x: 263, y: 220, size: 13)
        let battery = SKShapeNode(rectOf: CGSize(width: 22, height: 10), cornerRadius: 1)
        battery.strokeColor = .darkGray; battery.fillColor = NSColor(calibratedRed: 0.35, green: 0.68, blue: 0.3, alpha: 1)
        battery.position = CGPoint(x: 298, y: 228); scene.addChild(battery)
        if busy { label(L10n.text("Загрузка… Menu — отмена"), x: 18, y: 112, size: 16); return }
        if page.nowPlaying {
            guard let track = playback.track else { label(L10n.text("Выберите музыку"), x: 20, y: 120, size: 20); return }
            let cover = SKSpriteNode(color: NSColor(calibratedWhite: 0.83, alpha: 1), size: CGSize(width: 100, height: 100))
            cover.position = CGPoint(x: 64, y: 148); scene.addChild(cover)
            let placeholder = label("♫", x: 44, y: 132, size: 44, color: .gray)
            if let data = track.artwork, let image = NSImage(data: data) { cover.texture = SKTexture(image: image); placeholder.removeFromParent() }
            else if let url = track.artworkURL {
                if let image = artworkCache.object(forKey: url as NSURL) { cover.texture = SKTexture(image: image); placeholder.removeFromParent() }
                else {
                    artworkTask = Task { [weak self, weak cover, weak placeholder] in
                        do {
                            guard url.scheme == "https" else { return }
                            var request = URLRequest(url: url); request.timeoutInterval = 10
                            let (data, response) = try await URLSession.shared.data(for: request)
                            try Task.checkCancellation()
                            guard (response as? HTTPURLResponse)?.statusCode == 200, data.count < 10_000_000, let image = NSImage(data: data) else { return }
                            self?.artworkCache.setObject(image, forKey: url as NSURL); cover?.texture = SKTexture(image: image); placeholder?.removeFromParent(); self?.capture()
                        } catch {}
                    }
                }
            }
            scrollingLabel(track.title, x: 125, y: 173, width: 183, size: 18, bold: true)
            scrollingLabel(track.displayArtist, x: 125, y: 146, width: 183, size: 15)
            scrollingLabel(track.displayAlbum, x: 125, y: 122, width: 183, size: 13)
            label(playback.source == .local ? "LOCAL MUSIC" : "SPOTIFY", x: 14, y: 76, size: 10, color: .gray)
            let rail = SKSpriteNode(color: .lightGray, size: CGSize(width: 292, height: 6)); rail.position = CGPoint(x: 160, y: 57); scene.addChild(rail)
            progress.anchorPoint = CGPoint(x: 0, y: 0.5); progress.position = CGPoint(x: 14, y: 57); scene.addChild(progress)
            timeLabel.fontSize = 11; timeLabel.fontColor = .darkGray; timeLabel.horizontalAlignmentMode = .left
            timeLabel.position = CGPoint(x: 14, y: 35); scene.addChild(timeLabel)
            label(seeking ? L10n.text("ПЕРЕМОТКА · шаг 5 с") : L10n.format("ГРОМКОСТЬ %@%% · Select: позиция", String(Int(playback.volume * 100))), x: 14, y: 12, size: 10, color: .gray)
            updateTime()
        } else if page.rows.isEmpty { label(L10n.text("Пока пусто"), x: 18, y: 120, size: 20) }
        else {
            for index in page.offset..<min(page.offset + 6, page.rows.count) {
                let y = CGFloat(182 - (index - page.offset) * 30)
                let selected = index == page.selected
                if selected {
                    let bar = SKSpriteNode(color: NSColor(calibratedRed: 0.1, green: 0.42, blue: 0.85, alpha: 1), size: CGSize(width: 320, height: 30))
                    bar.position = CGPoint(x: 160, y: y + 6); scene.addChild(bar)
                }
                if selected { scrollingLabel(page.rows[index].displayTitle, x: 12, y: y, width: 275, size: 18, bold: true, color: .white) }
                else { label(String(page.rows[index].displayTitle.prefix(28)), x: 12, y: y, size: 18) }
                label("›", x: 297, y: y - 1, size: 23, color: selected ? .white : .gray)
            }
            label("\(page.selected + 1) / \(page.rows.count)", x: 12, y: 9, size: 10, color: .gray)
        }
    }
    func updateTime() {
        let now = ProcessInfo.processInfo.systemUptime
        for (node, overflow, started) in marquees {
            let duration = Double(overflow / 25)
            let phase = (now - started).truncatingRemainder(dividingBy: duration + 3)
            node.position.x = phase < 1.5 ? 0 : -min(overflow, CGFloat(phase - 1.5) * 25)
        }
        guard pageIsNowPlaying else { if hasAnimations { capture() }; return }
        let position = snapshot.position()
        progress.size.width = snapshot.duration > 0 ? 292 * position / snapshot.duration : 0
        func format(_ value: Double) -> String { let value = Int(max(0, value)); return String(format: "%d:%02d", value / 60, value % 60) }
        timeLabel.text = "\(format(position))                         −\(format(snapshot.duration - position))"
        if snapshot.playing || hasAnimations { capture() }
    }
    @discardableResult private func label(_ text: String, x: CGFloat, y: CGFloat, size: CGFloat, bold: Bool = false, color: NSColor = .black) -> SKLabelNode {
        let node = SKLabelNode(fontNamed: bold ? "Helvetica-Bold" : "Helvetica")
        node.text = text; node.fontSize = size; node.fontColor = color; node.horizontalAlignmentMode = .left
        node.position = CGPoint(x: x, y: y); scene.addChild(node); return node
    }
    private func scrollingLabel(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat, size: CGFloat, bold: Bool = false, color: NSColor = .black) {
        let node = label(text, x: 0, y: 0, size: size, bold: bold, color: color)
        node.removeFromParent()
        let crop = SKCropNode(); crop.position = CGPoint(x: x, y: y)
        let mask = SKSpriteNode(color: .white, size: CGSize(width: width, height: 30)); mask.anchorPoint = CGPoint(x: 0, y: 0.25)
        crop.maskNode = mask; crop.addChild(node); scene.addChild(crop)
        let overflow = node.frame.width - width
        if overflow > 0 {
            hasAnimations = true
            marquees.append((node, overflow, ProcessInfo.processInfo.systemUptime))
        }
    }
}
