import Foundation

public enum GeometryEditError: LocalizedError, Equatable {
    case atomIndexOutOfRange(Int)
    case invalidDistance(Float)
    case coincidentAtoms

    public var errorDescription: String? {
        switch self {
        case .atomIndexOutOfRange(let index):
            return "Atom index \(index) is outside this geometry."
        case .invalidDistance(let distance):
            return "Bond length must be positive; received \(distance)."
        case .coincidentAtoms:
            return "A bond direction cannot be inferred from coincident atoms."
        }
    }
}

public enum GeometryEditor {
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
        guard targetLength > 0 else { throw GeometryEditError.invalidDistance(targetLength) }
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
