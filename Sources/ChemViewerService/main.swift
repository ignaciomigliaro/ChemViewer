import Foundation
import ChemCraftCore

// Private stdio transport: no listener, shell, network access or platform UI.
// A malformed request must not destroy the session or produce partial edits.
struct Request: Decodable {
    var id: Int
    var action: String
    var document: String?
    var path: String?
    var frame: Int?
    var atom: Int?
    var indices: [Int]?
    var position: [Float]?
    var element: String?
    var value: Float?
    var fragment: Int?
    var overwrite: Bool?
}
struct Snapshot {
    var parsed: ParsedDocument
    var revision = UUID().uuidString
}
struct SessionDocument {
    var current: Snapshot
    var source: String
    var path: String?
    var sourceName: String
    var companions: [String: String]
    var savedRevision: String
    var undo: [Snapshot] = []
    var redo: [Snapshot] = []
}
struct Reply: Encodable {
    var id: Int
    var ok: Bool
    var error: String?
    var document: String?
    var data: PortableDocument?
    var dirty: Bool?
    var canUndo: Bool?
    var canRedo: Bool?
    var measurement: Float?
    var fragments: [String]?
}
struct SavedAtom: Codable {
    var element: String
    var position: [Float]
}
struct SavedFrame: Codable {
    var atoms: [SavedAtom]
    init(atoms: [Atom]) {
        self.atoms = atoms.map { SavedAtom(element: $0.element, position: [$0.position.x, $0.position.y, $0.position.z]) }
    }
    func restoredAtoms() throws -> [Atom] {
        let result = try atoms.enumerated().map { index, atom -> Atom in
            guard let element = BuildingProject.validatedElement(atom.element), atom.position.count == 3,
                  atom.position.allSatisfy(\.isFinite) else { throw invalid("Invalid project atom") }
            return Atom(id: index, element: element, position: Vector3(atom.position[0], atom.position[1], atom.position[2]))
        }
        _ = try BuildingProject(atoms: result)
        return result
    }
}
struct Project: Codable {
    var schemaVersion = 1
    var source: String
    var sourceName: String
    var companions: [String: String]
    var frames: [SavedFrame]
    var editedFrames: [Int]
}
var documents: [String: SessionDocument] = [:]
func invalid(_ text: String) -> ParseError { .malformed(text) }
func write(_ data: Data, path: String?, overwrite: Bool) throws {
    guard let path, !path.isEmpty else { throw invalid("A destination path is required") }
    let url = URL(fileURLWithPath: path)
    // Explicit overwrite is granted only by the frontend's save dialog.
    try data.write(to: url, options: overwrite ? .atomic : .withoutOverwriting)
}
func invalidateScience(_ parsed: inout ParsedDocument, frame: Int) {
    parsed.frames[frame].energyHartree = nil
    parsed.frames[frame].comment = "Edited geometry; source calculation values do not apply"
    parsed.energyRecords = []; parsed.thermochemistry = []; parsed.nebProfile = nil
    // A mode belongs to a particular equilibrium geometry; never animate it on edits.
    if parsed.vibrationalFrameIndex == frame || parsed.vibrationalFrameIndex == nil {
        parsed.vibrationalModes = []; parsed.vibrationalFrameIndex = nil
    }
    let warning = "Edited geometry: calculated energy/properties are invalidated. Original source is retained."
    if !parsed.warnings.contains(warning) { parsed.warnings.append(warning) }
}
func handle(_ r: Request) throws -> Reply {
    var reply = Reply(id: r.id, ok: true)
    if r.action == "hello" { reply.fragments = BuildingProject.fragmentNames; return reply }
    if r.action == "open" || r.action == "new" {
        let parsed: ParsedDocument
        let source: String
        var sourceName = "untitled.xyz"
        var companions: [String: String] = [:]
        if r.action == "new" {
            source = ""
            parsed = ParsedDocument(title: "Untitled", sourceFormat: "Builder", frames: [MoleculeFrame(id: 0, atoms: [])])
        } else {
            guard let path = r.path else { throw invalid("An input path is required") }
            let url = URL(fileURLWithPath: path)
            let data = try Data(contentsOf: url)
            if url.pathExtension.lowercased() == "cvdesktop" {
                let project = try JSONDecoder().decode(Project.self, from: data)
                guard project.schemaVersion == 1 else { throw invalid("Unsupported desktop project version") }
                source = project.source
                sourceName = project.sourceName; companions = project.companions
                let savedFrames = try project.frames.map { try $0.restoredAtoms() }
                var restored = source.isEmpty
                    ? ParsedDocument(title: url.deletingPathExtension().lastPathComponent, sourceFormat: "Builder", frames: savedFrames.enumerated().map { MoleculeFrame(id: $0.offset, atoms: $0.element) })
                    : (companions.isEmpty
                       ? try ParserRegistry.parse(text: source, fileName: project.sourceName)
                       : try ORCAInputParser.parse(text: source, title: project.sourceName, resolveXYZ: { name in
                           guard let text = companions[name] else { throw invalid("Missing embedded companion: \(name)") }; return text
                       }))
                guard restored.frames.count == project.frames.count else { throw invalid("Project frame count differs from its source") }
                for (i, atoms) in savedFrames.enumerated() {
                    let differsFromSource = restored.frames[i].atoms != atoms
                    restored.frames[i].atoms = atoms
                    if differsFromSource || project.editedFrames.contains(i) { invalidateScience(&restored, frame: i) }
                }
                parsed = restored
            } else {
                guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { throw invalid("Unsupported source encoding") }
                source = text
                sourceName = url.lastPathComponent
                parsed = try ParserRegistry.parse(text: text, fileName: url.lastPathComponent, baseURL: url)
                if parsed.sourceFormat == "ORCA input" {
                    for name in ORCAInputParser.externalXYZReferences(in: text) {
                        let companion = URL(fileURLWithPath: name, relativeTo: url.deletingLastPathComponent()).standardizedFileURL
                        companions[name] = try String(contentsOf: companion, encoding: .utf8)
                    }
                }
            }
        }
        let snapshot = Snapshot(parsed: parsed)
        let key = UUID().uuidString
        documents[key] = SessionDocument(current: snapshot, source: source, path: r.path, sourceName: sourceName, companions: companions, savedRevision: r.action == "new" ? "" : snapshot.revision)
        reply.document = key
    } else {
        guard let key = r.document, var doc = documents[key] else { throw invalid("Unknown document") }
        reply.document = key
        if r.action == "close" { documents.removeValue(forKey: key); return reply }
        switch r.action {
        case "snapshot": break
        case "undo":
            guard let previous = doc.undo.popLast() else { throw invalid("Nothing to undo") }
            doc.redo.append(doc.current); doc.current = previous
        case "redo":
            guard let next = doc.redo.popLast() else { throw invalid("Nothing to redo") }
            doc.undo.append(doc.current); doc.current = next
        case "save_project":
            let parsed = doc.current.parsed
            let project = Project(source: doc.source, sourceName: doc.sourceName, companions: doc.companions,
                frames: parsed.frames.map { SavedFrame(atoms: $0.atoms) },
                editedFrames: parsed.frames.indices.filter { parsed.frames[$0].comment == "Edited geometry; source calculation values do not apply" })
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
            try write(encoder.encode(project), path: r.path, overwrite: r.overwrite ?? false)
            doc.savedRevision = doc.current.revision
        case "export_xyz":
            guard !doc.current.parsed.frames.isEmpty else { throw ParseError.noGeometry }
            let frames: [MoleculeFrame]
            if let i = r.frame {
                guard doc.current.parsed.frames.indices.contains(i) else { throw invalid("Invalid frame") }
                frames = [doc.current.parsed.frames[i]]
            } else { frames = doc.current.parsed.frames }
            try write(Data(frames.map { XYZWriter.string(frame: $0) }.joined().utf8), path: r.path, overwrite: r.overwrite ?? false)
        case "measure":
            let i = r.frame ?? 0
            guard doc.current.parsed.frames.indices.contains(i) else { throw invalid("Invalid frame") }
            let frame = doc.current.parsed.frames[i], indices = r.indices ?? []
            switch indices.count {
            case 2: reply.measurement = try GeometryEditor.distance(in: frame, firstAtomIndex: indices[0], secondAtomIndex: indices[1])
            case 3: reply.measurement = try GeometryEditor.angleDegrees(in: frame, firstAtomIndex: indices[0], vertexAtomIndex: indices[1], thirdAtomIndex: indices[2])
            case 4: reply.measurement = try GeometryEditor.dihedralDegrees(in: frame, firstAtomIndex: indices[0], secondAtomIndex: indices[1], thirdAtomIndex: indices[2], fourthAtomIndex: indices[3])
            default: throw invalid("Select two, three or four atoms")
            }
        default:
            let i = r.frame ?? 0
            guard doc.current.parsed.frames.indices.contains(i) else { throw invalid("Invalid frame") }
            var parsed = doc.current.parsed
            var frame = parsed.frames[i]
            let building = try BuildingProject(atoms: frame.atoms)
            switch r.action {
            case "position":
                guard let atom = r.atom, let p = r.position, p.count == 3, p.allSatisfy(\.isFinite) else { throw invalid("Expected an atom and three finite coordinates") }
                frame = try GeometryEditor.replacingPosition(in: frame, atomIndex: atom, with: Vector3(p[0], p[1], p[2]))
            case "element":
                guard let atom = r.atom, let element = r.element else { throw invalid("Expected an atom and element") }
                frame.atoms = try building.replacingElement(at: atom, with: element).atoms
            case "delete":
                let indices = r.indices ?? []
                guard !indices.isEmpty, indices.allSatisfy(frame.atoms.indices.contains) else { throw invalid("Select valid atoms to delete") }
                frame.atoms = try building.deleting(indices).atoms
            case "add":
                guard let element = r.element, let valid = BuildingProject.validatedElement(element), let p = r.position, p.count == 3, p.allSatisfy(\.isFinite) else { throw invalid("Expected a valid element and three finite coordinates") }
                frame.atoms = try building.appending([Atom(id: frame.atoms.count, element: valid, position: Vector3(p[0], p[1], p[2]))]).atoms
            case "fragment":
                guard let index = r.fragment, BuildingProject.fragmentNames.indices.contains(index) else { throw invalid("Invalid fragment") }
                let fragment = BuildingProject.fragment(index)
                if let atom = r.atom {
                    guard let leaving = fragment.indices.first(where: { fragment[$0].element == "X" }) else { throw invalid("This fragment has no attachment site; place it separately") }
                    frame.atoms = try building.attachingAtAtom(fragment, hostAtom: atom, fragmentLeaving: leaving).atoms
                } else {
                    guard let p = r.position, p.count == 3, p.allSatisfy(\.isFinite) else { throw invalid("Expected three finite placement coordinates") }
                    frame.atoms = try building.placing(fragment, at: Vector3(p[0], p[1], p[2])).atoms
                }
            case "distance":
                guard let indices = r.indices, indices.count == 2, let target = r.value else { throw invalid("Select two atoms and a distance") }
                frame = try GeometryEditor.settingDistance(in: frame, first: indices[0], second: indices[1], to: target, movement: .secondAtom)
            case "angle":
                guard let indices = r.indices, indices.count == 3, let target = r.value else { throw invalid("Select three atoms and an angle") }
                frame = try GeometryEditor.settingAngle(in: frame, first: indices[0], vertex: indices[1], third: indices[2], toDegrees: target)
            default: throw invalid("Unknown action: \(r.action)")
            }
            parsed.frames[i] = frame; invalidateScience(&parsed, frame: i)
            doc.undo.append(doc.current)
            if doc.undo.count > 100 { doc.undo.removeFirst() }
            doc.redo = []; doc.current = Snapshot(parsed: parsed)
        }
        documents[key] = doc
    }
    if let key = reply.document, let doc = documents[key] {
        reply.data = PortableDocument(document: doc.current.parsed, source: doc.source)
        reply.dirty = doc.current.revision != doc.savedRevision
        reply.canUndo = !doc.undo.isEmpty; reply.canRedo = !doc.redo.isEmpty
    }
    return reply
}
let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
while let line = readLine(strippingNewline: true) {
    var id = -1
    let reply: Reply
    do {
        let request = try JSONDecoder().decode(Request.self, from: Data(line.utf8)); id = request.id
        reply = try handle(request)
    } catch { reply = Reply(id: id, ok: false, error: error.localizedDescription) }
    do {
        let data = try encoder.encode(reply)
        FileHandle.standardOutput.write(data); FileHandle.standardOutput.write(Data([10]))
    } catch {
        FileHandle.standardError.write(Data("Cannot encode service response: \(error)\n".utf8))
        exit(1)
    }
}
