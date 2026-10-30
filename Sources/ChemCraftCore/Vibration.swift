import Foundation

/// A display clock, independent of the signed physical frequency. Times are monotonic seconds.
public struct VibrationPlayback: Equatable, Sendable {
    public private(set) var isPlaying: Bool
    public private(set) var speed: Double
    private var angle: Double = 0
    private var anchor: Double

    public init(time: Double, speed: Double = 0.48, isPlaying: Bool = true) {
        self.anchor = time; self.speed = speed; self.isPlaying = isPlaying
    }
    private func angle(at time: Double) -> Double {
        angle + (isPlaying ? (time - anchor) * speed * 2 * .pi : 0)
    }
    public func factor(at time: Double) -> Float { Float(sin(angle(at: time))) }
    public mutating func setPlaying(_ playing: Bool, at time: Double) {
        angle = angle(at: time); anchor = time; isPlaying = playing
    }
    public mutating func setSpeed(_ speed: Double, at time: Double) {
        angle = angle(at: time); anchor = time; self.speed = speed
    }
    public mutating func freezeAtMaximum(negative: Bool, at time: Double) {
        angle = negative ? -.pi / 2 : .pi / 2; anchor = time; isPlaying = false
    }
    public mutating func reset(at time: Double) { angle = 0; anchor = time }
}

public enum NormalModeGeometry {
    /// q = q_source + amplitude * phase * printed displacement. No normalization or mass weighting.
    /// amplitude is a display multiplier, phase is a signed fraction in [-1, 1].
    public static func displaced(_ frame: MoleculeFrame, mode: VibrationalMode,
                                 amplitude: Float, phase: Float) throws -> MoleculeFrame {
        guard !frame.atoms.isEmpty, mode.displacements.count == frame.atoms.count,
              amplitude.isFinite, amplitude >= 0, phase.isFinite, abs(phase) <= 1 else {
            throw ParseError.malformed("The selected mode needs one displacement per atom and a finite amplitude/phase.")
        }
        var result = frame
        for index in frame.atoms.indices {
            let source = frame.atoms[index].position, displacement = mode.displacements[index]
            let position = source + displacement * (amplitude * phase)
            guard [source.x, source.y, source.z, displacement.x, displacement.y, displacement.z,
                   position.x, position.y, position.z].allSatisfy(\.isFinite) else {
                throw ParseError.malformed("The mode or coordinates contain nonfinite values.")
            }
            result.atoms[index].position = position
        }
        // A displaced seed has no calculated energy. Do not copy an energy-bearing source comment.
        result.energyHartree = nil
        result.comment = "Displaced seed; mode \(mode.index), frequency_cm-1=\(mode.frequencyCM1), display_amplitude=\(amplitude), signed_phase=\(phase); not optimized"
        return result
    }
}
