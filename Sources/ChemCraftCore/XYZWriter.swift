import Foundation

public enum XYZWriter {
    public static func string(frame: MoleculeFrame, comment: String? = nil) -> String {
        let rawComment: String
        if let comment { rawComment = comment }
        else if let energy = frame.energyHartree, energy.isFinite,
                !(frame.comment.hasPrefix("energy_hartree=") && XYZCommentEnergy.parse(frame.comment, frameIndex: 0, sourceLine: 1)?.hartree().map { abs($0 - energy) < max(1e-12, abs(energy) * 1e-14) } == true) {
            rawComment = "energy_hartree=" + String(format: "%.15g", locale: Locale(identifier: "en_US_POSIX"), energy) + " | " + frame.comment
        } else { rawComment = frame.comment }
        let singleLineComment = rawComment
            .components(separatedBy: .newlines)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)

        var lines = [String(frame.atoms.count), singleLineComment]
        lines.append(contentsOf: frame.atoms.map { atom in
            [
                atom.element,
                coordinate(atom.position.x),
                coordinate(atom.position.y),
                coordinate(atom.position.z)
            ].joined(separator: " ")
        })
        return lines.joined(separator: "\n") + "\n"
    }

    private static func coordinate(_ value: Float) -> String {
        String(format: "%.9g", locale: Locale(identifier: "en_US_POSIX"), Double(value))
    }
}
