import Foundation

public struct SpectralLine: Equatable, Sendable {
    public var position: Double
    public var intensity: Double

    public init(position: Double, intensity: Double) {
        self.position = position
        self.intensity = intensity
    }
}

public struct SpectralPoint: Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public enum SpectralLineShape: String, CaseIterable, Identifiable, Sendable {
    case gaussian = "Gaussian"
    case lorentzian = "Lorentzian"

    public var id: String { rawValue }
}

public enum SpectrumBroadening {
    public static func sample(
        lines: [SpectralLine],
        from lower: Double,
        to upper: Double,
        pointCount: Int,
        halfWidthAtHalfMaximum hwhm: Double,
        shape: SpectralLineShape
    ) -> [SpectralPoint] {
        guard pointCount >= 2, upper > lower, hwhm > 0 else { return [] }
        let step = (upper - lower) / Double(pointCount - 1)
        return (0..<pointCount).map { index in
            let x = lower + Double(index) * step
            let y = lines.reduce(0.0) { partial, line in
                let ratio = (x - line.position) / hwhm
                switch shape {
                case .gaussian:
                    return partial + line.intensity * exp(-log(2) * ratio * ratio)
                case .lorentzian:
                    return partial + line.intensity / (1 + ratio * ratio)
                }
            }
            return SpectralPoint(x: x, y: y)
        }
    }
}
