import Foundation

public enum SketchRingTemplate: String, CaseIterable, Sendable {
    case benzene = "Benzene", cyclopropane = "Cyclopropane", cyclobutane = "Cyclobutane"
    case cyclopentane = "Cyclopentane", cyclohexane = "Cyclohexane", cycloheptane = "Cycloheptane", cyclooctane = "Cyclooctane"
    case cyclopentene = "Cyclopentene", cyclohexene = "Cyclohexene", cyclopentadiene = "Cyclopentadiene"
    case pyridine = "Pyridine", pyrrole = "Pyrrole", furan = "Furan", thiophene = "Thiophene"
    public var elements: [String] {
        switch self {
        case .cyclopropane: return Array(repeating: "C", count: 3)
        case .cyclobutane: return Array(repeating: "C", count: 4)
        case .cyclopentane, .cyclopentene, .cyclopentadiene: return Array(repeating: "C", count: 5)
        case .cycloheptane: return Array(repeating: "C", count: 7)
        case .cyclooctane: return Array(repeating: "C", count: 8)
        case .pyridine: return ["C", "C", "N", "C", "C", "C"]
        case .pyrrole: return ["C", "C", "N", "C", "C"]
        case .furan: return ["C", "C", "O", "C", "C"]
        case .thiophene: return ["C", "C", "S", "C", "C"]
        default: return Array(repeating: "C", count: 6)
        }
    }
    public var bondOrders: [Int] {
        switch self {
        case .benzene, .pyridine: return [2, 1, 2, 1, 2, 1]
        case .pyrrole, .furan, .thiophene, .cyclopentadiene: return [2, 1, 1, 2, 1]
        case .cyclopentene, .cyclohexene: return [2] + Array(repeating: 1, count: elements.count - 1)
        default: return Array(repeating: 1, count: elements.count)
        }
    }
}

extension MolecularSketch {
    /// Standard skeletal drawing angles; independent of any 3D geometry optimization.
    public func suggestedBondAngle(from id: Int, order: Int = 1) throws -> Double {
        guard let atom = atoms.first(where: { $0.id == id }) else { throw ParseError.malformed("Missing chain anchor.") }
        let edges = bonds.filter { $0.a == id || $0.b == id }
        let neighbors = edges.compactMap { edge in atoms.first { $0.id == (edge.a == id ? edge.b : edge.a) } }
        guard let neighbor = neighbors.first else { return .pi / 6 }
        if neighbors.count == 1 {
            let incoming = atan2(atom.y - neighbor.y, atom.x - neighbor.x)
            if order == 3 || edges[0].order == 3 { return incoming }
            let previous = bonds.filter { ($0.a == neighbor.id || $0.b == neighbor.id) && $0.a != id && $0.b != id }
                .compactMap { edge in atoms.first { $0.id == (edge.a == neighbor.id ? edge.b : edge.a) } }.first
            var sign = -1.0
            if let previous {
                let ux = neighbor.x - previous.x, uy = neighbor.y - previous.y
                let vx = atom.x - neighbor.x, vy = atom.y - neighbor.y
                sign = ux * vy - uy * vx > 1e-8 ? -1 : 1
            }
            let preferred = incoming + sign * .pi / 3, alternate = incoming - sign * .pi / 3
            func clearance(_ angle: Double) -> Double {
                let x = atom.x + 48 * cos(angle), y = atom.y + 48 * sin(angle)
                return atoms.filter { $0.id != id }.map { hypot($0.x - x, $0.y - y) }.min() ?? 100
            }
            return clearance(preferred) < 25 && clearance(alternate) > clearance(preferred) ? alternate : preferred
        }
        let angles = neighbors.map { atan2($0.y - atom.y, $0.x - atom.x) }
        return (0..<12).map { Double($0) * .pi / 6 }.max { a, b in
            func gap(_ angle: Double) -> Double { angles.map { abs(atan2(sin(angle - $0), cos(angle - $0))) }.min() ?? .pi }
            return gap(a) < gap(b)
        } ?? .pi / 6
    }
    @discardableResult public mutating func addZigzagChain(from anchor: Int, bonds count: Int, axis: Double) throws -> Int {
        guard (1...100).contains(count), axis.isFinite, let start = atoms.first(where: { $0.id == anchor }) else { throw ParseError.malformed("Choose a chain of 1–100 bonds with a valid anchor.") }
        var next = self, previous = anchor
        let suggested = try suggestedBondAngle(from: anchor)
        func distance(_ angle: Double) -> Double { abs(atan2(sin(angle - suggested), cos(angle - suggested))) }
        let sign = distance(axis + .pi / 6) <= distance(axis - .pi / 6) ? 1.0 : -1.0
        var x = start.x, y = start.y
        for i in 0..<count {
            let angle = axis + (i % 2 == 0 ? sign : -sign) * .pi / 6
            x += 48 * cos(angle); y += 48 * sin(angle)
            let id = try next.addAtom("C", x: x, y: y)
            try next.connect(previous, id, order: 1); previous = id
        }
        try next.validate(); self = next; return previous
    }
    public mutating func addRing(template: SketchRingTemplate, x: Double, y: Double, anchor: Int? = nil) throws {
        var next = self
        let existing = Set(atoms.map(\.id))
        try next.addRing(size: template.elements.count, x: x, y: y, anchor: anchor)
        let ids = (anchor.map { [$0] } ?? []) + next.atoms.filter { !existing.contains($0.id) }.map(\.id)
        for (i, id) in ids.enumerated() {
            if id != anchor, let index = next.atoms.firstIndex(where: { $0.id == id }) { next.atoms[index].element = template.elements[i] }
            try next.connect(id, ids[(i + 1) % ids.count], order: template.bondOrders[i])
        }
        try next.validate(); self = next
    }
}
