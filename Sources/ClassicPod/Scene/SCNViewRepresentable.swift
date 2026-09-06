import SwiftUI
import SceneKit
import PodCore

struct SCNViewRepresentable: NSViewRepresentable {
    @ObservedObject var store: AppStore
    func makeNSView(context: Context) -> PodSCNView { PodSCNView(store: store) }
    func updateNSView(_ view: PodSCNView, context: Context) { view.update() }
    static func dismantleNSView(_ view: PodSCNView, coordinator: ()) { view.stop() }
}
@MainActor final class PodSCNView: SCNView {
    private let store: AppStore
    let pod = PodScene()
    private var wheelGesture = ClickWheel()
    private(set) var gesture = PodGesture.none
    private var rotation = RotationController()
    private var pressed: SIMD2<Double>?
    private var frontViewRevision = 0
    private var timer: Timer?
    private var inertiaTimer: Timer?
    private var inertiaTime = 0.0
    private var renderUntil = 0.0
    private var accessibilityButtons: [PodAccessibleButton] = []
    private var accessibilityLanguage = L10n.language
    override var acceptsFirstResponder: Bool { true }
    init(store: AppStore) {
        self.store = store
        super.init(frame: .zero, options: [SCNView.Option.preferredRenderingAPI.rawValue: SCNRenderingAPI.metal.rawValue])
        scene = pod.scene; pointOfView = pod.camera; backgroundColor = .clear
        antialiasingMode = .multisampling4X; preferredFramesPerSecond = 30; isPlaying = true; rendersContinuously = true
        autoenablesDefaultLighting = false
        registerForDraggedTypes([.fileURL]); setAccessibilityLabel(L10n.text("ClassicPod — 3D музыкальный плеер"))
        setAccessibilityElement(true); setAccessibilityRole(.group)
        pod.display.onVisualChange = { [weak self] in self?.pod.updateDisplayTexture(); self?.requestFrame() }
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let burst = ProcessInfo.processInfo.systemUptime < self.renderUntil
                let windowVisible = self.window?.occlusionState.contains(.visible) == true
                let visible = windowVisible || burst
                let animate = visible && (burst || self.gesture == .rotate || self.store.playback.playing || self.pod.display.hasAnimations)
                self.isPlaying = animate
                self.rendersContinuously = animate
                if windowVisible { self.pod.display.updateTime() }
            }
        }
        update()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    func stop() { timer?.invalidate(); timer = nil; stopInertia(); isPlaying = false }
    private func stopInertia() {
        inertiaTimer?.invalidate(); inertiaTimer = nil; rotation.stopInertia()
        if store.modelCoasting { store.modelCoasting = false }
    }
    private var inertiaEnabled: Bool { store.rotationInertia && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    private func startInertia() {
        guard rotation.isCoasting else { return }
        store.modelCoasting = true
        inertiaTime = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                guard self.inertiaEnabled, self.window?.occlusionState.contains(.visible) == true, self.gesture == .none else { self.stopInertia(); return }
                let now = ProcessInfo.processInfo.systemUptime
                if self.rotation.advance(by: now - self.inertiaTime) {
                    self.applyRotation()
                }
                self.inertiaTime = now
                if !self.rotation.isCoasting { self.stopInertia() }
            }
        }
        inertiaTimer = timer; RunLoop.main.add(timer, forMode: .common)
    }
    private func applyRotation() {
        pod.modelRoot.simdOrientation = simd_quatf(vector: SIMD4<Float>(rotation.orientation.vector))
        let rotated = !rotation.isFront
        if store.modelRotated != rotated { store.modelRotated = rotated }
        requestFrame()
    }
    func update() {
        if !inertiaEnabled { stopInertia() }
        if accessibilityLanguage != L10n.language {
            accessibilityLanguage = L10n.language
            accessibilityButtons.removeAll()
            setAccessibilityLabel(L10n.text("ClassicPod — 3D музыкальный плеер"))
            NSAccessibility.post(element: self, notification: .layoutChanged)
        }
        requestFrame()
        allowsCameraControl = false
        if frontViewRevision != store.frontViewRevision {
            stopInertia()
            frontViewRevision = store.frontViewRevision; rotation.reset(); pod.modelRoot.simdOrientation = simd_quatf(vector: SIMD4<Float>(rotation.orientation.vector))
            gesture = .none; pressed = nil; wheelGesture.end()
        }
        window?.level = store.alwaysOnTop ? .floating : .normal
        pod.display.render(page: store.navigation.current, playback: store.playback, seeking: store.seeking, busy: store.busy)
        let page = store.navigation.current
        let selected = page.rows.indices.contains(page.selected) ? page.rows[page.selected].displayTitle : ""
        setAccessibilityValue("\(page.displayTitle). \(selected). \(store.playback.track?.title ?? "")")
        needsDisplay = true
    }
    private func requestFrame() {
        renderUntil = ProcessInfo.processInfo.systemUptime + 0.6
        isPlaying = true; rendersContinuously = true; needsDisplay = true
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow(); window?.makeFirstResponder(self); update()
    }
    private func point(_ event: NSEvent) -> CGPoint { convert(event.locationInWindow, from: nil) }
    func surface(at location: CGPoint) -> PodHitSurface {
        guard let hit = hitTest(location, options: [.searchMode: SCNHitTestSearchMode.closest.rawValue, .backFaceCulling: true]).first else { return .none }
        var node: SCNNode? = hit.node
        while let current = node, current !== pod.modelRoot {
            if current.name == "CenterButton" { return .center }
            if current.name == "ClickWheel" { return .wheel }
            node = current.parent
        }
        return .body
    }
    private var rotationSize: SIMD2<Double> { SIMD2(bounds.width, bounds.height) }
    private func rotationPoint(_ point: CGPoint) -> SIMD2<Double> { SIMD2(point.x, isFlipped ? bounds.height - point.y : point.y) }
    private func wheelPoint(_ location: CGPoint) -> SIMD2<Double>? {
        let near = unprojectPoint(SCNVector3(Float(location.x), Float(location.y), 0))
        let far = unprojectPoint(SCNVector3(Float(location.x), Float(location.y), 1))
        let origin = pod.wheel.convertPosition(near, from: nil)
        let end = pod.wheel.convertPosition(far, from: nil)
        let direction = SCNVector3(end.x - origin.x, end.y - origin.y, end.z - origin.z)
        guard abs(direction.z) > 0.000001 else { return nil }
        let distance = -origin.z / direction.z
        guard distance >= 0 else { return nil }
        return SIMD2(Double(origin.x + direction.x * distance) / 2, Double(origin.y + direction.y * distance) / 2)
    }
    override func mouseDown(with event: NSEvent) {
        stopInertia()
        window?.makeFirstResponder(self)
        let location = point(event)
        gesture = PodGesture.choose(surface: surface(at: location), optionDown: event.modifierFlags.contains(.option))
        switch gesture {
        case .moveWindow: window?.performDrag(with: event); gesture = .none
        case .rotate: rotation.begin(point: rotationPoint(location), size: rotationSize, time: event.timestamp)
        case .wheel:
            guard let local = wheelPoint(location), hypot(local.x, local.y) <= 1.02 else { gesture = .none; return }
            pressed = local; wheelGesture.begin(x: local.x, y: local.y, screenX: location.x, screenY: location.y)
        case .none: break
        }
    }
    override func mouseDragged(with event: NSEvent) {
        let location = point(event)
        if gesture == .rotate {
            rotation.drag(point: rotationPoint(location), size: rotationSize, time: event.timestamp)
            applyRotation(); return
        }
        guard gesture == .wheel else { return }
        guard let local = wheelPoint(location) else { return }
        let steps = wheelGesture.move(x: local.x, y: local.y, screenX: location.x, screenY: location.y)
        if steps != 0 { store.input(.step(steps)) }
    }
    override func mouseUp(with event: NSEvent) {
        defer {
            rotation.end(time: event.timestamp, inertia: gesture == .rotate && inertiaEnabled)
            gesture = .none; pressed = nil; wheelGesture.end(); startInertia()
        }
        if gesture == .wheel, !wheelGesture.cancelledClick, let pressed { store.input(ClickWheel.button(x: pressed.x, y: pressed.y)) }
    }
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: store.escape()
        case 36, 76: store.input(.select)
        case 49: store.input(.playPause)
        case 125: store.input(.step(1))
        case 126: store.input(.step(-1))
        case 123: store.input(.previous)
        case 124: store.input(.next)
        default: super.keyDown(with: event)
        }
    }
    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation { .copy }
    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty else { return false }
        store.importURLs(urls); return true
    }
    override func accessibilityChildren() -> [Any]? {
        if !accessibilityButtons.isEmpty { return accessibilityButtons }
        let actions: [(String, InputEvent)] = [(L10n.text("Menu — назад"), .menu), (L10n.text("Выбрать"), .select), ("Play / Pause", .playPause), (L10n.text("Следующий трек"), .next), (L10n.text("Предыдущий трек"), .previous), (L10n.text("Вниз"), .step(1)), (L10n.text("Вверх"), .step(-1))]
        accessibilityButtons = actions.map { title, event in
            let button = PodAccessibleButton { [weak self] in self?.store.input(event) }
            button.setAccessibilityLabel(title); button.setAccessibilityRole(.button); button.setAccessibilityParent(self)
            button.setAccessibilityElement(true)
            button.setAccessibilityEnabled(true)
            button.setAccessibilityFrame(window?.convertToScreen(convert(bounds, to: nil)) ?? .zero)
            return button
        }
        return accessibilityButtons
    }
}
final class PodAccessibleButton: NSAccessibilityElement {
    let action: @MainActor @Sendable () -> Void
    init(action: @escaping @MainActor @Sendable () -> Void) { self.action = action; super.init() }
    override func accessibilityPerformPress() -> Bool { let action = action; Task { @MainActor in action() }; return true }
}
