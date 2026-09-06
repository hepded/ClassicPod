import AppKit

func rounded(_ rectangle: NSRect, radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rectangle, xRadius: radius, yRadius: radius)
}

func drawIcon(size: Int) throws -> Data {
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { fatalError("Icon bitmap") }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    let scale = NSAffineTransform(); scale.scale(by: CGFloat(size) / 1024); scale.concat()
    let tile = rounded(NSRect(x: 80, y: 80, width: 864, height: 864), radius: 192)
    NSGraphicsContext.saveGraphicsState()
    let tileShadow = NSShadow(); tileShadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    tileShadow.shadowBlurRadius = 20; tileShadow.shadowOffset = NSSize(width: 0, height: -12); tileShadow.set()
    NSColor(calibratedRed: 0.07, green: 0.12, blue: 0.2, alpha: 1).setFill(); tile.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors: [NSColor(calibratedRed: 0.04, green: 0.08, blue: 0.15, alpha: 1), NSColor(calibratedRed: 0.14, green: 0.27, blue: 0.40, alpha: 1)])!.draw(in: tile, angle: 65)
    NSColor.white.withAlphaComponent(0.16).setStroke(); tile.lineWidth = 2; tile.stroke()

    NSGraphicsContext.saveGraphicsState()
    let rotation = NSAffineTransform(); rotation.translateX(by: 512, yBy: 512); rotation.rotate(byDegrees: -9); rotation.translateX(by: -512, yBy: -512); rotation.concat()
    let shell = rounded(NSRect(x: 294, y: 180, width: 450, height: 684), radius: 57)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.55)
    shadow.shadowBlurRadius = 36; shadow.shadowOffset = NSSize(width: 12, height: -25); shadow.set()
    NSColor(calibratedWhite: 0.3, alpha: 1).setFill(); shell.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors: [.white, NSColor(calibratedWhite: 0.35, alpha: 1), NSColor(calibratedWhite: 0.85, alpha: 1)])!.draw(in: shell, angle: 0)
    let face = rounded(NSRect(x: 286, y: 190, width: 440, height: 682), radius: 52)
    NSGradient(colors: [NSColor(calibratedWhite: 0.63, alpha: 1), NSColor(calibratedWhite: 0.96, alpha: 1), NSColor(calibratedWhite: 0.78, alpha: 1)])!.draw(in: face, angle: 20)
    NSColor.white.withAlphaComponent(0.7).setStroke(); face.lineWidth = 3; face.stroke()
    let bezel = rounded(NSRect(x: 323, y: 559, width: 366, height: 259), radius: 17)
    NSColor(calibratedWhite: 0.11, alpha: 1).setFill(); bezel.fill()
    let screen = rounded(NSRect(x: 336, y: 572, width: 340, height: 233), radius: 7)
    NSGradient(colors: [NSColor(calibratedRed: 0.05, green: 0.30, blue: 0.66, alpha: 1), NSColor(calibratedRed: 0.17, green: 0.72, blue: 0.91, alpha: 1)])!.draw(in: screen, angle: 75)
    NSGraphicsContext.saveGraphicsState(); screen.addClip()
    let shine = NSBezierPath(); shine.move(to: NSPoint(x: 330, y: 810)); shine.line(to: NSPoint(x: 680, y: 810)); shine.line(to: NSPoint(x: 330, y: 655)); shine.close()
    NSColor.white.withAlphaComponent(0.12).setFill(); shine.fill(); NSGraphicsContext.restoreGraphicsState()
    NSColor.white.setFill()
    let note = NSBezierPath(); note.move(to: NSPoint(x: 496, y: 632)); note.line(to: NSPoint(x: 496, y: 744)); note.line(to: NSPoint(x: 572, y: 761)); note.line(to: NSPoint(x: 572, y: 657)); note.line(to: NSPoint(x: 555, y: 657)); note.line(to: NSPoint(x: 555, y: 726)); note.line(to: NSPoint(x: 513, y: 717)); note.line(to: NSPoint(x: 513, y: 632)); note.close(); note.fill()
    NSBezierPath(ovalIn: NSRect(x: 458, y: 614, width: 55, height: 35)).fill()
    NSBezierPath(ovalIn: NSRect(x: 517, y: 638, width: 55, height: 35)).fill()

    let wheel = NSBezierPath(ovalIn: NSRect(x: 364, y: 246, width: 284, height: 284))
    NSGradient(starting: NSColor(calibratedWhite: 0.89, alpha: 1), ending: .white)!.draw(in: wheel, angle: 90)
    NSColor(calibratedWhite: 0.57, alpha: 1).setStroke(); wheel.lineWidth = 2; wheel.stroke()
    let center = NSBezierPath(ovalIn: NSRect(x: 453, y: 335, width: 106, height: 106))
    NSGradient(starting: NSColor(calibratedWhite: 0.67, alpha: 1), ending: NSColor(calibratedWhite: 0.87, alpha: 1))!.draw(in: center, angle: 90)
    NSColor(calibratedWhite: 0.55, alpha: 1).setStroke(); center.lineWidth = 2; center.stroke()
    if size >= 64 {
        NSColor(calibratedWhite: 0.49, alpha: 1).setFill()
        rounded(NSRect(x: 491, y: 485, width: 30, height: 5), radius: 2).fill()
        for horizontal in [397.0, 611.0] { NSBezierPath(ovalIn: NSRect(x: horizontal - 4, y: 384, width: 8, height: 8)).fill() }
        let play = NSBezierPath(); play.move(to: NSPoint(x: 501, y: 284)); play.line(to: NSPoint(x: 513, y: 292)); play.line(to: NSPoint(x: 501, y: 300)); play.close(); play.fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.restoreGraphicsState()
    guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("PNG encoding") }
    return png
}

guard CommandLine.arguments.count == 2 else { fatalError("Usage: swift scripts/generate-icon.swift path/to/ClassicPod.iconset") }
let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try drawIcon(size: points * scale).write(to: directory.appendingPathComponent(name))
    }
}
print("Generated 10 icon representations")
