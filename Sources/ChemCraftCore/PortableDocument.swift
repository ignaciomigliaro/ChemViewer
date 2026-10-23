import Foundation

/// Versioned presentation boundary shared by the portable executable and tests.
/// No scientific values are inferred here. Nil energies/intensities remain absent.
public struct PortableDocument: Encodable {
    public struct Point: Encodable {
        public let element: String
        public let position: [Float]
        public let color: [Float]
    }
    public struct Frame: Encodable {
        public let atoms: [Point]
        public let bonds: [[Int]]
        public let energyHartree: Double?
        public let comment: String
        public let xyz: String
    }
    public struct Mode: Encodable {
        public let index: Int
        public let frequencyCM1: Double
        public let infraredIntensity: Double?
        public let ramanActivity: Double?
        public let displacements: [[Float]]
    }
    public let schemaVersion = 1
    public let title: String
    public let sourceFormat: String
    public let coordinateUnit = "angstrom"
    public let energyUnit = "hartree"
    public let frames: [Frame]
    public let modes: [Mode]
    public let vibrationalFrameIndex: Int?
    public let charge: Int?
    public let multiplicity: Int?
    public let warnings: [String]
    public let source: String

    public init(document: ParsedDocument, source: String) {
        title = document.title; sourceFormat = document.sourceFormat
        charge = document.charge; multiplicity = document.multiplicity
        vibrationalFrameIndex = document.vibrationalFrameIndex
        warnings = document.warnings; self.source = source
        frames = document.frames.map { frame in
            Frame(atoms: frame.atoms.map { atom in
                let c = ElementTable.color(for: atom.element)
                return Point(element: atom.element, position: [atom.position.x, atom.position.y, atom.position.z], color: [c.0, c.1, c.2])
            }, bonds: BondBuilder.inferBonds(atoms: frame.atoms).map { [$0.first, $0.second] },
            energyHartree: frame.energyHartree, comment: frame.comment, xyz: XYZWriter.string(frame: frame))
        }
        modes = document.vibrationalModes.map {
            Mode(index: $0.index, frequencyCM1: $0.frequencyCM1, infraredIntensity: $0.infraredIntensity,
                 ramanActivity: $0.ramanActivity, displacements: $0.displacements.map { [$0.x, $0.y, $0.z] })
        }
    }

    public func json() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return try encoder.encode(self)
    }

    /// Base64 prevents source text (including closing script tags) becoming HTML.
    public func html(template: String) throws -> String {
        template.replacingOccurrences(of: "__CHEMVIEWER_DATA__", with: try json().base64EncodedString())
    }
}
