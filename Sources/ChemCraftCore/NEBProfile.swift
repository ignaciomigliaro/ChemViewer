import Foundation

public struct NEBImage: Equatable, Sendable {
    public let name: String
    public let imageIndex: Int?
    public let energyHartree: Double
    public let relativeKcal: Double
    public let isTransitionState: Bool
    public let isClimbingImage: Bool
    public let sourceLine: Int
    public var atoms: [Atom] = []
    public var structureSource: String?
}

public struct NEBProfile: Equatable, Sendable {
    public fileprivate(set) var images: [NEBImage]
    public let sourceLine: Int
    public let isNEBTS: Bool
    public let tsConverged: Bool
    public var reactant: NEBImage { images.first { $0.imageIndex == 0 }! }
    public var product: NEBImage { images.last { $0.imageIndex != nil }! }
    public var transitionState: NEBImage? { images.first { $0.isTransitionState } }
    public var forwardBarrierKcal: Double? { transitionState.map { $0.relativeKcal - reactant.relativeKcal } }
    public var reverseBarrierKcal: Double? { transitionState.map { $0.relativeKcal - product.relativeKcal } }
    public var reactionEnergyKcal: Double { product.relativeKcal - reactant.relativeKcal }
}

public enum ORCANEBParser {
    public static func parse(lines: [String]) -> NEBProfile? {
        // Use the last summary only. Never substitute a prior job's complete path for a truncated final summary.
        guard let start = lines.lastIndex(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("PATH SUMMARY") }),
              let header = ((start + 1)..<min(start + 12, lines.count)).first(where: { lines[$0].contains("E(Eh)") && lines[$0].contains("dE(kcal/mol)") }) else { return nil }
        let distanceColumn = lines[header].contains("Dist.")
        var images: [NEBImage] = []
        for i in (header + 1)..<lines.count {
            let row = lines[i].split(whereSeparator: \.isWhitespace).map(String.init)
            if row.isEmpty { if !images.isEmpty { break }; continue }
            guard let label = row.first else { return nil }
            if label != "TS" && Int(label) == nil {
                guard label.allSatisfy({ $0 == "-" }) || label == "STATISTICS" || lines[i].contains("Straight line distance") else { return nil }
                break
            }
            let energyIndex = distanceColumn ? 2 : 1
            func number(_ token: String) -> Double? { Double(token.replacingOccurrences(of: "D", with: "E").replacingOccurrences(of: "d", with: "e")) }
            guard row.count > energyIndex + 1, let energy = number(row[energyIndex]), let relative = number(row[energyIndex + 1]), energy.isFinite, relative.isFinite else { return nil }
            images.append(NEBImage(name: label, imageIndex: Int(label), energyHartree: energy, relativeKcal: relative, isTransitionState: label == "TS", isClimbingImage: lines[i].contains("<= CI"), sourceLine: i + 1))
        }
        let indices = images.compactMap(\.imageIndex)
        guard indices.count >= 2, indices == Array(0..<indices.count), images.filter(\.isTransitionState).count <= 1 else { return nil }
        if let settings = lines[..<start].last(where: { $0.contains("Number of intermediate images") }),
           let last = settings.split(whereSeparator: \.isWhitespace).last, let intermediate = Int(last),
           indices.count != intermediate + 2 { return nil }
        let isTS = lines[start].contains("NEB-TS")
        if isTS && !images.contains(where: \.isTransitionState) { return nil }
        let contextStart = max(0, (lines[..<start].lastIndex(where: { $0.contains("PATH SUMMARY") }) ?? 0))
        let converged = lines[contextStart..<start].contains { $0.contains("THE TS OPTIMIZATION HAS CONVERGED") }
        return NEBProfile(images: images, sourceLine: start + 1, isNEBTS: isTS, tsConverged: converged)
    }

    public static func loadCompanionStructures(profile: NEBProfile, outputURL: URL) -> NEBProfile {
        var result = profile
        let base = outputURL.deletingPathExtension()
        func frames(_ suffix: String) -> [MoleculeFrame] {
            let url = URL(fileURLWithPath: base.path + suffix)
            guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 20_000_000,
                  let data = try? Data(contentsOf: url, options: [.mappedIfSafe]), let text = String(data: data, encoding: .utf8), let doc = try? XYZParser.parse(text: text), doc.frames.count <= 2000 else { return [] }
            return doc.frames
        }
        let path = frames("_MEP_trj.xyz"), ts = frames("_NEB-TS_converged.xyz")
        let elements = path.first?.atoms.map(\.element) ?? ts.first?.atoms.map(\.element)
        for i in result.images.indices {
            let point = result.images[i]
            let candidate: MoleculeFrame?
            let suffix: String
            if point.isTransitionState { candidate = ts.count == 1 ? ts.first : nil; suffix = "_NEB-TS_converged.xyz" }
            else { candidate = path.count == profile.images.compactMap(\.imageIndex).count ? point.imageIndex.flatMap { path.indices.contains($0) ? path[$0] : nil } : nil; suffix = "_MEP_trj.xyz" }
            guard let frame = candidate, frame.atoms.count <= 10_000, frame.atoms.map(\.element) == elements else { continue }
            let tokens = frame.comment.split(whereSeparator: \.isWhitespace)
            guard let eIndex = tokens.lastIndex(of: "E"), eIndex + 1 < tokens.count, let energy = Double(tokens[eIndex + 1]), abs(energy - point.energyHartree) <= 0.0000055 else { continue }
            result.images[i].atoms = frame.atoms
            result.images[i].structureSource = base.lastPathComponent + suffix
        }
        return result
    }
}
