import SceneKit
import SpriteKit
import AppKit
import PodCore

enum ResourceLocator {
    static var directory: URL {
        if let resources = Bundle.main.resourceURL {
            let packaged = resources.appendingPathComponent("ClassicPod_ClassicPod.bundle/Resources")
            if FileManager.default.fileExists(atPath: packaged.appendingPathComponent("AssetConfig.json").path) { return packaged }
        }
        #if SWIFT_PACKAGE
        return Bundle.main.executableURL!.deletingLastPathComponent().appendingPathComponent("ClassicPod_ClassicPod.bundle/Resources")
        #else
        return Bundle.main.resourceURL!.appendingPathComponent("Resources")
        #endif
    }
}
@MainActor final class PodScene {
    let scene = SCNScene()
    let camera = SCNNode()
    let modelRoot = SCNNode()
    let display = VirtualDisplay()
    private var displayMaterials: [SCNMaterial] = []
    private(set) var wheel = SCNNode()
    private(set) var temporaryModel = false
    private(set) var assetWarning: String?
    init() {
        scene.background.contents = NSColor.clear
        modelRoot.name = "iPodAssembly"; scene.rootNode.addChildNode(modelRoot)
        camera.camera = SCNCamera(); camera.camera?.usesOrthographicProjection = false; camera.camera?.fieldOfView = 34; camera.camera?.orthographicScale = 6.5
        camera.position = SCNVector3(0, 0, 22); scene.rootNode.addChildNode(camera)
        if !loadModel() { proceduralModel() }
        scene.lightingEnvironment.contents = studioEnvironment()
        scene.lightingEnvironment.intensity = 1.1
        addLight(type: .ambient, intensity: 160, position: SCNVector3(0, 0, 10))
        addSoftbox(intensity: 900, position: SCNVector3(-5, 4, 12), size: SIMD2(8, 12))
        addSoftbox(intensity: 320, position: SCNVector3(7, -2, 7), size: SIMD2(4, 8))
        addLight(type: .omni, intensity: 430, position: SCNVector3(-2, 1, -12))
        addLight(type: .omni, intensity: 120, position: SCNVector3(8, -4, -5))
    }
    private struct Config: Decodable {
        let model: String?; let bodyNode: String; let screenNode: String; let wheelNode: String; let centerNode: String
    }
    private func loadModel() -> Bool {
        do {
            let config = try JSONDecoder().decode(Config.self, from: Data(contentsOf: ResourceLocator.directory.appendingPathComponent("AssetConfig.json")))
            guard let model = config.model else { return false }
            let root = ResourceLocator.directory.standardizedFileURL
            let url = root.appendingPathComponent(model).standardizedFileURL
            guard url.path.hasPrefix(root.path + "/") else { throw NSError(domain: "Asset", code: 1) }
            let loaded = try SCNScene(url: url)
            guard let body = loaded.rootNode.childNode(withName: config.bodyNode, recursively: true), body.geometry != nil else { throw NSError(domain: "Asset: missing Body geometry", code: 2) }
            let container = SCNNode()
            for node in loaded.rootNode.childNodes { container.addChildNode(node) }
            let screen = container.childNode(withName: config.screenNode, recursively: true) ?? makeScreen()
            if screen.parent == nil { container.addChildNode(screen) }
            screen.geometry?.firstMaterial = screenMaterial()
            wheel = container.childNode(withName: config.wheelNode, recursively: true) ?? makeWheel()
            if wheel.parent == nil { container.addChildNode(wheel) }
            wheel.name = "ClickWheel"
            if container.childNode(withName: config.centerNode, recursively: true) == nil { container.addChildNode(makeCenter()) }
            modelRoot.addChildNode(container); return true
        } catch { assetWarning = L10n.format("Внешняя модель не загружена: %@. Используется встроенная модель.", error.localizedDescription); return false }
    }
    private func proceduralModel() {
        let chrome = material(NSColor(calibratedWhite: 0.67, alpha: 1), metal: 1, rough: 0.13)
        chrome.name = "Polished Stainless Steel"
        let shell = SCNBox(width: 6.05, height: 10.05, length: 0.88, chamferRadius: 0.42)
        shell.chamferSegmentCount = 12
        shell.firstMaterial = chrome
        let back = SCNNode(geometry: shell); back.name = "Back"; modelRoot.addChildNode(back)
        let seam = SCNShape(path: NSBezierPath(roundedRect: NSRect(x: -3.01, y: -5.01, width: 6.02, height: 10.02), xRadius: 0.4, yRadius: 0.4), extrusionDepth: 0.045)
        seam.chamferRadius = 0.004
        seam.firstMaterial = material(NSColor(calibratedWhite: 0.2, alpha: 1), metal: 0.5, rough: 0.4)
        let seamNode = SCNNode(geometry: seam); seamNode.name = "CaseSeam"; seamNode.position.z = 0.12; modelRoot.addChildNode(seamNode)
        let body = SCNBox(width: 6, height: 10, length: 0.4, chamferRadius: 0.35)
        body.chamferSegmentCount = 12
        let aluminum = material(NSColor(calibratedWhite: 0.62, alpha: 1), metal: 0.92, rough: 0.4)
        aluminum.name = "Brushed Aluminum"
        aluminum.diffuse.contents = brushedTexture(base: 0.72, variation: 0.008)
        aluminum.roughness.contents = brushedTexture(base: 0.35, variation: 0.008)
        body.firstMaterial = aluminum
        let face = SCNNode(geometry: body); face.name = "Body"; face.position.z = 0.32; modelRoot.addChildNode(face)
        let bezel = SCNBox(width: 4.88, height: 3.73, length: 0.025, chamferRadius: 0.012)
        bezel.firstMaterial = material(.black, metal: 0.1, rough: 0.2)
        let frame = SCNNode(geometry: bezel); frame.name = "ScreenBezel"; frame.position = SCNVector3(0, 2, 0.535); modelRoot.addChildNode(frame)
        modelRoot.addChildNode(makeScreen()); wheel = makeWheel(); modelRoot.addChildNode(wheel)
        modelRoot.addChildNode(makeCenter())
        addPorts()
        addBackLabel("ClassicPod", y: 0.55, scale: 0.52)
        addBackLabel("CLASSIC EDITION", y: -0.05, scale: 0.13)
        addBackLabel("Designed for your music", y: -3.05, scale: 0.105)
        addBackLabel("MODEL CP–01   ·   DIGITAL AUDIO", y: -3.38, scale: 0.08)
    }
    private func makeScreen() -> SCNNode {
        let geometry = SCNPlane(width: 4.6, height: 3.45); geometry.firstMaterial = screenMaterial()
        let node = SCNNode(geometry: geometry); node.name = "Screen"; node.position = SCNVector3(0, 2, 0.56); return node
    }
    private func screenMaterial() -> SCNMaterial {
        let material = SCNMaterial(); material.lightingModel = .constant; material.diffuse.contents = display.image
        displayMaterials.append(material)
        material.isDoubleSided = false; return material
    }
    func updateDisplayTexture() { for material in displayMaterials { material.diffuse.contents = display.image } }
    private func makeWheel() -> SCNNode {
        let texture = SKScene(size: CGSize(width: 512, height: 512)); texture.backgroundColor = .clear
        let ring = SKShapeNode(circleOfRadius: 254); ring.fillColor = NSColor(calibratedWhite: 0.94, alpha: 1); ring.strokeColor = NSColor(calibratedWhite: 0.7, alpha: 1)
        ring.position = CGPoint(x: 256, y: 256); texture.addChild(ring)
        let ink = NSColor(calibratedWhite: 0.32, alpha: 1)
        let menu = SKLabelNode(fontNamed: "HelveticaNeue-Medium"); menu.text = "MENU"; menu.fontSize = 27
        menu.fontColor = ink; menu.position = CGPoint(x: 256, y: 426); texture.addChild(menu)
        func triangle(at position: CGPoint, direction: CGFloat) {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: -8 * direction, y: -11))
            path.addLine(to: CGPoint(x: 9 * direction, y: 0))
            path.addLine(to: CGPoint(x: -8 * direction, y: 11)); path.closeSubpath()
            let icon = SKShapeNode(path: path); icon.fillColor = ink; icon.strokeColor = .clear
            icon.position = position; texture.addChild(icon)
        }
        func bar(at position: CGPoint) {
            let icon = SKShapeNode(rectOf: CGSize(width: 4, height: 22), cornerRadius: 0.5)
            icon.fillColor = ink; icon.strokeColor = .clear; icon.position = position; texture.addChild(icon)
        }
        triangle(at: CGPoint(x: 244, y: 80), direction: 1)
        bar(at: CGPoint(x: 261, y: 80)); bar(at: CGPoint(x: 270, y: 80))
        for direction: CGFloat in [-1, 1] {
            let center = 256 + direction * 178
            triangle(at: CGPoint(x: center - direction * 7, y: 256), direction: direction)
            triangle(at: CGPoint(x: center + direction * 8, y: 256), direction: direction)
            bar(at: CGPoint(x: center + direction * 19, y: 256))
        }
        let wheelNode = SCNNode(); wheelNode.name = "ClickWheel"; wheelNode.position = SCNVector3(0, -2.15, 0.56)
        let disk = SCNCylinder(radius: 2.01, height: 0.045); disk.radialSegmentCount = 128
        disk.firstMaterial = material(NSColor(calibratedWhite: 0.28, alpha: 1), metal: 0.15, rough: 0.5)
        let diskNode = SCNNode(geometry: disk); diskNode.eulerAngles.x = .pi / 2; wheelNode.addChildNode(diskNode)
        let plane = SCNPlane(width: 4, height: 4); plane.cornerRadius = 2
        let material = material(.white, metal: 0, rough: 0.68); material.diffuse.contents = texture; plane.firstMaterial = material
        material.diffuse.contentsTransform = flippedTextureTransform()
        let node = SCNNode(geometry: plane); node.position.z = 0.024; wheelNode.addChildNode(node); return wheelNode
    }
    private func makeCenter() -> SCNNode {
        let shape = SCNCylinder(radius: 0.67, height: 0.065); shape.radialSegmentCount = 96
        shape.firstMaterial = material(NSColor(calibratedWhite: 0.65, alpha: 1), metal: 0.85, rough: 0.36)
        let trim = SCNTorus(ringRadius: 0.67, pipeRadius: 0.012)
        trim.ringSegmentCount = 96; trim.pipeSegmentCount = 12
        trim.firstMaterial = material(NSColor(calibratedWhite: 0.5, alpha: 1), metal: 1, rough: 0.17)
        let node = SCNNode(geometry: shape); node.eulerAngles.x = .pi / 2; node.position = SCNVector3(0, -2.15, 0.6); node.name = "CenterButton"
        let rim = SCNNode(geometry: trim); rim.position.y = -0.027; node.addChildNode(rim); return node
    }
    private func material(_ color: NSColor, metal: CGFloat, rough: CGFloat) -> SCNMaterial {
        let material = SCNMaterial(); material.lightingModel = .physicallyBased; material.diffuse.contents = color
        material.metalness.contents = metal; material.roughness.contents = rough; return material
    }
    private func flippedTextureTransform() -> SCNMatrix4 {
        var transform = SCNMatrix4MakeScale(1, -1, 1); transform.m42 = 1; return transform
    }
    private func addPorts() {
        let dark = material(NSColor(calibratedWhite: 0.04, alpha: 1), metal: 0.1, rough: 0.65)
        let steel = material(NSColor(calibratedWhite: 0.63, alpha: 1), metal: 1, rough: 0.22)
        let gold = material(NSColor(calibratedRed: 0.7, green: 0.51, blue: 0.22, alpha: 1), metal: 0.85, rough: 0.27)
        func box(_ name: String, width: CGFloat, height: CGFloat, depth: CGFloat, at position: SCNVector3, material: SCNMaterial) {
            let geometry = SCNBox(width: width, height: height, length: depth, chamferRadius: min(0.035, min(height, depth) / 3))
            geometry.firstMaterial = material
            let node = SCNNode(geometry: geometry); node.name = name; node.position = position; modelRoot.addChildNode(node)
        }
        let jackRim = SCNTube(innerRadius: 0.15, outerRadius: 0.22, height: 0.045); jackRim.radialSegmentCount = 64; jackRim.firstMaterial = steel
        let jack = SCNNode(geometry: jackRim); jack.name = "HeadphoneJack"; jack.position = SCNVector3(1.65, 5.035, -0.02); modelRoot.addChildNode(jack)
        let cavity = SCNCylinder(radius: 0.151, height: 0.006); cavity.firstMaterial = dark
        let hole = SCNNode(geometry: cavity); hole.name = "JackCavity"; hole.position = SCNVector3(1.65, 5.03, -0.02); modelRoot.addChildNode(hole)
        box("HoldRecess", width: 1.0, height: 0.035, depth: 0.26, at: SCNVector3(-1.6, 5.035, -0.015), material: dark)
        box("HoldIndicator", width: 0.28, height: 0.012, depth: 0.16, at: SCNVector3(-1.91, 5.058, -0.015), material: material(.systemOrange, metal: 0, rough: 0.7))
        box("HoldSlider", width: 0.54, height: 0.065, depth: 0.2, at: SCNVector3(-1.43, 5.06, -0.015), material: steel)
        for index in 0..<5 {
            box("HoldGrip", width: 0.018, height: 0.008, depth: 0.15, at: SCNVector3(-1.62 + Float(index) * 0.09, 5.097, -0.015), material: dark)
        }
        box("DockRim", width: 2.35, height: 0.05, depth: 0.39, at: SCNVector3(0, -5.035, -0.015), material: steel)
        box("DockSocket", width: 2.17, height: 0.066, depth: 0.28, at: SCNVector3(0, -5.055, -0.015), material: dark)
        box("DockTongue", width: 1.91, height: 0.01, depth: 0.10, at: SCNVector3(0, -5.09, -0.015), material: material(NSColor(calibratedWhite: 0.27, alpha: 1), metal: 0, rough: 0.7))
        for index in 0..<30 {
            box("DockPin\(index + 1)", width: 0.035, height: 0.006, depth: 0.12, at: SCNVector3(-0.87 + Float(index) * 0.06, -5.099, -0.015), material: gold)
        }
        for horizontal in [-2.15, 2.15] {
            let screw = SCNCylinder(radius: 0.055, height: 0.022); screw.firstMaterial = steel
            let node = SCNNode(geometry: screw); node.name = "DockScrew"; node.position = SCNVector3(horizontal, -5.04, -0.015); modelRoot.addChildNode(node)
            box("ScrewSlot", width: 0.065, height: 0.008, depth: 0.012, at: SCNVector3(horizontal, -5.055, -0.015), material: dark)
        }
    }
    private func addBackLabel(_ text: String, y: Float, scale: Float) {
        let geometry = SCNText(string: text, extrusionDepth: 0.15)
        geometry.font = NSFont.systemFont(ofSize: 100, weight: .regular); geometry.flatness = 0.08
        geometry.firstMaterial = material(NSColor(calibratedWhite: 0.18, alpha: 1), metal: 0.45, rough: 0.52)
        let node = SCNNode(geometry: geometry); node.name = "BackEngraving"
        let bounds = node.boundingBox
        let factor = scale / 100
        node.scale = SCNVector3(factor, factor, factor); node.eulerAngles.y = .pi
        node.position = SCNVector3(Float(bounds.min.x + bounds.max.x) * factor / 2, y, -0.447)
        modelRoot.addChildNode(node)
    }
    private func studioEnvironment() -> NSImage {
        NSImage(size: NSSize(width: 1024, height: 512), flipped: false) { rectangle in
            NSGradient(colors: [NSColor(calibratedWhite: 0.045, alpha: 1), NSColor(calibratedRed: 0.28, green: 0.31, blue: 0.36, alpha: 1), NSColor(calibratedWhite: 0.12, alpha: 1)])?.draw(in: rectangle, angle: 90)
            for (horizontal, width, brightness) in [(110.0, 170.0, 0.92), (690.0, 85.0, 0.74)] {
                let softbox = NSBezierPath(roundedRect: NSRect(x: horizontal, y: 70, width: width, height: 375), xRadius: 32, yRadius: 32)
                NSGradient(starting: NSColor(calibratedWhite: brightness, alpha: 1), ending: NSColor(calibratedWhite: brightness * 0.52, alpha: 1))?.draw(in: softbox, angle: 0)
            }
            return true
        }
    }
    private func brushedTexture(base: CGFloat, variation: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: 512, height: 512), flipped: false) { rectangle in
            var seed: UInt32 = 0xC1A551C
            for row in 0..<512 {
                seed = 1664525 &* seed &+ 1013904223
                let value = base + (CGFloat(seed & 1023) / 1023 - 0.5) * variation
                NSColor(calibratedWhite: value, alpha: 1).setFill()
                NSRect(x: 0, y: CGFloat(row), width: rectangle.width, height: 1).fill()
            }
            return true
        }
    }
    private func addLight(type: SCNLight.LightType, intensity: CGFloat, position: SCNVector3) {
        let node = SCNNode(); node.light = SCNLight(); node.light?.type = type; node.light?.intensity = intensity
        node.position = position; scene.rootNode.addChildNode(node)
    }
    private func addSoftbox(intensity: CGFloat, position: SCNVector3, size: SIMD2<Float>) {
        let node = SCNNode(); let light = SCNLight()
        light.type = .area; light.intensity = intensity; light.areaType = .rectangle
        light.areaExtents = SIMD3(size.x, size.y, 1); light.drawsArea = false
        node.light = light; node.position = position; node.look(at: SCNVector3Zero)
        scene.rootNode.addChildNode(node)
    }
}
