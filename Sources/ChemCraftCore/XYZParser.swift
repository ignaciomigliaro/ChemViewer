import Foundation

public enum XYZParser {
    public static func parse(text: String, title: String = "Untitled.xyz") throws -> ParsedDocument {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n")
        var cursor = 0
        var frames: [MoleculeFrame] = []
        var energies: [EnergyRecord] = []

        while cursor < lines.count {
            while cursor < lines.count && lines[cursor].trimmingCharacters(in: .whitespaces).isEmpty {
                cursor += 1
            }
            guard cursor < lines.count else { break }
            guard let atomCount = Int(lines[cursor].trimmingCharacters(in: .whitespaces)), atomCount >= 0 else {
                throw ParseError.malformed("expected an atom count at line \(cursor + 1)")
            }
            cursor += 1
            guard cursor < lines.count else {
                throw ParseError.malformed("missing XYZ comment line")
            }
            let commentLine = cursor + 1
            let comment = lines[cursor]
            cursor += 1
            var atoms: [Atom] = []
            atoms.reserveCapacity(atomCount)

            for atomIndex in 0..<atomCount {
                guard cursor < lines.count else {
                    throw ParseError.malformed("frame \(frames.count + 1) ended after \(atoms.count) of \(atomCount) atoms")
                }
                let fields = lines[cursor].split(whereSeparator: \.isWhitespace)
                cursor += 1
                guard fields.count >= 4,
                      let x = Float(fields[1]),
                      let y = Float(fields[2]),
                      let z = Float(fields[3]), x.isFinite, y.isFinite, z.isFinite else {
                    throw ParseError.malformed("invalid atom row at line \(cursor)")
                }
                atoms.append(Atom(
                    id: atomIndex,
                    element: String(fields[0]),
                    position: Vector3(x, y, z)
                ))
            }
            let energy = XYZCommentEnergy.parse(comment, frameIndex: frames.count, sourceLine: commentLine)
            if let energy { energies.append(energy) }
            frames.append(MoleculeFrame(id: frames.count, atoms: atoms, comment: comment, energyHartree: energy?.hartree()))
        }

        guard !frames.isEmpty else { throw ParseError.noGeometry }
        return ParsedDocument(title: title, sourceFormat: "XYZ", frames: frames, energyRecords: energies)
    }
}
