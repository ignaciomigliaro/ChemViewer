import Foundation

/// SIMD3 is part of the Swift standard library; Apple's simd module is not.
/// Keep the Double precision used by fragment geometry on every platform.
public enum VectorMath {
    public static func dot(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double {
        a.x * b.x + a.y * b.y + a.z * b.z
    }
    public static func cross(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
    }
    public static func length(_ a: SIMD3<Double>) -> Double { sqrt(dot(a, a)) }
    public static func distance(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double { length(a - b) }
    public static func normalize(_ a: SIMD3<Double>) -> SIMD3<Double> { a / length(a) }
}
