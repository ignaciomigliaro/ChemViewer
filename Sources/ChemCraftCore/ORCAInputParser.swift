import Foundation

/// Independent Cartesian input reader; source syntax: ORCA 6.1 coordinate manual.
/// No ORCA execution or expression evaluation takes place here.
public enum ORCAInputParser {
    public static func tokens(_ line: String) -> [String] {
        var result: [String] = [], token = "", quote: Character?
        for character in line {
            if let delimiter = quote {
                if character == delimiter { quote = nil } else { token.append(character) }
            } else if character == "#" { break }
            else if character == "\"" || character == "'" { quote = character }
            else if character.isWhitespace {
                if !token.isEmpty { result.append(token); token = "" }
            } else { token.append(character) }
        }
        if !token.isEmpty { result.append(token) }; return result
    }
    public static func externalXYZReferences(in text: String) -> [String] {
        text.components(separatedBy: .newlines).compactMap { line in
            let values = tokens(line)
            return values.count >= 5 && values[0] == "*" && values[1].lowercased() == "xyzfile" ? values[4] : nil
        }
    }
    public static func parse(text: String, title: String, resolveXYZ: ((String) throws -> String)? = nil) throws -> ParsedDocument {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n")
        var frames: [MoleculeFrame] = [], warnings: [String] = []
        var charge: Int?, multiplicity: Int?
        var scale: Float = 1
        var cursor = 0
        var coordinateOptions = false
        func number(_ value: String) -> Float? { Float(value.replacingOccurrences(of: "D", with: "E").replacingOccurrences(of: "d", with: "e")) }
        func atom(_ values: [String], line: Int) throws -> Atom {
            guard values.count == 4, let symbol = BuildingProject.validatedElement(values[0]), let x = number(values[1]), let y = number(values[2]), let z = number(values[3]), x.isFinite, y.isFinite, z.isFinite else {
                throw ParseError.malformed("Unsupported ORCA Cartesian atom row at line \(line). Expressions, ghost/fragment annotations and point charges require Source view.")
            }
            return Atom(id: 0, element: symbol, position: Vector3(x * scale, y * scale, z * scale))
        }
        while cursor < lines.count {
            let values = tokens(lines[cursor]); cursor += 1
            guard let first = values.first else { continue }
            if first.hasPrefix("!") {
                for keyword in values.flatMap({ $0.lowercased().split(separator: "!").map(String.init) }) {
                    if keyword == "bohrs" { scale = 0.529177210903 }
                    if keyword == "angs" { scale = 1 }
                }
                continue
            }
            if coordinateOptions && first.lowercased() == "units", values.count >= 2 {
                switch values[1].lowercased() {
                case "bohrs": scale = 0.529177210903
                case "angs": scale = 1
                default: throw ParseError.malformed("Unsupported ORCA coordinate unit: \(values[1])")
                }
                continue
            }
            if first.lowercased() == "end" { coordinateOptions = false }
            if first.lowercased() == "%coords" {
                coordinateOptions = true
                warnings.append("%coords blocks are shown as source; this reader supports * xyz and * xyzfile Cartesian inputs.")
                continue
            }
            guard first == "*", values.count >= 2 else { continue }
            let kind = values[1].lowercased()
            guard values.count >= 4, let q = Int(values[2]), let m = Int(values[3]), m > 0 else { throw ParseError.malformed("Invalid ORCA charge/multiplicity at line \(cursor)") }
            if charge == nil { charge = q; multiplicity = m }
            if kind == "xyzfile" {
                guard scale == 1 else { throw ParseError.malformed("Bohr xyzfile input is not yet supported; convert the companion to Angstrom or use inline xyz coordinates.") }
                guard values.count >= 5, let resolveXYZ else { throw ParseError.malformed("ORCA xyzfile needs an explicit filename and accessible XYZ companion.") }
                let companion = try XYZParser.parse(text: resolveXYZ(values[4]), title: values[4])
                for frame in companion.frames {
                    // XYZ companion units are preserved as Angstrom; no input-unit scaling.
                    frames.append(MoleculeFrame(id: frames.count, atoms: frame.atoms, comment: "Input XYZ: \(values[4]); charge \(q), multiplicity \(m)"))
                }
            } else if kind == "xyz" {
                var atoms: [Atom] = [], closed = false
                while cursor < lines.count {
                    let row = tokens(lines[cursor]); cursor += 1
                    if row == ["*"] { closed = true; break }
                    if row.isEmpty { continue }
                    let parsed = try atom(row, line: cursor); atoms.append(Atom(id: atoms.count, element: parsed.element, position: parsed.position))
                    guard atoms.count <= 10_000 else { throw ParseError.malformed("Input exceeds 10,000 atoms") }
                }
                guard closed, !atoms.isEmpty else { throw ParseError.malformed("Missing ORCA coordinate terminator or empty xyz block") }
                frames.append(MoleculeFrame(id: frames.count, atoms: atoms, comment: "Input geometry; charge \(q), multiplicity \(m); source \(scale == 1 ? "Angstrom" : "Bohr")"))
            } else {
                warnings.append("ORCA \(kind) coordinates are shown as source; no Cartesian structure was inferred.")
                while cursor < lines.count { let row = tokens(lines[cursor]); cursor += 1; if row == ["*"] { break } }
            }
        }
        if frames.isEmpty { warnings.append("No supported Cartesian geometry: showing the original input/template in Source view.") }
        if frames.count > 1 { warnings.append("Multiple input geometries; the tab charge/multiplicity describes the first block. No calculation energies are inferred.") }
        return ParsedDocument(title: title, sourceFormat: "ORCA input", frames: frames, warnings: warnings, charge: charge, multiplicity: multiplicity)
    }
}
