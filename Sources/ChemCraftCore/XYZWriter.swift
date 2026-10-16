import Foundation

public enum XYZWriter {
    public static func string(frame: MoleculeFrame, comment: String? = nil) -> String {
        let rawComment = comment ?? frame.comment
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
