import Foundation

public struct Vector3: Equatable, Sendable {
    public var x: Float
    public var y: Float
    public var z: Float

    public init(_ x: Float, _ y: Float, _ z: Float) {
        self.x = x
        self.y = y
        self.z = z
    }

    public static let zero = Vector3(0, 0, 0)

    public static func + (lhs: Vector3, rhs: Vector3) -> Vector3 {
        Vector3(lhs.x + rhs.x, lhs.y + rhs.y, lhs.z + rhs.z)
    }

    public static func - (lhs: Vector3, rhs: Vector3) -> Vector3 {
        Vector3(lhs.x - rhs.x, lhs.y - rhs.y, lhs.z - rhs.z)
    }

    public static func * (lhs: Vector3, rhs: Float) -> Vector3 {
        Vector3(lhs.x * rhs, lhs.y * rhs, lhs.z * rhs)
    }

    public var length: Float { sqrt(x * x + y * y + z * z) }
}

public struct Atom: Identifiable, Equatable, Sendable {
    public let id: Int
    public var element: String
    public var position: Vector3

    public init(id: Int, element: String, position: Vector3) {
        self.id = id
        self.element = ElementTable.canonicalSymbol(element)
        self.position = position
    }
}

public struct Bond: Identifiable, Equatable, Sendable {
    public let id: Int
    public let first: Int
    public let second: Int
    public var order: Float

    public init(id: Int, first: Int, second: Int, order: Float = 1) {
        self.id = id
        self.first = first
        self.second = second
        self.order = order
    }
}

public struct MoleculeFrame: Identifiable, Equatable, Sendable {
    public let id: Int
    public var atoms: [Atom]
    public var comment: String
    public var energyHartree: Double?

    public init(id: Int, atoms: [Atom], comment: String = "", energyHartree: Double? = nil) {
        self.id = id
        self.atoms = atoms
        self.comment = comment
        self.energyHartree = energyHartree
    }
}

public struct VibrationalMode: Identifiable, Equatable, Sendable {
    public var id: Int { index }
    public let index: Int
    public var frequencyCM1: Double
    public var infraredIntensity: Double?
    public var ramanActivity: Double?
    public var displacements: [Vector3]

    public init(
        index: Int,
        frequencyCM1: Double,
        infraredIntensity: Double? = nil,
        ramanActivity: Double? = nil,
        displacements: [Vector3] = []
    ) {
        self.index = index
        self.frequencyCM1 = frequencyCM1
        self.infraredIntensity = infraredIntensity
        self.ramanActivity = ramanActivity
        self.displacements = displacements
    }

    public var isImaginary: Bool { frequencyCM1 < 0 }
}

public struct ParsedDocument: Equatable, Sendable {
    public var title: String
    public var sourceFormat: String
    public var frames: [MoleculeFrame]
    public var vibrationalModes: [VibrationalMode]
    public var vibrationalFrameIndex: Int?
    public var nebProfile: NEBProfile?
    public var thermochemistry: [ThermochemistryRecord]
    public var energyRecords: [EnergyRecord]
    public var warnings: [String]
    public var charge: Int?
    public var multiplicity: Int?

    public init(
        title: String,
        sourceFormat: String,
        frames: [MoleculeFrame],
        vibrationalModes: [VibrationalMode] = [],
        vibrationalFrameIndex: Int? = nil,
        warnings: [String] = [],
        energyRecords: [EnergyRecord] = [],
        thermochemistry: [ThermochemistryRecord] = [],
        nebProfile: NEBProfile? = nil,
        charge: Int? = nil,
        multiplicity: Int? = nil
    ) {
        self.charge = charge; self.multiplicity = multiplicity
        self.nebProfile = nebProfile
        self.title = title
        self.sourceFormat = sourceFormat
        self.frames = frames
        self.vibrationalModes = vibrationalModes
        self.vibrationalFrameIndex = vibrationalFrameIndex
        self.warnings = warnings
        self.energyRecords = energyRecords
        self.thermochemistry = thermochemistry
    }
}

public enum ParseError: LocalizedError, Equatable {
    case unsupportedFormat
    case malformed(String)
    case noGeometry

    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            return "The file format is not supported yet."
        case .malformed(let detail):
            return "Malformed chemistry file: \(detail)"
        case .noGeometry:
            return "No Cartesian geometry was found."
        }
    }
}

public enum ElementTable {
    private static let symbols = [
        "X", "H", "He", "Li", "Be", "B", "C", "N", "O", "F", "Ne",
        "Na", "Mg", "Al", "Si", "P", "S", "Cl", "Ar", "K", "Ca",
        "Sc", "Ti", "V", "Cr", "Mn", "Fe", "Co", "Ni", "Cu", "Zn",
        "Ga", "Ge", "As", "Se", "Br", "Kr", "Rb", "Sr", "Y", "Zr",
        "Nb", "Mo", "Tc", "Ru", "Rh", "Pd", "Ag", "Cd", "In", "Sn",
        "Sb", "Te", "I", "Xe"
    ]

    private static let radii: [String: Float] = [
        "H": 0.31, "B": 0.84, "C": 0.76, "N": 0.71, "O": 0.66,
        "F": 0.57, "Si": 1.11, "P": 1.07, "S": 1.05, "Cl": 1.02,
        "Br": 1.20, "I": 1.39, "Fe": 1.32, "Co": 1.26, "Ni": 1.24,
        "Cu": 1.32, "Zn": 1.22
    ]

    public static func canonicalSymbol(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let atomicNumber = Int(trimmed), atomicNumber >= 0, atomicNumber < IntegratedBuilding.elements.count {
            return IntegratedBuilding.elements[atomicNumber]
        }
        guard let first = trimmed.first else { return "X" }
        return String(first).uppercased() + trimmed.dropFirst().lowercased()
    }

    public static func covalentRadius(for element: String) -> Float {
        radii[canonicalSymbol(element)] ?? Float(IntegratedBuilding.editingRadii[canonicalSymbol(element)] ?? 0.9)
    }

    public static func color(for element: String) -> (Float, Float, Float, Float) {
        switch canonicalSymbol(element) {
        case "H": return (0.95, 0.95, 0.95, 1)
        case "C": return (0.18, 0.20, 0.22, 1)
        case "N": return (0.15, 0.28, 0.90, 1)
        case "O": return (0.90, 0.12, 0.10, 1)
        case "F", "Cl": return (0.10, 0.75, 0.18, 1)
        case "S": return (0.95, 0.75, 0.10, 1)
        case "P": return (0.95, 0.45, 0.05, 1)
        case "Br": return (0.55, 0.15, 0.08, 1)
        case "I": return (0.42, 0.12, 0.65, 1)
        case "Fe": return (0.80, 0.35, 0.12, 1)
        default: return (0.35, 0.65, 0.75, 1)
        }
    }
}

public enum BondBuilder {
    public static func inferBonds(atoms: [Atom], tolerance: Float = 1.22) -> [Bond] {
        guard atoms.count > 1, tolerance.isFinite, tolerance > 0 else { return [] }
        struct Cell: Hashable { let x: Int; let y: Int; let z: Int }
        let radii = atoms.map { ElementTable.covalentRadius(for: $0.element) }
        let width = max(1, 2 * (radii.max() ?? 1.4) * tolerance)
        var grid: [Cell: [Int]] = [:], pairs: [(Int, Int)] = []
        var comparisons = 0
        outer: for (i, atom) in atoms.enumerated() {
            let p = atom.position
            let coords = [Double(p.x / width), Double(p.y / width), Double(p.z / width)]
            guard coords.allSatisfy({ $0.isFinite && abs($0) < Double(Int.max / 2) }) else { continue }
            let cell = Cell(x: Int(floor(coords[0])), y: Int(floor(coords[1])), z: Int(floor(coords[2])))
            for dx in -1...1 { for dy in -1...1 { for dz in -1...1 {
                for j in grid[Cell(x: cell.x + dx, y: cell.y + dy, z: cell.z + dz)] ?? [] {
                    comparisons += 1
                    if comparisons > 2_000_000 || pairs.count >= 30_000 { break outer }
                    let distance = (p - atoms[j].position).length
                    if distance > 0.1 && distance <= tolerance * (radii[i] + radii[j]) { pairs.append((j, i)) }
                }
            } } }
            grid[cell, default: []].append(i)
        }
        pairs.sort { $0.0 == $1.0 ? $0.1 < $1.1 : $0.0 < $1.0 }
        return pairs.enumerated().map { Bond(id: $0.offset, first: $0.element.0, second: $0.element.1) }
    }
}
