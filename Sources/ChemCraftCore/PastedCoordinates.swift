import Foundation

/// Clipboard Cartesian coordinates use XYZ's angstrom convention.
public enum PastedCoordinates {
    public static func parse(_ text: String) throws -> ParsedDocument {
        guard text.utf8.count <= 10_000_000 else { throw ParseError.malformed("Pasted coordinates exceed 10 MB.") }
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let rows = normalized.components(separatedBy: "\n")
        guard let first = rows.first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else { throw ParseError.noGeometry }
        let xyz: String
        if Int(first.trimmingCharacters(in: .whitespaces)) != nil {
            xyz = normalized
        } else {
            let atoms = rows.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            guard atoms.count <= 10_000 else { throw ParseError.malformed("At most 10,000 atoms per frame are supported.") }
            guard atoms.allSatisfy({ $0.split(whereSeparator: \.isWhitespace).count == 4 }) else {
                throw ParseError.malformed("Use Element X Y Z rows, or a complete XYZ including atom count and comment line.")
            }
            xyz = "\(atoms.count)\nPasted Cartesian coordinates (angstrom)\n" + atoms.joined(separator: "\n") + "\n"
        }
        var document = try XYZParser.parse(text: xyz, title: "Pasted coordinates.xyz")
        guard document.frames.count <= 2000, document.frames.allSatisfy({ !$0.atoms.isEmpty && $0.atoms.count <= 10_000 }), document.frames.reduce(0, { $0 + $1.atoms.count }) <= 500_000 else {
            throw ParseError.malformed("Use nonempty frames, at most 10,000 atoms per frame and 500,000 atoms total.")
        }
        for frame in document.frames.indices {
            for atom in document.frames[frame].atoms.indices {
                guard let symbol = BuildingProject.validatedElement(document.frames[frame].atoms[atom].element) else {
                    throw ParseError.malformed("Unknown element in frame \(frame + 1), atom \(atom + 1).")
                }
                document.frames[frame].atoms[atom].element = symbol
            }
        }
        return document
    }
}
