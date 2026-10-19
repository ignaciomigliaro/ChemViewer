import AppKit
import ChemCraftCore
import Combine
import Foundation

@MainActor
final class WorkspaceStore: ObservableObject {
    @Published var isBuilderVisible = false
    @Published var pendingAttachment: [Atom]?
    var pendingAttachmentLeaving = 0
    @Published var pendingElement: String?
    @Published var buildingHint = ""
    func placeBuilderItem(at index: Int) -> Bool {
        guard pendingAttachment != nil || pendingElement != nil else { return false }
        do {
            let project = try buildingProject()
            if let element = pendingElement {
                applyBuildingProject(try project.attachingAtom(element, hostAtom: index))
            } else if let fragment = pendingAttachment {
                applyBuildingProject(try project.attachingAtAtom(fragment, hostAtom: index, fragmentLeaving: pendingAttachmentLeaving))
            }
            buildingHint = "Attached. Click another site to add again; right-click to finish."
        } catch { errorMessage = error.localizedDescription }
        return true
    }
    @Published var showExplorer = true
    @Published var showHydrogens = true
    @Published var atomCaption: AtomCaption = .none
    @Published var vibrationSpeed: Float = 0.48
    @Published var charge = 0
    @Published var multiplicity = 1
    @Published var calculationFacts: [CalculationFact] = []
    @Published var modesByFrame: [Int: [VibrationalMode]] = [:]
    private var groupsByFrame: [Int: [[Int]]] = [:]
    private var storedBondAxis: (Int, Int)?
    private struct Snapshot {
        let frame: MoleculeFrame
        let groups: [[Int]]
        let selection: [Int]
        let charge: Int
        let multiplicity: Int
        let edited: Bool
    }
    private var geometryRedoStacks: [Int: [Snapshot]] = [:]
    @Published var isDraggingEnabled = false {
        didSet {
            if isDraggingEnabled { pendingAttachment = nil; pendingElement = nil; buildingHint = ""; stopTrajectoryPlayback(); selectedModeIndex = nil; isVibrating = false }
            else { finishAtomDrag() }
        }
    }
    @Published var dragScope: DragScope = .atom
    @Published var dragAxis: DragAxis = .screen
    @Published var rotationPivot: RotationPivot = .center
    @Published var rotationStep: Float = 10
    @Published var translationStep: Float = 0.1
    private var fragmentBoundary: (Int, Int)?
    private var gestureBase: MoleculeFrame?
    private var gestureIndices: [Int] = []
    private var gestureFrame = 0
    @Published var isAnimationExportPresented = false
    @Published var isEnergyLandscapePresented = false
    @Published var sourceFocusLine: Int?
    @Published var xyzEnergyUnit: EnergyUnit? = nil { didSet { applyXYZEnergyUnit() } }
    @Published var showMeasurementOverlay = false
    @Published var geometryRevision = 0
    @Published var activeTab = "Image"
    @Published var renderingStyle: MolecularStyle = .paton
    @Published var sourceText = ""
    @Published var document: ParsedDocument?
    @Published var frameIndex = 0
    @Published var selectedModeIndex: Int?
    @Published var isVibrating = true
    @Published var vibrationAmplitude: Float = 0.6
    @Published var isImporterPresented = false
    @Published var isExporterPresented = false
    @Published var isSpectrumPresented = false
    @Published var isCoordinateEditorPresented = false
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showDisplacementVectors = false
    @Published var selectedAtomIndices: [Int] = []
    @Published var isPlayingTrajectory = false

    private var loadGeneration = 0
    private var editedFrames: Set<Int> = []
    private var geometryUndoStacks: [Int: [Snapshot]] = [:]
    private var trajectoryTask: Task<Void, Never>?

    func open(_ url: URL) {
        finishAtomDrag()
        fragmentBoundary = nil
        stopTrajectoryPlayback()
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        errorMessage = nil
        let hasSecurityScope = url.startAccessingSecurityScopedResource()
        Task {
            defer {
                if hasSecurityScope { url.stopAccessingSecurityScopedResource() }
                if generation == loadGeneration { isLoading = false }
            }
            do {
                let parsed = try await Task.detached(priority: .userInitiated) {
                    let fileSize = (try url.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0
                    guard fileSize <= 100_000_000 else { throw ParseError.malformed("Input exceeds 100 MB.") }
                    let data = try Data(contentsOf: url, options: [.mappedIfSafe])
                    guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { throw ParseError.malformed("Unsupported text encoding") }
                    if ["mvproject", "cvproject"].contains(url.pathExtension.lowercased()) {
                        guard data.count <= 10_000_000 else { throw ParseError.malformed("Project exceeds 10 MB.") }
                        let project = try JSONDecoder().decode(BuildingProject.self, from: data)
                        return (ParsedDocument(title: url.lastPathComponent, sourceFormat: "ChemViewer project", frames: [MoleculeFrame(id: 0, atoms: project.atoms, comment: "Editable project; calculation output and modes are not stored")]), "", Optional(project), [Int: [VibrationalMode]](), [CalculationFact]())
                    }
                    var result = try ParserRegistry.parse(text: text, fileName: url.lastPathComponent)
                    if let profile = result.nebProfile { result.nebProfile = ORCANEBParser.loadCompanionStructures(profile: profile, outputURL: url) }
                    guard result.frames.count <= 2000, result.frames.allSatisfy({ $0.atoms.count <= 10_000 }), result.frames.reduce(0, { $0 + $1.atoms.count }) <= 500_000 else { throw ParseError.malformed("Trajectory exceeds the supported frame/atom limits.") }
                    let analysis = try? BuildingProject.analysis(text)
                    return (result, text, Optional<BuildingProject>.none, analysis?.modes ?? [:], analysis?.facts ?? [])
                }.value
                guard generation == loadGeneration else { return }
                document = parsed.0
                modesByFrame = parsed.3; calculationFacts = parsed.4
                charge = Int(parsed.4.last(where: { $0.label == "Charge" })?.value ?? "0") ?? 0
                multiplicity = Int(parsed.4.last(where: { $0.label == "Multiplicity" })?.value ?? "1") ?? 1
                groupsByFrame = [:]; storedBondAxis = nil; geometryRedoStacks = [:]
                if let project = parsed.2 { charge = project.charge; multiplicity = project.multiplicity; groupsByFrame[0] = project.groups }
                geometryRevision += 1
                sourceText = parsed.1
                editedFrames.removeAll()
                frameIndex = parsed.0.vibrationalFrameIndex ?? max(0, parsed.0.frames.count - 1)
                geometryUndoStacks.removeAll()
                sourceFocusLine = nil
                applyXYZEnergyUnit()
                selectedAtomIndices = parsed.2?.selection ?? []
                selectedModeIndex = parsed.0.vibrationalModes.first(where: {
                    abs($0.frequencyCM1) > 1 && !$0.displacements.isEmpty
                })?.index
            } catch {
                if generation == loadGeneration { errorMessage = error.localizedDescription }
            }
        }
    }

    func presentAnimationExport() {
        if activeTab == "Image" || activeTab == "Image/Abs" { isAnimationExportPresented = true }
        else {
            activeTab = "Image"
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.isAnimationExportPresented = true }
        }
    }

    var selectedMode: VibrationalMode? {
        guard let selectedModeIndex, !editedFrames.contains(frameIndex) else { return nil }
        return availableModes.first { $0.index == selectedModeIndex }
    }

    var availableModes: [VibrationalMode] {
        guard let document else { return [] }
        if document.vibrationalFrameIndex == frameIndex { return document.vibrationalModes }
        return modesByFrame[frameIndex] ?? []
    }
    var currentGroups: [[Int]] { groupsByFrame[frameIndex] ?? [] }
    var canRedoGeometry: Bool { !(geometryRedoStacks[frameIndex]?.isEmpty ?? true) }
    private func snapshot(_ frame: MoleculeFrame? = nil) -> Snapshot? {
        guard let frame = frame ?? currentFrame else { return nil }
        return Snapshot(frame: frame, groups: currentGroups, selection: selectedAtomIndices, charge: charge, multiplicity: multiplicity, edited: editedFrames.contains(frameIndex))
    }
    private func checkpoint(_ frame: MoleculeFrame? = nil) {
        guard let snapshot = snapshot(frame) else { return }
        geometryUndoStacks[frameIndex, default: []].append(snapshot)
        if geometryUndoStacks[frameIndex, default: []].count > 100 { geometryUndoStacks[frameIndex]?.removeFirst() }
        geometryRedoStacks[frameIndex] = []
    }
    var currentFrame: MoleculeFrame? {
        guard let document, document.frames.indices.contains(frameIndex) else { return nil }
        return document.frames[frameIndex]
    }

    var canUndoGeometry: Bool { !(geometryUndoStacks[frameIndex]?.isEmpty ?? true) }
    func isFrameEdited(_ index: Int) -> Bool { editedFrames.contains(index) || (gestureBase != nil && gestureFrame == index && currentFrame?.atoms != gestureBase?.atoms) }

    private func applyXYZEnergyUnit() {
        guard var document, document.sourceFormat == "XYZ" else { return }
        for record in document.energyRecords {
            guard let index = record.frameIndex, document.frames.indices.contains(index), !editedFrames.contains(index) else { continue }
            document.frames[index].energyHartree = record.hartree(assuming: xyzEnergyUnit)
        }
        self.document = document
    }

    func showSource(line: Int) { sourceFocusLine = line; activeTab = "Source" }

    func stepFrame(_ step: Int) {
        guard let document, !document.frames.isEmpty else { return }
        let target = min(max(frameIndex + step, 0), document.frames.count - 1)
        if target != frameIndex { selectFrame(target) }
    }

    func applyDistance(_ value: Float, movement: GeometryEditor.DistanceMovement) {
        guard let frame = currentFrame, selectedAtomIndices.count == 2 else { return }
        do {
            let result = try GeometryEditor.settingDistance(in: frame, first: selectedAtomIndices[0], second: selectedAtomIndices[1], to: value, movement: movement)
            replaceCurrentAtoms(result.atoms)
        } catch { errorMessage = error.localizedDescription }
    }

    func applyAngle(_ value: Float, movement: GeometryEditor.AngleMovement = .thirdAtom) {
        guard let frame = currentFrame, selectedAtomIndices.count == 3 else { return }
        do {
            let result = try GeometryEditor.settingAngle(in: frame, first: selectedAtomIndices[0], vertex: selectedAtomIndices[1], third: selectedAtomIndices[2], toDegrees: value, movement: movement)
            replaceCurrentAtoms(result.atoms)
        } catch { errorMessage = error.localizedDescription }
    }

    var exportDocument: XYZExportDocument {
        guard let frame = currentFrame else { return XYZExportDocument(text: "0\n\n") }
        return XYZExportDocument(text: XYZWriter.string(frame: frame))
    }

    func selectFrame(_ index: Int) {
        finishAtomDrag()
        fragmentBoundary = nil
        guard let document, document.frames.indices.contains(index) else { return }
        stopTrajectoryPlayback()
        storedBondAxis = nil
        frameIndex = index
        selectedModeIndex = nil
        selectedAtomIndices.removeAll()
    }

    func selectMode(_ index: Int) {
        if index < 0 { selectedModeIndex = nil; return }
        isDraggingEnabled = false
        guard let document else { return }
        let frame = availableModes.contains(where: { $0.index == index }) ? frameIndex : (document.vibrationalFrameIndex ?? frameIndex)
        guard !editedFrames.contains(frame) else { errorMessage = "Undo the geometry edits or reopen the original file before animating its normal modes."; return }
        stopTrajectoryPlayback()
        frameIndex = frame
        selectedAtomIndices.removeAll()
        selectedModeIndex = index
    }

    func toggleTrajectoryPlayback() {
        if !isPlayingTrajectory { isDraggingEnabled = false }
        if isPlayingTrajectory {
            stopTrajectoryPlayback()
            return
        }
        guard let document, document.frames.count > 1 else { return }
        isPlayingTrajectory = true
        trajectoryTask = Task { [weak self] in
            while let self, self.isPlayingTrajectory, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard !Task.isCancelled,
                      let document = self.document,
                      document.frames.count > 1 else { break }
                self.frameIndex = (self.frameIndex + 1) % document.frames.count
                self.selectedAtomIndices.removeAll()
            }
        }
    }

    func stopTrajectoryPlayback() {
        isPlayingTrajectory = false
        trajectoryTask?.cancel()
        trajectoryTask = nil
    }

    func replaceCurrentAtoms(_ atoms: [Atom]) {
        finishAtomDrag()
        guard var document,
              document.frames.indices.contains(frameIndex),
              atoms.count == document.frames[frameIndex].atoms.count else { return }
        guard atoms.allSatisfy({ $0.position.x.isFinite && $0.position.y.isFinite && $0.position.z.isFinite }) else {
            errorMessage = "Coordinates must be finite numbers."; return
        }
        guard atoms != document.frames[frameIndex].atoms else { return }
        stopTrajectoryPlayback()
        checkpoint(document.frames[frameIndex])
        editedFrames.insert(frameIndex)
        selectedModeIndex = nil
        document.frames[frameIndex].atoms = atoms
        document.frames[frameIndex].energyHartree = nil
        document.frames[frameIndex].comment = "Edited geometry; energy not recalculated"
        self.document = document
        geometryRevision += 1
    }

    private func restore(_ snapshot: Snapshot) {
        guard var document, document.frames.indices.contains(frameIndex) else { return }
        document.frames[frameIndex] = snapshot.frame
        groupsByFrame[frameIndex] = snapshot.groups; selectedAtomIndices = snapshot.selection
        charge = snapshot.charge; multiplicity = snapshot.multiplicity
        if snapshot.edited { editedFrames.insert(frameIndex) } else { editedFrames.remove(frameIndex) }
        storedBondAxis = nil; selectedModeIndex = nil
        self.document = document; geometryRevision += 1
    }
    func undoGeometry() {
        finishAtomDrag()
        guard let current = snapshot(), let previous = geometryUndoStacks[frameIndex]?.popLast() else { return }
        geometryRedoStacks[frameIndex, default: []].append(current)
        restore(previous); applyXYZEnergyUnit()
    }
    func redoGeometry() {
        finishAtomDrag()
        guard let current = snapshot(), let next = geometryRedoStacks[frameIndex]?.popLast() else { return }
        geometryUndoStacks[frameIndex, default: []].append(current)
        restore(next)
    }

}


enum DragScope: String, CaseIterable { case atom = "Atom", fragment = "Fragment", molecule = "Molecule" }
enum DragAxis: String, CaseIterable { case screen = "Screen plane", x = "X", y = "Y", z = "Z" }
enum RotationPivot: String, CaseIterable { case center = "Group center", anchor = "Attachment / first atom", origin = "World origin" }

extension WorkspaceStore {
    func clearSelection() { finishAtomDrag(); selectedAtomIndices = []; fragmentBoundary = nil; pendingAttachment = nil; pendingElement = nil; buildingHint = "" }

    func chooseDragScope(_ scope: DragScope) {
        finishAtomDrag()
        let previous = selectedAtomIndices
        isDraggingEnabled = true
        dragScope = scope
        fragmentBoundary = nil
        guard let frame = currentFrame else { return }
        do {
            switch scope {
            case .atom: if let last = previous.last { selectedAtomIndices = [last] }
            case .molecule: selectedAtomIndices = Array(frame.atoms.indices)
            case .fragment:
                if previous.count == 2 {
                    selectedAtomIndices = try GeometryEditor.fragment(in: frame, fixed: previous[0], moving: previous[1])
                    fragmentBoundary = (previous[0], previous[1])
                } else if let seed = previous.last {
                    selectedAtomIndices = try GeometryEditor.connectedAtoms(in: frame, seed: seed)
                }
            }
        } catch { selectedAtomIndices = []; errorMessage = error.localizedDescription }
    }

    @discardableResult func selectManipulationSeed(_ seed: Int) -> Bool {
        guard let frame = currentFrame, frame.atoms.indices.contains(seed) else { return false }
        do {
            switch dragScope {
            case .atom: selectedAtomIndices = [seed]
            case .molecule: selectedAtomIndices = Array(frame.atoms.indices)
            case .fragment:
                let boundary = fragmentBoundary.map { Bond(id: 0, first: $0.0, second: $0.1) }
                selectedAtomIndices = try GeometryEditor.connectedAtoms(in: frame, seed: seed, excluding: boundary)
            }
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }

    var manipulationIndices: [Int] {
        guard let frame = currentFrame else { return [] }
        switch dragScope {
        case .molecule: return Array(frame.atoms.indices)
        case .fragment: return selectedAtomIndices.filter(frame.atoms.indices.contains)
        case .atom: return selectedAtomIndices.last.map { [$0] } ?? []
        }
    }

    func beginAtomDrag(_ seed: Int) -> Bool {
        finishAtomDrag()
        guard isDraggingEnabled, selectManipulationSeed(seed), let frame = currentFrame else { return false }
        selectedModeIndex = nil; isVibrating = false; stopTrajectoryPlayback()
        gestureBase = frame; gestureFrame = frameIndex; gestureIndices = manipulationIndices
        return !gestureIndices.isEmpty
    }

    func previewAtomDrag(_ displacement: Vector3) {
        guard let base = gestureBase, gestureFrame == frameIndex, var document,
              let moved = try? GeometryEditor.translating(in: base, atomIndices: gestureIndices, by: displacement),
              moved.atoms.allSatisfy({ [$0.position.x, $0.position.y, $0.position.z].allSatisfy(\.isFinite) }) else { return }
        var result = moved
        if result.atoms != base.atoms { result.energyHartree = nil; result.comment = "Edited geometry; energy not recalculated" }
        document.frames[frameIndex] = result
        self.document = document; geometryRevision += 1
    }

    func finishAtomDrag() {
        guard let base = gestureBase else { return }
        gestureBase = nil
        if gestureFrame == frameIndex, currentFrame?.atoms != base.atoms {
            checkpoint(base)
            editedFrames.insert(frameIndex)
            geometryRevision += 1
        }
        gestureIndices = []
    }

    func rotateManipulation(axis: Vector3, sign: Float) {
        finishAtomDrag()
        guard isDraggingEnabled, let frame = currentFrame, !manipulationIndices.isEmpty else { return }
        guard rotationStep.isFinite && rotationStep > 0 else { errorMessage = "Use a positive finite rotation step."; return }
        let indices = manipulationIndices
        let pivot: Vector3
        switch rotationPivot {
        case .origin: pivot = .zero
        case .center: pivot = indices.reduce(Vector3.zero) { $0 + frame.atoms[$1].position } * (1 / Float(indices.count))
        case .anchor:
            if let boundary = fragmentBoundary {
                let anchor = indices.contains(boundary.0) ? boundary.1 : boundary.0
                pivot = frame.atoms[anchor].position
            } else { pivot = frame.atoms[selectedAtomIndices.first ?? indices[0]].position }
        }
        do { replaceCurrentAtoms(try GeometryEditor.rotating(in: frame, atomIndices: indices, around: pivot, axis: axis, degrees: rotationStep * sign).atoms) }
        catch { errorMessage = error.localizedDescription }
    }

    func translateManipulation(axis: Vector3, sign: Float) {
        finishAtomDrag()
        guard isDraggingEnabled, let frame = currentFrame, !manipulationIndices.isEmpty else { return }
        guard translationStep.isFinite && translationStep > 0 else { errorMessage = "Use a positive finite translation step."; return }
        do { replaceCurrentAtoms(try GeometryEditor.translating(in: frame, atomIndices: manipulationIndices, by: axis * (translationStep * sign)).atoms) }
        catch { errorMessage = error.localizedDescription }
    }
}

extension WorkspaceStore {
    func newMolecule() {
        finishAtomDrag(); stopTrajectoryPlayback(); loadGeneration += 1; isLoading = false
        document = ParsedDocument(title: "Untitled molecule", sourceFormat: "Builder", frames: [MoleculeFrame(id: 0, atoms: [], comment: "Initial geometry approximation")])
        sourceText = ""; frameIndex = 0; selectedModeIndex = nil; selectedAtomIndices = []
        groupsByFrame = [:]; geometryUndoStacks = [:]; geometryRedoStacks = [:]; editedFrames = []
        calculationFacts = []; modesByFrame = [:]; storedBondAxis = nil; charge = 0; multiplicity = 1
        activeTab = "Image"; isBuilderVisible = true; geometryRevision += 1
    }
    func buildingProject() throws -> BuildingProject {
        try BuildingProject(atoms: currentFrame?.atoms ?? [], groups: currentGroups, selection: selectedAtomIndices, charge: charge, multiplicity: multiplicity)
    }
    func applyBuildingProject(_ project: BuildingProject) {
        finishAtomDrag(); stopTrajectoryPlayback()
        if document == nil { newMolecule() }
        guard var document, document.frames.indices.contains(frameIndex) else { return }
        checkpoint()
        document.frames[frameIndex].atoms = project.atoms
        document.frames[frameIndex].comment = "Edited initial geometry; energy not recalculated"
        document.frames[frameIndex].energyHartree = nil
        groupsByFrame[frameIndex] = project.groups; selectedAtomIndices = project.selection
        charge = project.charge; multiplicity = project.multiplicity
        storedBondAxis = nil; selectedModeIndex = nil; isVibrating = false; editedFrames.insert(frameIndex)
        self.document = document; geometryRevision += 1
    }
    func addBuildingFragment(_ atoms: [Atom]) {
        do {
            let offset = (currentFrame?.atoms.map { $0.position.x }.max() ?? -3) + 3
            let added = atoms.map { Atom(id: $0.id, element: $0.element, position: $0.position + Vector3(offset, 0, 0)) }
            applyBuildingProject(try buildingProject().appending(added))
        } catch { errorMessage = error.localizedDescription }
    }
    func attachBuildingFragment(_ atoms: [Atom], leaving: Int) {
        guard selectedAtomIndices.count == 1, let host = selectedAtomIndices.first else { errorMessage = "Select one host hydrogen or X dummy atom."; return }
        do { applyBuildingProject(try buildingProject().attachingAtAtom(atoms, hostAtom: host, fragmentLeaving: leaving)) }
        catch { errorMessage = error.localizedDescription }
    }
    func duplicateSelectedAtoms() {
        guard let frame = currentFrame, !selectedAtomIndices.isEmpty else { return }
        addBuildingFragment(selectedAtomIndices.filter(frame.atoms.indices.contains).map { frame.atoms[$0] })
    }
    func deleteSelectedAtoms() {
        guard !selectedAtomIndices.isEmpty else { return }
        do { applyBuildingProject(try buildingProject().deleting(selectedAtomIndices)) } catch { errorMessage = error.localizedDescription }
    }
    func editElement(_ symbol: String, insert: Bool) {
        guard BuildingProject.elements.contains(symbol) else { errorMessage = "Enter a valid element symbol or X for a dummy site."; return }
        if insert { addBuildingFragment([Atom(id: 0, element: symbol, position: .zero)]); return }
        guard let frame = currentFrame else { return }
        var atoms = frame.atoms
        for index in selectedAtomIndices where atoms.indices.contains(index) { atoms[index].element = symbol }
        replaceCurrentAtoms(atoms)
    }
    func selectBuilderIndices(_ text: String) {
        do { selectedAtomIndices = try BuildingProject.selection(text, atomCount: currentFrame?.atoms.count ?? 0) }
        catch { errorMessage = error.localizedDescription }
    }
    func selectImportedGroup() {
        guard let first = selectedAtomIndices.first, let group = currentGroups.last(where: { $0.contains(first) }) else { return }
        selectedAtomIndices = group
    }
    func selectConnectedGroup() {
        guard let frame = currentFrame, let seed = selectedAtomIndices.first else { return }
        do { selectedAtomIndices = try GeometryEditor.connectedAtoms(in: frame, seed: seed) } catch { errorMessage = error.localizedDescription }
    }
    func setBuildingBondAxis() {
        guard let frame = currentFrame, selectedAtomIndices.count == 2 else { errorMessage = "Select two bonded atoms first."; return }
        let a = selectedAtomIndices[0], b = selectedAtomIndices[1]
        guard BondBuilder.inferBonds(atoms: frame.atoms).contains(where: { Set([$0.first, $0.second]) == Set([a, b]) }) else { errorMessage = "Choose a bonded pair for the rotation axis."; return }
        storedBondAxis = (a, b)
    }
    func transformBuildingSelection(axis: String, distance: Float, degrees: Float) {
        guard let frame = currentFrame, !selectedAtomIndices.isEmpty else { return }
        do {
            var direction = axis == "X" ? Vector3(1, 0, 0) : axis == "Y" ? Vector3(0, 1, 0) : Vector3(0, 0, 1)
            var pivot = selectedAtomIndices.reduce(Vector3.zero) { $0 + frame.atoms[$1].position } * (1 / Float(selectedAtomIndices.count))
            if rotationPivot == .origin { pivot = .zero }
            if rotationPivot == .anchor { pivot = frame.atoms[selectedAtomIndices[0]].position }
            if axis == "Bond" {
                guard let pair = storedBondAxis, frame.atoms.indices.contains(pair.0), frame.atoms.indices.contains(pair.1) else { errorMessage = "Set the bond axis first, then select atoms to move or rotate."; return }
                pivot = frame.atoms[pair.0].position
                direction = frame.atoms[pair.1].position - pivot
            }
            guard direction.length > 1e-6 else { return }
            let result = try buildingProject().transformed(selection: selectedAtomIndices, translation: direction * (distance / direction.length), axis: direction, degrees: degrees, pivot: pivot)
            // Coordinate transforms retain a stored bond axis for repeated steps.
            let savedAxis = storedBondAxis; applyBuildingProject(result); storedBondAxis = savedAxis
        } catch { errorMessage = error.localizedDescription }
    }
    func saveBuildingProject() {
        do {
            let project = try buildingProject()
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(project)
            let panel = NSSavePanel(); panel.nameFieldStringValue = "molecule.cvproject"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try data.write(to: url, options: .atomic)
        } catch { errorMessage = error.localizedDescription }
    }
    func requestXYZExport() {
        do { _ = try buildingProject().xyzText(); isExporterPresented = true }
        catch { errorMessage = error.localizedDescription }
    }
    func exportORCAGeometry() {
        do {
            let text = try buildingProject().orcaGeometryText()
            let panel = NSSavePanel(); panel.nameFieldStringValue = "geometry.inp"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch { errorMessage = error.localizedDescription }
    }
}
