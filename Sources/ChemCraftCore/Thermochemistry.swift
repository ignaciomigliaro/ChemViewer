import Foundation

public struct ThermochemicalValue: Equatable, Sendable {
    public let hartree: Double
    public let sourceLine: Int
    public let sourceText: String
}

public struct ThermochemistryRecord: Identifiable, Equatable, Sendable {
    public var id: Int { sourceLine }
    public let sourceLine: Int
    public let frameIndex: Int?
    public var temperatureKelvin: Double?
    public var pressure: String?
    public var electronic: ThermochemicalValue?
    public var zeroPoint: ThermochemicalValue?
    public var enthalpy: ThermochemicalValue?
    public var gibbs: ThermochemicalValue?
    public var printedGibbsCorrection: ThermochemicalValue?
    // ORCA's "Thermal Enthalpy correction" alone is kBT, not H - E.
    public var enthalpyCorrection: Double? {
        guard let h = enthalpy?.hartree, let e = electronic?.hartree else { return nil }
        return h - e
    }
    public var gibbsCorrection: Double? {
        if let printed = printedGibbsCorrection?.hartree { return printed }
        guard let g = gibbs?.hartree, let e = electronic?.hartree else { return nil }
        return g - e
    }
    public func summedEnthalpy(electronicEnergy: Double) -> Double? { enthalpyCorrection.map { electronicEnergy + $0 } }
    public func summedGibbs(electronicEnergy: Double) -> Double? { gibbsCorrection.map { electronicEnergy + $0 } }
}

public enum ORCAThermochemistryParser {
    public static func parse(lines: [String], geometryHeaders: [Int]) throws -> [ThermochemistryRecord] {
        let number = #"([-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[EeDd][-+]?\d+)?)"#
        let energy = try NSRegularExpression(pattern: #"(?i)^\s*(Electronic energy|Zero point energy|Total enthalpy|Final Gibbs free (?:enthalpy|energy)|G-E\(el\))\s*(?:\.{3})?\s*"# + number + #"\s+Eh\b"#)
        let temperature = try NSRegularExpression(pattern: #"(?i)(?:AT|Temperature\s*\.{3})\s*"# + number + #"\s*K\b"#)
        var records: [ThermochemistryRecord] = []
        var current: ThermochemistryRecord?
        func finish() {
            if let current, current.electronic != nil || current.enthalpy != nil || current.gibbs != nil { records.append(current) }
        }
        for (index, raw) in lines.enumerated() {
            let text = raw.trimmingCharacters(in: .whitespaces)
            if text.uppercased().hasPrefix("THERMOCHEMISTRY AT") {
                finish()
                current = ThermochemistryRecord(sourceLine: index + 1, frameIndex: geometryHeaders.lastIndex(where: { $0 < index }))
            } else if text.contains("CARTESIAN COORDINATES (ANGSTROEM)") {
                finish(); current = nil
            }
            guard current != nil else { continue }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            if let match = temperature.firstMatch(in: text, range: range), let r = Range(match.range(at: 1), in: text), let t = Double(text[r]), t.isFinite, t >= 0 { current?.temperatureKelvin = t }
            if text.hasPrefix("Pressure"), let dots = text.range(of: "...") { current?.pressure = String(text[dots.upperBound...]).trimmingCharacters(in: .whitespaces) }
            guard let match = energy.firstMatch(in: text, range: range), let nameRange = Range(match.range(at: 1), in: text), let valueRange = Range(match.range(at: 2), in: text),
                  let value = Double(text[valueRange].replacingOccurrences(of: "D", with: "E").replacingOccurrences(of: "d", with: "e")), value.isFinite else { continue }
            let item = ThermochemicalValue(hartree: value, sourceLine: index + 1, sourceText: raw)
            switch text[nameRange].lowercased() {
            case "electronic energy": current?.electronic = item
            case "zero point energy": current?.zeroPoint = item
            case "total enthalpy": current?.enthalpy = item
            case "g-e(el)": current?.printedGibbsCorrection = item
            default: current?.gibbs = item
            }
        }
        finish()
        return records
    }
}
