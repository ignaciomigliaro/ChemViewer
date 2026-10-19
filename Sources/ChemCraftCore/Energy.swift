import Foundation

public enum EnergyUnit: String, CaseIterable, Codable, Sendable {
    case hartree = "Eh", electronVolt = "eV", kilojoulePerMole = "kJ/mol", kilocaloriePerMole = "kcal/mol"
    // CODATA 2022 Hartree energy and exact SI Avogadro constant/calorie.
    public var perHartree: Double {
        switch self {
        case .hartree: return 1
        case .electronVolt: return 27.211386245981
        case .kilojoulePerMole: return 4.3597447222060e-18 * 6.02214076e23 / 1000
        case .kilocaloriePerMole: return EnergyUnit.kilojoulePerMole.perHartree / 4.184
        }
    }
}

public enum EnergyKind: String, Codable, Sendable {
    case scf = "SCF energy", singlePoint = "Final single-point energy", xyzComment = "XYZ comment energy"
}

public struct EnergyRecord: Identifiable, Equatable, Sendable {
    public var id: Int { sourceLine }
    public let value: Double
    public let unit: EnergyUnit?
    public let kind: EnergyKind
    public let frameIndex: Int?
    public let sourceLine: Int // one-based
    public let sourceText: String

    public init(value: Double, unit: EnergyUnit?, kind: EnergyKind, frameIndex: Int?, sourceLine: Int, sourceText: String) {
        self.value = value; self.unit = unit; self.kind = kind; self.frameIndex = frameIndex
        self.sourceLine = sourceLine; self.sourceText = sourceText
    }
    public func hartree(assuming unitForUnlabelledXYZ: EnergyUnit? = nil) -> Double? {
        guard let effective = unit ?? (kind == .xyzComment ? unitForUnlabelledXYZ : nil) else { return nil }
        return value / effective.perHartree
    }
}

public enum XYZCommentEnergy {
    // Accept named energy fields or a comment consisting solely of an energy.
    // Unlabelled numbers remain unassigned until the user chooses a unit.
    private static let number = #"([-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[EeDd][-+]?\d+)?)"#
    private static let named = try! NSRegularExpression(pattern: #"(?i)\b(?:energy|e)(?:[_\s]*(hartree|ha|eh|au|ev))?\s*[:=]\s*"# + number + #"(?![\w.])\s*([A-Za-z./⁻¹0-9-]*)"#)
    private static let bare = try! NSRegularExpression(pattern: #"(?i)^\s*"# + number + #"\s*([A-Za-z./⁻¹0-9-]*)\s*$"#)
    public static func parse(_ comment: String, frameIndex: Int, sourceLine: Int) -> EnergyRecord? {
        let range = NSRange(comment.startIndex..<comment.endIndex, in: comment)
        let match: NSTextCheckingResult
        let numberGroup: Int, unitGroup: Int
        var prefix = ""
        if let found = named.firstMatch(in: comment, range: range) {
            match = found; numberGroup = 2; unitGroup = 3
            if let r = Range(found.range(at: 1), in: comment) { prefix = String(comment[r]) }
        } else if let found = bare.firstMatch(in: comment, range: range) {
            match = found; numberGroup = 1; unitGroup = 2
        } else { return nil }
        func group(_ index: Int) -> String { Range(match.range(at: index), in: comment).map { String(comment[$0]) } ?? "" }
        guard let value = Double(group(numberGroup).replacingOccurrences(of: "D", with: "E").replacingOccurrences(of: "d", with: "e")), value.isFinite else { return nil }
        let suffix = group(unitGroup).lowercased()
        let token = prefix.isEmpty ? suffix : prefix.lowercased()
        let unit: EnergyUnit?
        switch token {
        case "eh", "ha", "hartree", "hartrees", "au", "a.u.", "a.u": unit = .hartree
        case "ev": unit = .electronVolt
        case "kj/mol", "kjmol-1", "kjmol⁻¹": unit = .kilojoulePerMole
        case "kcal/mol", "kcalmol-1", "kcalmol⁻¹": unit = .kilocaloriePerMole
        default: unit = nil
        }
        // A named energy can be followed by unrelated metadata. Unknown explicit
        // units must never become Hartree through the user's unlabelled setting.
        if unit == nil && !token.isEmpty && !["gnorm", "xtb", "frame", "step"].contains(token) { return nil }
        return EnergyRecord(value: value, unit: unit, kind: .xyzComment, frameIndex: frameIndex, sourceLine: sourceLine, sourceText: comment)
    }
}
