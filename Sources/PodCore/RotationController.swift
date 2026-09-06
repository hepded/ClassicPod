import Foundation
import simd

public enum PodHitSurface: Sendable { case none, body, wheel, center }
public enum PodGesture: Sendable, Equatable {
    case none, rotate, wheel, moveWindow
    public static func choose(surface: PodHitSurface, optionDown: Bool) -> Self {
        if surface == .none { return .none }
        if optionDown { return .moveWindow }
        switch surface {
        case .wheel, .center: return .wheel
        case .body: return .rotate
        case .none: return .none
        }
    }
}
public struct RotationController: Sendable {
    public private(set) var orientation = simd_quatd(angle: 0, axis: SIMD3(0, 1, 0))
    private var previous: SIMD3<Double>?
    private var previousTime = 0.0
    private var angularVelocity = SIMD3<Double>.zero
    public private(set) var isCoasting = false
    public init() {}
    public var isFront: Bool { abs(orientation.real) > 1 - 0.000001 }
    public mutating func begin(point: SIMD2<Double>, size: SIMD2<Double>, time: Double = ProcessInfo.processInfo.systemUptime) {
        stopInertia(); previous = Self.project(point, size: size); previousTime = time
    }
    public mutating func drag(point: SIMD2<Double>, size: SIMD2<Double>, time: Double = ProcessInfo.processInfo.systemUptime) {
        let current = Self.project(point, size: size)
        guard let previous else { self.previous = current; return }
        let cosine = min(1, max(-1, simd_dot(previous, current)))
        let delta: simd_quatd
        if cosine < -0.999999 {
            let helper = abs(previous.z) < 0.9 ? SIMD3<Double>(0, 0, 1) : SIMD3<Double>(0, 1, 0)
            delta = simd_quatd(angle: .pi, axis: simd_normalize(simd_cross(previous, helper)))
        } else { delta = simd_normalize(simd_quatd(vector: SIMD4(simd_cross(previous, current), 1 + cosine))) }
        orientation = simd_normalize(delta * orientation)
        let elapsed = time - previousTime
        let angle = 2 * acos(min(1, max(-1, delta.real)))
        if elapsed >= 0.001 && elapsed <= 0.12 && angle > 0.00001 {
            let velocity = simd_normalize(delta.imag) * min(3, angle / elapsed)
            let blend = simd_length_squared(angularVelocity) < 0.000001 ? 1 : 1 - exp(-30 * elapsed)
            angularVelocity += (velocity - angularVelocity) * blend
        } else { angularVelocity = .zero }
        previousTime = time
        self.previous = current
    }
    public mutating func end(time: Double = ProcessInfo.processInfo.systemUptime, inertia: Bool = false) {
        let age = time - previousTime
        isCoasting = previous != nil && inertia && age >= 0 && age <= 0.1 && simd_length(angularVelocity) > 0.08
        previous = nil
        if isCoasting { angularVelocity *= exp(-6.5 * age) } else { stopInertia() }
    }
    public mutating func stopInertia() { angularVelocity = .zero; isCoasting = false }
    @discardableResult public mutating func advance(by elapsed: Double) -> Bool {
        guard isCoasting else { return false }
        guard elapsed.isFinite, elapsed > 0, elapsed <= 0.25 else { stopInertia(); return false }
        let speed = simd_length(angularVelocity)
        let attenuation = exp(-6.5 * elapsed)
        let angle = speed * (1 - attenuation) / 6.5
        orientation = simd_normalize(simd_quatd(angle: angle, axis: angularVelocity / speed) * orientation)
        angularVelocity *= attenuation
        if simd_length(angularVelocity) < 0.03 { stopInertia() }
        return true
    }
    public mutating func reset() { orientation = simd_quatd(angle: 0, axis: SIMD3(0, 1, 0)); previous = nil; stopInertia() }
    public static func project(_ point: SIMD2<Double>, size: SIMD2<Double>) -> SIMD3<Double> {
        let radius = max(1, min(size.x, size.y) * 0.48)
        let planar = (point - size / 2) / radius
        let lengthSquared = simd_length_squared(planar)
        if lengthSquared <= 1 { return SIMD3(planar.x, planar.y, sqrt(max(0, 1 - lengthSquared))) }
        return simd_normalize(SIMD3(planar.x, planar.y, 0))
    }
}
