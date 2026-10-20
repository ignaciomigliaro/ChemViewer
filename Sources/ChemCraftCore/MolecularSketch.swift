import Foundation

/// A drawing stores explicit connectivity, independently of inferred 3D bonds.
public struct MolecularSketch: Codable, Equatable, Sendable {
    public struct Node: Codable, Equatable, Identifiable, Sendable {
        public var id: Int
        public var element: String
        public var x: Double
        public var y: Double
        public var charge: Int = 0
        public var chiralTag: Int = 0
        public var explicitHs: Int? = nil
        public var noImplicit: Bool? = nil
        public var radicalElectrons: Int? = nil
        public init(id: Int, element: String, x: Double, y: Double, charge: Int = 0, chiralTag: Int = 0) {
            self.id = id; self.element = element; self.x = x; self.y = y; self.charge = charge; self.chiralTag = chiralTag
        }
    }
    public struct Edge: Codable, Equatable, Sendable {
        public var a: Int
        public var b: Int
        public var order: Int
        public var stereo: String = "none"
        public var bondStereo: Int? = nil
        public var stereoAtoms: [Int]? = nil
        public init(a: Int, b: Int, order: Int = 1, stereo: String = "none") { self.a = a; self.b = b; self.order = order; self.stereo = stereo }
    }
    public var atoms: [Node] = []
    public var bonds: [Edge] = []
    public init() {}
    public func validate() throws {
        let ids = Set(atoms.map(\.id))
        guard atoms.count <= 500, bonds.count <= 1000, ids.count == atoms.count,
              atoms.allSatisfy({ $0.id >= 0 && $0.id < 1000000 && $0.x.isFinite && $0.y.isFinite && abs($0.x) < 1e6 && abs($0.y) < 1e6 && BuildingProject.validatedElement($0.element) == $0.element && $0.element != "X" && (-8...8).contains($0.charge) && (0...2).contains($0.chiralTag) && (0...8).contains($0.explicitHs ?? 0) && (0...8).contains($0.radicalElectrons ?? 0) }),
              bonds.allSatisfy({ ids.contains($0.a) && ids.contains($0.b) && $0.a != $0.b && (1...3).contains($0.order) && ["none", "up", "down"].contains($0.stereo) && ($0.stereo == "none" || $0.order == 1) && (0...5).contains($0.bondStereo ?? 0) && ($0.stereoAtoms == nil || ($0.stereoAtoms?.count == 2 && $0.stereoAtoms!.allSatisfy(ids.contains))) }),
              Set(bonds.map { "\(min($0.a, $0.b)):\(max($0.a, $0.b))" }).count == bonds.count else {
            throw ParseError.malformed("Invalid drawing: use real elements, unique atoms/bonds, finite coordinates and bond orders 1–3 (maximum 500 atoms).")
        }
    }
    @discardableResult public mutating func addAtom(_ element: String, x: Double, y: Double) throws -> Int {
        guard let symbol = BuildingProject.validatedElement(element), symbol != "X", atoms.count < 500, x.isFinite, y.isFinite, abs(x) < 1e6, abs(y) < 1e6 else { throw ParseError.malformed("Choose a chemical element and a valid drawing position.") }
        let previousID = atoms.map(\.id).max() ?? -1
        guard previousID < 999999 else { throw ParseError.malformed("Drawing atom IDs exceed the supported range.") }
        let id = previousID + 1
        atoms.append(Node(id: id, element: symbol, x: x, y: y)); return id
    }
    public mutating func connect(_ a: Int, _ b: Int, order: Int, stereo: String = "none") throws {
        var next = self
        next.bonds.removeAll { Set([$0.a, $0.b]) == Set([a, b]) }
        next.bonds.append(Edge(a: a, b: b, order: order, stereo: stereo))
        try next.validate(); self = next
    }
    public mutating func removeAtom(_ id: Int) {
        atoms.removeAll { $0.id == id }; bonds.removeAll { $0.a == id || $0.b == id }
        for index in bonds.indices where bonds[index].stereoAtoms?.contains(id) == true {
            bonds[index].bondStereo = nil; bonds[index].stereoAtoms = nil
        }
    }
    /// Regular carbon rings use 48 drawing units per bond; an existing atom can be shared.
    public mutating func addRing(size: Int, aromatic: Bool = false, x: Double, y: Double, anchor: Int? = nil) throws {
        guard (3...8).contains(size), !aromatic || size == 6 else { throw ParseError.malformed("Choose a 3–8-membered ring or benzene.") }
        var next = self
        let radius = 48 / (2 * sin(Double.pi / Double(size)))
        let origin = anchor.flatMap { id in atoms.first { $0.id == id } }
        if anchor != nil && origin == nil { throw ParseError.malformed("Ring anchor is missing.") }
        let cx = origin.map { $0.x + radius } ?? x, cy = origin?.y ?? y
        var ids: [Int] = []
        for i in 0..<size {
            if i == 0, let anchor { ids.append(anchor); continue }
            let theta = Double.pi + Double(i) * 2 * Double.pi / Double(size)
            ids.append(try next.addAtom("C", x: cx + radius * cos(theta), y: cy + radius * sin(theta)))
        }
        for i in 0..<size { try next.connect(ids[i], ids[(i + 1) % size], order: aromatic && i % 2 == 0 ? 2 : 1) }
        try next.validate(); self = next
    }
}
