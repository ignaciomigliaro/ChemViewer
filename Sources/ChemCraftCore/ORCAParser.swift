import Foundation

public enum ORCAParser {
    private static let energyPattern = try! NSRegularExpression(
        pattern: #"FINAL SINGLE POINT ENERGY\s+([-+]?\d+(?:\.\d+)?(?:[Ee][-+]?\d+)?)"#
    )
    private static let frequencyPattern = try! NSRegularExpression(
        pattern: #"^\s*(\d+):\s*([-+]?\d+(?:\.\d+)?)\s+cm\*\*-1"#
    )
    private static let spectrumPattern = try! NSRegularExpression(
        pattern: #"^\s*(\d+):\s*([-+]?\d+(?:\.\d+)?)\s+([-+]?\d+(?:\.\d+)?(?:[Ee][-+]?\d+)?)"#
    )

    public static func parse(text: String, title: String = "ORCA output") throws -> ParsedDocument {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n")
        let frameRecords = try parseCartesianBlocks(lines)
        var frames = frameRecords.map(\.frame)
        guard !frames.isEmpty else { throw ParseError.noGeometry }

        var energyCount = 0
        var energies: [EnergyRecord] = []
        let scfPattern = try NSRegularExpression(pattern: #"^\s*Total Energy\s*:\s*([-+]?\d+(?:\.\d+)?(?:[Ee][-+]?\d+)?)\s+(?:Eh|a\.u\.)"#)
        var scfHeader: Int?
        for (lineIndex, line) in lines.enumerated() {
            if line.contains("TOTAL SCF ENERGY") { scfHeader = lineIndex }
            let frame = frameRecords.lastIndex(where: { $0.lineIndex < lineIndex })
            if let start = scfHeader, lineIndex - start < 35, let match = firstMatch(scfPattern, line), let energy = Double(match[1]), energy.isFinite {
                energies.append(EnergyRecord(value: energy, unit: .hartree, kind: .scf, frameIndex: frame, sourceLine: lineIndex + 1, sourceText: line))
                if let frame, frames[frame].energyHartree == nil { frames[frame].energyHartree = energy }
                scfHeader = nil
            }
            guard let match = firstMatch(energyPattern, line), let energy = Double(match[1]), energy.isFinite else { continue }
            energyCount += 1
            energies.append(EnergyRecord(value: energy, unit: .hartree, kind: .singlePoint, frameIndex: frame, sourceLine: lineIndex + 1, sourceText: line))
            if let frame { frames[frame].energyHartree = energy }
        }

        let frequencyLine = lines.lastIndex { $0.trimmingCharacters(in: .whitespaces) == "VIBRATIONAL FREQUENCIES" }
        let modeFrameIndex = frequencyLine.flatMap { line in frameRecords.lastIndex { $0.lineIndex < line } }
        let frequencySection: [String] = frequencyLine.map { start in
            let end = frameRecords.first { $0.lineIndex > start }?.lineIndex ?? lines.count
            return Array(lines[start..<end])
        } ?? []
        var modes = parseFrequencies(frequencySection)
        let coordinateCount = modeFrameIndex.map { frames[$0].atoms.count * 3 } ?? 0
        let vectors = parseNormalModes(frequencySection, coordinateCount: coordinateCount)
        let intensities = parseIRSpectrum(frequencySection)

        for index in modes.indices {
            let modeNumber = modes[index].index
            if let values = vectors[modeNumber], values.count == coordinateCount {
                modes[index].displacements = stride(from: 0, to: coordinateCount, by: 3).map {
                    Vector3(values[$0], values[$0 + 1], values[$0 + 2])
                }
            }
            modes[index].infraredIntensity = intensities[modeNumber]
        }

        var warnings: [String] = []
        if !modes.isEmpty && vectors.isEmpty {
            warnings.append("Frequencies were found, but no normal-mode displacement matrix was parsed.")
        }
        let assignedEnergyCount = frames.lazy.filter { $0.energyHartree != nil }.count
        if energyCount > 0 && assignedEnergyCount < min(energyCount, frames.count) {
            warnings.append("Some ORCA energies could not be associated with a preceding Cartesian geometry.")
        }
        let neb = ORCANEBParser.parse(lines: lines)
        if neb == nil && lines.contains(where: { $0.contains("PATH SUMMARY") }) { warnings.append("NEB path summary is incomplete or unsupported; geometry optimization history remains available.") }
        return ParsedDocument(
            title: title,
            sourceFormat: "ORCA",
            frames: frames,
            vibrationalModes: modes,
            vibrationalFrameIndex: modes.isEmpty ? nil : modeFrameIndex,
            warnings: warnings,
            energyRecords: energies,
            thermochemistry: try ORCAThermochemistryParser.parse(lines: lines, geometryHeaders: frameRecords.map(\.lineIndex)),
            nebProfile: neb
        )
    }

    private struct FrameRecord {
        var lineIndex: Int
        var frame: MoleculeFrame
    }

    private static func parseCartesianBlocks(_ lines: [String]) throws -> [FrameRecord] {
        var frames: [FrameRecord] = []
        var lineIndex = 0
        while lineIndex < lines.count {
            guard lines[lineIndex].contains("CARTESIAN COORDINATES (ANGSTROEM)") else {
                lineIndex += 1
                continue
            }
            let headerLineIndex = lineIndex
            lineIndex += 1
            while lineIndex < lines.count {
                let value = lines[lineIndex].trimmingCharacters(in: .whitespaces)
                if value.isEmpty || value.allSatisfy({ $0 == "-" }) {
                    lineIndex += 1
                } else {
                    break
                }
            }

            var atoms: [Atom] = []
            while lineIndex < lines.count {
                let row = lines[lineIndex].trimmingCharacters(in: .whitespaces)
                if row.isEmpty { break }
                let fields = row.split(whereSeparator: \.isWhitespace)
                guard fields.count >= 4,
                      let x = Float(fields[1]),
                      let y = Float(fields[2]),
                      let z = Float(fields[3]) else { break }
                guard x.isFinite, y.isFinite, z.isFinite else { throw ParseError.malformed("non-finite coordinate at line \(lineIndex + 1)") }
                atoms.append(Atom(
                    id: atoms.count,
                    element: String(fields[0]),
                    position: Vector3(x, y, z)
                ))
                lineIndex += 1
            }
            if !atoms.isEmpty {
                frames.append(FrameRecord(
                    lineIndex: headerLineIndex,
                    frame: MoleculeFrame(id: frames.count, atoms: atoms, comment: "ORCA Cartesian geometry")
                ))
            }
        }
        return frames
    }

    private static func parseFrequencies(_ lines: [String]) -> [VibrationalMode] {
        guard let start = lines.lastIndex(where: { $0.contains("VIBRATIONAL FREQUENCIES") }) else { return [] }
        var modes: [VibrationalMode] = []
        for line in lines.dropFirst(start + 1) {
            if line.contains("NORMAL MODES") || line.contains("IR SPECTRUM") { break }
            guard let match = firstMatch(frequencyPattern, line),
                  let index = Int(match[1]),
                  let frequency = Double(match[2]) else { continue }
            modes.append(VibrationalMode(index: index, frequencyCM1: frequency))
        }
        return modes
    }

    private static func parseNormalModes(_ lines: [String], coordinateCount: Int) -> [Int: [Float]] {
        guard coordinateCount > 0,
              let start = lines.lastIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "NORMAL MODES" }) else {
            return [:]
        }
        let end = lines[(start + 1)...].firstIndex(where: {
            let value = $0.trimmingCharacters(in: .whitespaces)
            return value == "IR SPECTRUM" || value == "RAMAN SPECTRUM"
        }) ?? lines.endIndex

        var valuesByMode: [Int: [Int: Float]] = [:]
        var headers: [Int] = []
        var invalid: Set<Int> = []
        for rawLine in lines[(start + 1)..<end] {
            let tokens = rawLine.split(whereSeparator: \.isWhitespace).map(String.init)
            if !tokens.isEmpty, tokens.allSatisfy({ Int($0) != nil }) {
                headers = tokens.compactMap(Int.init)
                if Set(headers).count != headers.count { invalid.formUnion(headers) }
                continue
            }
            guard !headers.isEmpty, let first = tokens.first, let coordinate = Int(first), coordinate >= 0, coordinate < coordinateCount else { continue }
            guard tokens.count == headers.count + 1 else { invalid.formUnion(headers); continue }
            for (offset, mode) in headers.enumerated() {
                let token = tokens[offset + 1].replacingOccurrences(of: "D", with: "E").replacingOccurrences(of: "d", with: "e")
                guard let value = Float(token), value.isFinite, valuesByMode[mode]?[coordinate] == nil else { invalid.insert(mode); continue }
                valuesByMode[mode, default: [:]][coordinate] = value
            }
        }
        var complete: [Int: [Float]] = [:]
        for (mode, rows) in valuesByMode where !invalid.contains(mode) && rows.count == coordinateCount {
            complete[mode] = (0..<coordinateCount).map { rows[$0]! }
        }
        return complete
    }

    private static func parseIRSpectrum(_ lines: [String]) -> [Int: Double] {
        guard let start = lines.lastIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "IR SPECTRUM" }) else {
            return [:]
        }
        var result: [Int: Double] = [:]
        for line in lines.dropFirst(start + 1) {
            if line.contains("THERMOCHEMISTRY") || line.contains("RAMAN SPECTRUM") { break }
            guard let match = firstMatch(spectrumPattern, line),
                  let mode = Int(match[1]),
                  let intensity = Double(match[3]) else { continue }
            result[mode] = intensity
        }
        return result
    }

    private static func matches(_ expression: NSRegularExpression, in text: String) -> [[String]] {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.matches(in: text, range: range).map { match in
            (0..<match.numberOfRanges).map { index in
                guard let range = Range(match.range(at: index), in: text) else { return "" }
                return String(text[range])
            }
        }
    }

    private static func firstMatch(_ expression: NSRegularExpression, _ text: String) -> [String]? {
        matches(expression, in: text).first
    }
}
