import Foundation
import simd

public struct CalculationFact: Equatable, Sendable {
    public let label: String
    public let value: String
    public let unit: String
    public let line: Int
    public let job: Int
}

public struct BuildingProject: Codable {
    private var state: IntegratedBuilding.EditableProject
    public var atoms: [Atom] { Self.convert(state.atoms) }
    public var groups: [[Int]] { state.groups }
    public var selection: [Int] { state.selection }
    public var charge: Int { get { state.charge } set { state.charge = newValue } }
    public var multiplicity: Int { get { state.multiplicity } set { state.multiplicity = newValue } }
    public init(atoms: [Atom], groups: [[Int]] = [], selection: [Int] = [], charge: Int = 0, multiplicity: Int = 1) throws {
        state = .init(atoms: Self.convert(atoms), groups: groups, selection: selection, charge: charge, multiplicity: multiplicity)
        try state.validate()
    }
    public init(from decoder: Decoder) throws { state = try .init(from: decoder) }
    public func encode(to encoder: Encoder) throws { try state.encode(to: encoder) }
    private init(_ state: IntegratedBuilding.EditableProject) throws { try state.validate(); self.state = state }
    private static func convert(_ atoms: [Atom]) -> [IntegratedBuilding.Atom] { atoms.map { .init(symbol: $0.element, x: Double($0.position.x), y: Double($0.position.y), z: Double($0.position.z)) } }
    private static func convert(_ atoms: [IntegratedBuilding.Atom]) -> [Atom] { atoms.enumerated().map { .init(id: $0.offset, element: $0.element.symbol, position: Vector3(Float($0.element.x), Float($0.element.y), Float($0.element.z))) } }
    public static var fragmentNames: [String] { IntegratedBuilding.builtInFragments.map(\.name) }
    public static var elements: [String] { IntegratedBuilding.elements }
    public static func fragment(_ index: Int) -> [Atom] { convert(IntegratedBuilding.builtInFragments[min(max(index, 0), IntegratedBuilding.builtInFragments.count - 1)].atoms) }
    public func deleting(_ indices: [Int]) throws -> Self { try Self(state.deleting(Set(indices))) }
    public func appending(_ atoms: [Atom]) throws -> Self { try Self(state.appending(Self.convert(atoms))) }
    public func attaching(_ fragment: [Atom], hostLeaving: Int, fragmentLeaving: Int, bondLength: Double? = nil) throws -> Self {
        let result = try IntegratedBuilding.attachFragment(host: state.atoms, hostLeaving: hostLeaving, fragment: Self.convert(fragment), fragmentLeaving: fragmentLeaving, bondLength: bondLength)
        return try Self(state.attaching(result, hostLeaving: hostLeaving))
    }
    /// A heavy-atom click adds a new substituent along the least crowded sampled direction.
    /// Selecting a terminal H/X instead replaces that site using the existing alignment.
    public func attachingAtAtom(_ fragment: [Atom], hostAtom: Int, fragmentLeaving: Int) throws -> Self {
        guard atoms.indices.contains(hostAtom) else { throw ParseError.malformed("Select a host atom.") }
        if ["H", "X"].contains(atoms[hostAtom].element) {
            return try attaching(fragment, hostLeaving: hostAtom, fragmentLeaving: fragmentLeaving)
        }
        let origin = atoms[hostAtom].position
        // Prefer an existing terminal H/X on the clicked anchor, avoiding a
        // fifth bond when adding a substituent to a saturated carbon.
        let leavingSites = atoms.indices.filter { candidate in
            guard ["H", "X"].contains(atoms[candidate].element) else { return false }
            let limit: Float = atoms[candidate].element == "X" ? 2.6 : 1.8
            guard (atoms[candidate].position - origin).length < limit else { return false }
            let nearest = atoms.indices.filter { !["H", "X"].contains(atoms[$0].element) }.min {
                (atoms[$0].position - atoms[candidate].position).length < (atoms[$1].position - atoms[candidate].position).length
            }
            return nearest == hostAtom
        }
        if let site = leavingSites.first {
            return try attaching(fragment, hostLeaving: site, fragmentLeaving: fragmentLeaving)
        }
        let neighbors = atoms.indices.filter { $0 != hostAtom && (atoms[$0].position - origin).length < 3.2 }
        var best = Vector3(1, 0, 0)
        var bestScore: Float = -.infinity
        for k in 0..<96 {
            let z = 1 - 2 * (Float(k) + 0.5) / 96
            let phi = Float(k) * 2.39996323
            let radius = sqrt(max(0, 1 - z * z))
            let direction = Vector3(radius * cos(phi), radius * sin(phi), z)
            let score = neighbors.map { index -> Float in
                let delta = atoms[index].position - origin
                let normalized = delta * (1 / max(delta.length, 1e-6))
                return 1 - (direction.x * normalized.x + direction.y * normalized.y + direction.z * normalized.z)
            }.min() ?? 2
            if score > bestScore { bestScore = score; best = direction }
        }
        let dummy = Atom(id: atoms.count, element: "X", position: origin + best)
        let extended = try appending([dummy])
        return try extended.attaching(fragment, hostLeaving: atoms.count, fragmentLeaving: fragmentLeaving)
    }
    public func attachingAtom(_ element: String, hostAtom: Int) throws -> Self {
        guard Self.elements.contains(element), element != "X" else { throw ParseError.malformed("Choose a chemical element.") }
        // An incoming dummy has an explicit nearest heavy anchor. Hydrogen is added
        // directly along a temporary carbon scaffold and then substituted.
        let anchor = element == "H" ? "C" : element
        let fragment = [Atom(id: 0, element: anchor, position: .zero), Atom(id: 1, element: "X", position: Vector3(1, 0, 0))]
        let attached = try attachingAtAtom(fragment, hostAtom: hostAtom, fragmentLeaving: 1)
        if element != "H" { return attached }
        var next = attached.state
        let inserted = next.atoms.count - 1
        let originalHost = atoms[hostAtom]
        let anchorIndex = ["H", "X"].contains(originalHost.element) ? atoms.indices.filter { !["H", "X"].contains(atoms[$0].element) }.min { (atoms[$0].position - originalHost.position).length < (atoms[$1].position - originalHost.position).length } ?? hostAtom : hostAtom
        let base = atoms[anchorIndex].position
        let end = Self.convert(next.atoms)[inserted].position
        let delta = end - base
        let direction = delta * (1 / max(delta.length, 1e-6))
        next.atoms[inserted] = .init(symbol: "H", x: Double(base.x + direction.x * 1.1), y: Double(base.y + direction.y * 1.1), z: Double(base.z + direction.z * 1.1))
        return try Self(next)
    }
    public func transformed(selection: [Int], translation: Vector3, axis: Vector3, degrees: Float, pivot: Vector3) throws -> Self {
        guard [translation.x, translation.y, translation.z, axis.x, axis.y, axis.z, degrees, pivot.x, pivot.y, pivot.z].allSatisfy(\.isFinite), selection.allSatisfy(atoms.indices.contains) else { throw ParseError.malformed("Invalid transform") }
        var next = state
        next.atoms = IntegratedBuilding.transformedAtoms(state.atoms, selection: Set(selection), translation: SIMD3(Double(translation.x), Double(translation.y), Double(translation.z)), axis: SIMD3(Double(axis.x), Double(axis.y), Double(axis.z)), radians: Double(degrees) * .pi / 180, pivot: SIMD3(Double(pivot.x), Double(pivot.y), Double(pivot.z)))
        return try Self(next)
    }
    public func xyzText() throws -> String { try state.xyzText() }
    public func orcaGeometryText() throws -> String { try state.orcaGeometryText() }
    public static func selection(_ text: String, atomCount: Int) throws -> [Int] {
        var result: [Int] = []
        for token in text.split(separator: ",", omittingEmptySubsequences: false) {
            let fields = token.trimmingCharacters(in: .whitespaces).split(separator: "-", omittingEmptySubsequences: false)
            let indices: [Int]
            if fields.count == 1, let n = Int(fields[0]), n > 0, n <= atomCount { indices = [n - 1] }
            else if fields.count == 2, let a = Int(fields[0]), let b = Int(fields[1]), a > 0, b >= a, b <= atomCount { indices = Array((a - 1)..<b) }
            else { throw ParseError.malformed("Use 1-based atom indices, such as 1,3-6.") }
            for index in indices where !result.contains(index) { result.append(index) }
        }
        return result
    }
    public static func analysis(_ text: String) throws -> (frames: [MoleculeFrame], format: String, modes: [Int: [VibrationalMode]], facts: [CalculationFact]) {
        let parsed = try IntegratedBuilding.parse(text)
        let frames = parsed.frames.enumerated().map { MoleculeFrame(id: $0.offset, atoms: convert($0.element)) }
        var modes: [Int: [VibrationalMode]] = [:]
        for (i, source) in parsed.modesByFrame.enumerated() where !source.isEmpty {
            modes[i] = source.map { VibrationalMode(index: $0.index, frequencyCM1: $0.frequency, displacements: $0.displacements.map { Vector3(Float($0.x), Float($0.y), Float($0.z)) }) }
        }
        return (frames, parsed.format, modes, parsed.facts.map { .init(label: $0.label, value: $0.value, unit: $0.unit, line: $0.line, job: $0.job) })
    }
}
