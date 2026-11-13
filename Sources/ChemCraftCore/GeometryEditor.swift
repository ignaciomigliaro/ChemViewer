import Foundation

public enum GeometryEditError: LocalizedError, Equatable {
    case atomIndexOutOfRange(Int)
    case invalidDistance(Float)
    case invalidAngle(Float)
    case invalidTransform
    case ringBondCannotSplit
    case missingBoundaryBond
    case repeatedAtoms
    case coincidentAtoms

    public var errorDescription: String? {
        switch self {
        case .atomIndexOutOfRange(let index):
            return "Atom index \(index) is outside this geometry."
        case .invalidDistance(let distance):
            return "Bond length must be positive; received \(distance)."
        case .invalidAngle(let angle): return "Angle must be finite and between 0 and 180 degrees; received \(angle)."
        case .invalidTransform: return "Use finite coordinates, a nonzero rotation axis and a finite rotation angle."
        case .ringBondCannotSplit: return "This bond belongs to a ring and does not separate a fragment. Choose another boundary bond."
        case .missingBoundaryBond: return "The selected atoms do not define an inferred bond."
        case .repeatedAtoms: return "Select distinct atoms."
        case .coincidentAtoms:
            return "A bond direction cannot be inferred from coincident atoms."
        }
    }
}

public enum GeometryEditor {
    public static func togglingBond(in frame: MoleculeFrame, first: Int, second: Int) throws -> MoleculeFrame {
        guard first != second else { throw GeometryEditError.repeatedAtoms }
        _ = try position(in: frame, atomIndex: first)
        _ = try position(in: frame, atomIndex: second)
        var result = frame
        var bonds = frame.bonds
        if let index = bonds.firstIndex(where: { Set([$0.first, $0.second]) == Set([first, second]) }) { bonds.remove(at: index) }
        else { bonds.append(Bond(id: bonds.count, first: first, second: second)) }
        result.explicitBonds = bonds.enumerated().map { Bond(id: $0.offset, first: $0.element.first, second: $0.element.second, order: $0.element.order) }
        result.energyHartree = nil; result.comment = "Edited connectivity; energy not recalculated"
        return result
    }

    private struct BondPair: Hashable {
        let first: Int
        let second: Int
        init(_ bond: Bond) { first = min(bond.first, bond.second); second = max(bond.first, bond.second) }
    }

    /// Add distance-inferred connectivity without deleting explicit bonds or orders.
    /// With a previous geometry, add only contacts that became close during this edit;
    /// manually deleted pairs already close before the edit remain absent.
    public static func generatingBonds(in frame: MoleculeFrame, newContactsSince previous: MoleculeFrame? = nil, movingAtomIndices: [Int]? = nil) throws -> MoleculeFrame {
        if let previous {
            guard previous.atoms.count == frame.atoms.count,
                  previous.atoms.map(\.element) == frame.atoms.map(\.element) else { throw GeometryEditError.invalidTransform }
        }
        for index in movingAtomIndices ?? [] { _ = try position(in: frame, atomIndex: index) }
        let moving = movingAtomIndices.map { Set($0) }
        let oldContacts = Set(previous.map { BondBuilder.inferBonds(atoms: $0.atoms).map(BondPair.init) } ?? [])
        var bonds = frame.bonds
        var present = Set(bonds.map(BondPair.init))
        for candidate in BondBuilder.inferBonds(atoms: frame.atoms) {
            let pair = BondPair(candidate)
            if let moving, moving.contains(candidate.first) == moving.contains(candidate.second) { continue }
            if !oldContacts.contains(pair), present.insert(pair).inserted {
                bonds.append(Bond(id: bonds.count, first: candidate.first, second: candidate.second, order: candidate.order))
            }
        }
        var result = frame
        result.explicitBonds = bonds
        if bonds.count != frame.bonds.count { result.energyHartree = nil; result.comment = "Generated connectivity; energy not recalculated" }
        return result
    }

    /// The moving side of a numeric edit. A ligand attached to a fixed metal
    /// stays whole (including chelates), with all metals excluded from traversal.
    private static func editingFragment(in frame: MoleculeFrame, fixed: Int, moving: Int) throws -> [Int] {
        _ = try position(in: frame, atomIndex: fixed)
        _ = try position(in: frame, atomIndex: moving)
        guard fixed != moving else { throw GeometryEditError.repeatedAtoms }
        if ElementTable.isMetal(frame.atoms[fixed].element), !ElementTable.isMetal(frame.atoms[moving].element) {
            return try ligandAtoms(in: frame, seed: moving)
        }
        let boundary = frame.bonds.first { Set([$0.first, $0.second]) == Set([fixed, moving]) }
        let group = try connectedAtoms(in: frame, seed: moving, excluding: boundary)
        guard !group.contains(fixed) else { throw GeometryEditError.ringBondCannotSplit }
        return group
    }

    public static func replacingPosition(
        in frame: MoleculeFrame,
        atomIndex: Int,
        with position: Vector3
    ) throws -> MoleculeFrame {
        guard frame.atoms.indices.contains(atomIndex) else {
            throw GeometryEditError.atomIndexOutOfRange(atomIndex)
        }
        var edited = frame
        edited.atoms[atomIndex].position = position
        return edited
    }

    public static func translating(
        in frame: MoleculeFrame,
        atomIndices: [Int],
        by displacement: Vector3
    ) throws -> MoleculeFrame {
        var edited = frame
        for atomIndex in Set(atomIndices) {
            guard edited.atoms.indices.contains(atomIndex) else {
                throw GeometryEditError.atomIndexOutOfRange(atomIndex)
            }
            edited.atoms[atomIndex].position = edited.atoms[atomIndex].position + displacement
        }
        return edited
    }

    public static func settingBondLength(
        in frame: MoleculeFrame,
        fixedAtomIndex: Int,
        movingAtomIndex: Int,
        to targetLength: Float
    ) throws -> MoleculeFrame {
        guard targetLength.isFinite && targetLength > 0 else { throw GeometryEditError.invalidDistance(targetLength) }
        guard frame.atoms.indices.contains(fixedAtomIndex) else {
            throw GeometryEditError.atomIndexOutOfRange(fixedAtomIndex)
        }
        guard frame.atoms.indices.contains(movingAtomIndex) else {
            throw GeometryEditError.atomIndexOutOfRange(movingAtomIndex)
        }

        let fixed = frame.atoms[fixedAtomIndex].position
        let moving = frame.atoms[movingAtomIndex].position
        let direction = moving - fixed
        let currentLength = direction.length
        guard currentLength > 1e-7 else { throw GeometryEditError.coincidentAtoms }

        return try replacingPosition(
            in: frame,
            atomIndex: movingAtomIndex,
            with: fixed + direction * (targetLength / currentLength)
        )
    }

    public enum DistanceMovement: String, CaseIterable, Sendable {
        case secondFragment = "Move second fragment"
        case bothFragments = "Move both fragments equally"
        case secondAtom = "Move second atom"
        case bothAtoms = "Move both equally"
    }

    public static func settingDistance(in frame: MoleculeFrame, first: Int, second: Int, to target: Float, movement: DistanceMovement) throws -> MoleculeFrame {
        guard first != second else { throw GeometryEditError.repeatedAtoms }
        let moved = try settingBondLength(in: frame, fixedAtomIndex: first, movingAtomIndex: second, to: target)
        if movement == .secondFragment || movement == .bothFragments {
            let right = try editingFragment(in: frame, fixed: first, moving: second)
            let delta = moved.atoms[second].position - frame.atoms[second].position
            var result: MoleculeFrame
            if movement == .bothFragments {
                let left = try editingFragment(in: frame, fixed: second, moving: first)
                guard Set(left).isDisjoint(with: right) else { throw GeometryEditError.ringBondCannotSplit }
                result = try translating(in: frame, atomIndices: left, by: delta * -0.5)
                result = try translating(in: result, atomIndices: right, by: delta * 0.5)
            } else { result = try translating(in: frame, atomIndices: right, by: delta) }
            result.explicitBonds = frame.bonds
            return result
        }
        guard movement == .bothAtoms else { return moved }
        let delta = (moved.atoms[second].position - frame.atoms[second].position) * 0.5
        var result = frame
        result.atoms[first].position = frame.atoms[first].position - delta
        result.atoms[second].position = frame.atoms[second].position + delta
        return result
    }

    public enum AngleMovement: String, CaseIterable, Sendable {
        case thirdFragment = "Move C-side fragment"
        case bothFragments = "Move A/C fragments equally"
        case thirdAtom = "Move C only"
        case bothEnds = "Move A and C equally"
    }

    /// A-B-C: A and B stay fixed; C rotates in the original plane about B.
    /// Both adjacent distances are preserved. Collinear input uses a deterministic plane.
    public static func settingAngle(in frame: MoleculeFrame, first: Int, vertex: Int, third: Int, toDegrees target: Float, movement: AngleMovement = .thirdAtom) throws -> MoleculeFrame {
        guard Set([first, vertex, third]).count == 3 else { throw GeometryEditError.repeatedAtoms }
        guard target.isFinite && target >= 0 && target <= 180 else { throw GeometryEditError.invalidAngle(target) }
        let a = try position(in: frame, atomIndex: first), b = try position(in: frame, atomIndex: vertex), c = try position(in: frame, atomIndex: third)
        let left = a - b, right = c - b
        guard left.length > 1e-7 && right.length > 1e-7 else { throw GeometryEditError.coincidentAtoms }
        let u = left * (1 / left.length)
        var perpendicular = right - u * dot(right, u)
        if perpendicular.length < 1e-7 {
            let reference = abs(u.z) < 0.9 ? Vector3(0, 0, 1) : Vector3(0, 1, 0)
            perpendicular = reference - u * dot(reference, u)
        }
        let v = perpendicular * (1 / perpendicular.length)
        if movement == .thirdFragment || movement == .bothFragments {
            let moving = try editingFragment(in: frame, fixed: vertex, moving: third)
            guard !moving.contains(first) else { throw GeometryEditError.ringBondCannotSplit }
            let current = try angleDegrees(in: frame, firstAtomIndex: first, vertexAtomIndex: vertex, thirdAtomIndex: third)
            let change = target - current, axis = cross(u, v)
            var result: MoleculeFrame
            if movement == .bothFragments {
                let left = try editingFragment(in: frame, fixed: vertex, moving: first)
                guard !left.contains(third), Set(left).isDisjoint(with: moving) else { throw GeometryEditError.ringBondCannotSplit }
                result = try rotating(in: frame, atomIndices: left, around: b, axis: axis, degrees: -change / 2)
                result = try rotating(in: result, atomIndices: moving, around: b, axis: axis, degrees: change / 2)
            } else { result = try rotating(in: frame, atomIndices: moving, around: b, axis: axis, degrees: change) }
            result.explicitBonds = frame.bonds
            return result
        }
        if movement == .bothEnds {
            let current = try angleDegrees(in: frame, firstAtomIndex: first, vertexAtomIndex: vertex, thirdAtomIndex: third)
            let axis = cross(u, v)
            let halfChange = (target - current) / 2
            let firstMoved = try rotating(in: frame, atomIndices: [first], around: b, axis: axis, degrees: -halfChange)
            return try rotating(in: firstMoved, atomIndices: [third], around: b, axis: axis, degrees: halfChange)
        }
        let radians = target * .pi / 180
        return try replacingPosition(in: frame, atomIndex: third, with: b + (u * cos(radians) + v * sin(radians)) * right.length)
    }

    public static func connectedAtoms(in frame: MoleculeFrame, seed: Int, excluding bond: Bond? = nil) throws -> [Int] {
        _ = try position(in: frame, atomIndex: seed)
        var neighbors = Array(repeating: [Int](), count: frame.atoms.count)
        for edge in frame.bonds {
            if let bond, (edge.first == bond.first && edge.second == bond.second) || (edge.first == bond.second && edge.second == bond.first) { continue }
            neighbors[edge.first].append(edge.second); neighbors[edge.second].append(edge.first)
        }
        var seen: Set<Int> = [seed], queue = [seed], cursor = 0
        while cursor < queue.count {
            for next in neighbors[queue[cursor]] where seen.insert(next).inserted { queue.append(next) }
            cursor += 1
        }
        return seen.sorted()
    }

    /// Metal neighbors outside the selected motif, in stable atom-index order.
    public static func coordinatingMetals(in frame: MoleculeFrame, atomIndices: [Int]) throws -> [Int] {
        for index in atomIndices { _ = try position(in: frame, atomIndex: index) }
        let selected = Set(atomIndices)
        var metals: Set<Int> = []
        for bond in frame.bonds {
            if selected.contains(bond.first), !selected.contains(bond.second), ElementTable.isMetal(frame.atoms[bond.second].element) { metals.insert(bond.second) }
            if selected.contains(bond.second), !selected.contains(bond.first), ElementTable.isMetal(frame.atoms[bond.first].element) { metals.insert(bond.first) }
        }
        return metals.sorted()
    }

    /// Connected ligand after ignoring every edge incident to a metal for traversal only.
    /// Multiple donor bonds and bridging ligands are handled together; source bonds remain intact.
    /// A metal seed selects that metal alone.
    public static func ligandAtoms(in frame: MoleculeFrame, seed: Int) throws -> [Int] {
        _ = try position(in: frame, atomIndex: seed)
        if ElementTable.isMetal(frame.atoms[seed].element) { return [seed] }
        var ligandGraph = frame
        ligandGraph.explicitBonds = frame.bonds.filter {
            !ElementTable.isMetal(frame.atoms[$0.first].element) && !ElementTable.isMetal(frame.atoms[$0.second].element)
        }
        return try connectedAtoms(in: ligandGraph, seed: seed)
    }

    /// Ligand seed: stop at every metal. Metal seed: include its attached motif,
    /// stopping at all other metals, including across metal-metal bonds.
    public static func fragmentAtoms(in frame: MoleculeFrame, seed: Int) throws -> [Int] {
        _ = try position(in: frame, atomIndex: seed)
        guard ElementTable.isMetal(frame.atoms[seed].element) else { return try ligandAtoms(in: frame, seed: seed) }
        var graph = frame
        graph.explicitBonds = frame.bonds.filter {
            ($0.first == seed || !ElementTable.isMetal(frame.atoms[$0.first].element)) &&
            ($0.second == seed || !ElementTable.isMetal(frame.atoms[$0.second].element))
        }
        return try connectedAtoms(in: graph, seed: seed)
    }

    public static func rotationMetalCenters(in frame: MoleculeFrame, atomIndices: [Int]) throws -> [Int] {
        for index in atomIndices { _ = try position(in: frame, atomIndex: index) }
        let selected = Set(atomIndices.filter { ElementTable.isMetal(frame.atoms[$0].element) }).sorted()
        return selected.isEmpty ? try coordinatingMetals(in: frame, atomIndices: atomIndices) : selected
    }

    public static func fragment(in frame: MoleculeFrame, fixed: Int, moving: Int) throws -> [Int] {
        _ = try position(in: frame, atomIndex: fixed)
        _ = try position(in: frame, atomIndex: moving)
        guard fixed != moving else { throw GeometryEditError.repeatedAtoms }
        guard let boundary = frame.bonds.first(where: { ($0.first == fixed && $0.second == moving) || ($0.first == moving && $0.second == fixed) }) else { throw GeometryEditError.missingBoundaryBond }
        let group = try connectedAtoms(in: frame, seed: moving, excluding: boundary)
        guard !group.contains(fixed) else { throw GeometryEditError.ringBondCannotSplit }
        return group
    }

    public static func rotating(in frame: MoleculeFrame, atomIndices: [Int], around pivot: Vector3, axis: Vector3, degrees: Float) throws -> MoleculeFrame {
        guard [pivot.x, pivot.y, pivot.z, axis.x, axis.y, axis.z, degrees].allSatisfy({ $0.isFinite }), axis.length > 1e-7 else { throw GeometryEditError.invalidTransform }
        let u = axis * (1 / axis.length), angle = degrees * .pi / 180
        var result = frame
        for index in Set(atomIndices) {
            let p = try position(in: frame, atomIndex: index) - pivot
            result.atoms[index].position = pivot + p * cos(angle) + cross(u, p) * sin(angle) + u * (dot(u, p) * (1 - cos(angle)))
        }
        return result
    }

    public static func distance(
        in frame: MoleculeFrame,
        firstAtomIndex: Int,
        secondAtomIndex: Int
    ) throws -> Float {
        guard frame.atoms.indices.contains(firstAtomIndex) else {
            throw GeometryEditError.atomIndexOutOfRange(firstAtomIndex)
        }
        guard frame.atoms.indices.contains(secondAtomIndex) else {
            throw GeometryEditError.atomIndexOutOfRange(secondAtomIndex)
        }
        return (frame.atoms[firstAtomIndex].position - frame.atoms[secondAtomIndex].position).length
    }

    public static func angleDegrees(
        in frame: MoleculeFrame,
        firstAtomIndex: Int,
        vertexAtomIndex: Int,
        thirdAtomIndex: Int
    ) throws -> Float {
        let first = try position(in: frame, atomIndex: firstAtomIndex)
        let vertex = try position(in: frame, atomIndex: vertexAtomIndex)
        let third = try position(in: frame, atomIndex: thirdAtomIndex)
        let left = first - vertex
        let right = third - vertex
        guard left.length > 1e-7, right.length > 1e-7 else {
            throw GeometryEditError.coincidentAtoms
        }
        let cosine = min(max(dot(left, right) / (left.length * right.length), -1), 1)
        return acos(cosine) * 180 / .pi
    }

    public static func dihedralDegrees(
        in frame: MoleculeFrame,
        firstAtomIndex: Int,
        secondAtomIndex: Int,
        thirdAtomIndex: Int,
        fourthAtomIndex: Int
    ) throws -> Float {
        let p0 = try position(in: frame, atomIndex: firstAtomIndex)
        let p1 = try position(in: frame, atomIndex: secondAtomIndex)
        let p2 = try position(in: frame, atomIndex: thirdAtomIndex)
        let p3 = try position(in: frame, atomIndex: fourthAtomIndex)
        let b0 = p0 - p1
        let b1 = p2 - p1
        let b2 = p3 - p2
        guard b1.length > 1e-7 else { throw GeometryEditError.coincidentAtoms }
        let axis = b1 * (1 / b1.length)
        let v = b0 - axis * dot(b0, axis)
        let w = b2 - axis * dot(b2, axis)
        guard v.length > 1e-7, w.length > 1e-7 else {
            throw GeometryEditError.coincidentAtoms
        }
        return atan2(dot(cross(axis, v), w), dot(v, w)) * 180 / .pi
    }

    private static func position(in frame: MoleculeFrame, atomIndex: Int) throws -> Vector3 {
        guard frame.atoms.indices.contains(atomIndex) else {
            throw GeometryEditError.atomIndexOutOfRange(atomIndex)
        }
        return frame.atoms[atomIndex].position
    }

    private static func dot(_ lhs: Vector3, _ rhs: Vector3) -> Float {
        lhs.x * rhs.x + lhs.y * rhs.y + lhs.z * rhs.z
    }

    private static func cross(_ lhs: Vector3, _ rhs: Vector3) -> Vector3 {
        Vector3(
            lhs.y * rhs.z - lhs.z * rhs.y,
            lhs.z * rhs.x - lhs.x * rhs.z,
            lhs.x * rhs.y - lhs.y * rhs.x
        )
    }
}
