import ChemCraftCore
import Combine
import Foundation

@MainActor
final class WorkspaceStore: ObservableObject {
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
    @Published var showDisplacementVectors = true
    @Published var selectedAtomIndices: [Int] = []
    @Published var isPlayingTrajectory = false

    private var geometryUndoStack: [MoleculeFrame] = []
    private var trajectoryTask: Task<Void, Never>?

    func open(_ url: URL) {
        stopTrajectoryPlayback()
        isLoading = true
        errorMessage = nil
        let hasSecurityScope = url.startAccessingSecurityScopedResource()
        Task {
            defer {
                if hasSecurityScope { url.stopAccessingSecurityScopedResource() }
                isLoading = false
            }
            do {
                let parsed = try await Task.detached(priority: .userInitiated) {
                    try ParserRegistry.parse(url: url)
                }.value
                document = parsed
                frameIndex = max(0, parsed.frames.count - 1)
                geometryUndoStack.removeAll()
                selectedAtomIndices.removeAll()
                selectedModeIndex = parsed.vibrationalModes.first(where: {
                    abs($0.frequencyCM1) > 1 && !$0.displacements.isEmpty
                })?.index
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    var selectedMode: VibrationalMode? {
        guard let document, let selectedModeIndex else { return nil }
        return document.vibrationalModes.first { $0.index == selectedModeIndex }
    }

    var currentFrame: MoleculeFrame? {
        guard let document, document.frames.indices.contains(frameIndex) else { return nil }
        return document.frames[frameIndex]
    }

    var canUndoGeometry: Bool { !geometryUndoStack.isEmpty }

    var exportDocument: XYZExportDocument {
        guard let frame = currentFrame else { return XYZExportDocument(text: "0\n\n") }
        return XYZExportDocument(text: XYZWriter.string(frame: frame))
    }

    func selectFrame(_ index: Int) {
        guard let document, document.frames.indices.contains(index) else { return }
        frameIndex = index
        selectedAtomIndices.removeAll()
    }

    func toggleTrajectoryPlayback() {
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
        guard var document,
              document.frames.indices.contains(frameIndex),
              atoms.count == document.frames[frameIndex].atoms.count else { return }
        geometryUndoStack.append(document.frames[frameIndex])
        document.frames[frameIndex].atoms = atoms
        self.document = document
    }

    func undoGeometry() {
        guard var document,
              document.frames.indices.contains(frameIndex),
              let previous = geometryUndoStack.popLast() else { return }
        document.frames[frameIndex] = previous
        self.document = document
    }
}
