import Foundation

public struct ClickWheel: Sendable {
    public var stepAngle = Double.pi / 15
    public var innerRadius = 0.34
    public var outerRadius = 1.12
    public private(set) var remainder = 0.0
    public private(set) var cancelledClick = false
    private var lastAngle: Double?
    private var startPoint: SIMD2<Double>?
    private var ringCaptured = false
    public init() {}
    public mutating func begin(x: Double, y: Double, screenX: Double, screenY: Double) {
        remainder = 0; cancelledClick = false
        startPoint = SIMD2(screenX, screenY)
        ringCaptured = isRing(x, y)
        lastAngle = ringCaptured ? atan2(y, x) : nil
    }
    public mutating func move(x: Double, y: Double, screenX: Double, screenY: Double) -> Int {
        if let startPoint, hypot(screenX - startPoint.x, screenY - startPoint.y) > 4 { cancelledClick = true }
        guard ringCaptured else { return 0 }
        guard isRing(x, y) else { lastAngle = nil; return 0 }
        let angle = atan2(y, x)
        defer { lastAngle = angle }
        guard let lastAngle else { return 0 }
        remainder -= Self.normalized(angle - lastAngle)
        let steps = Int((remainder / stepAngle).rounded(.towardZero))
        remainder -= Double(steps) * stepAngle
        if steps != 0 { cancelledClick = true }
        return steps
    }
    public mutating func end() { lastAngle = nil; startPoint = nil; remainder = 0 }
    public func isRing(_ x: Double, _ y: Double) -> Bool { (innerRadius...outerRadius).contains(hypot(x, y)) }
    public static func normalized(_ angle: Double) -> Double { atan2(sin(angle), cos(angle)) }
    public static func button(x: Double, y: Double) -> InputEvent {
        if hypot(x, y) < 0.34 { return .select }
        if abs(y) > abs(x) { return y > 0 ? .menu : .playPause }
        return x > 0 ? .next : .previous
    }
}
