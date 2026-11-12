import AppKit
import ChemCraftCore

@MainActor enum MetalCleanupSmokeTest {
    static var started = false
    static func run(workspace: WorkspaceStore) async {
        guard !started else { return }; started = true
        let runtime = ChemistryRuntime.shared
        func require(_ ok: Bool, _ message: String) throws {
            if !ok { throw ParseError.malformed(message) }
        }
        func wait() async throws {
            for _ in 0..<600 {
                if !runtime.busy { return }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            throw ParseError.malformed("Cleanup timed out")
        }
        do {
            workspace.isBuilderVisible = true
            runtime.cleanupMethod = .auto
            let copper = [Atom(id: 0, element: "Cu", position: .zero),
                          Atom(id: 1, element: "H", position: Vector3(2.1, 0, 0))]
            workspace.applyBuildingProject(try BuildingProject(atoms: copper, charge: 0, multiplicity: 1))
            workspace.toggleBond(0, 1)
            workspace.selectedAtomIndices = [0]
            let original = workspace.currentFrame!
            runtime.optimize(workspace, freezeSelection: true)
            try await wait()
            try require(runtime.status.contains("GFN2-xTB converged") && runtime.status.contains("eV"), "Copper cleanup: " + runtime.status + " " + (workspace.errorMessage ?? ""))
            let optimized = workspace.currentFrame!
            try require(optimized.atoms[0] == original.atoms[0], "Fixed Cu moved")
            try require(abs(optimized.atoms[1].position.x - 1.423) < 0.015, "Independent CuH bond-length oracle mismatch")
            try require(optimized.bonds == original.bonds && workspace.selectedAtomIndices == [0], "Cleanup lost bonds or selection")
            try require(optimized.energyHartree == nil, "Cleanup retained stale electronic energy")
            workspace.undoGeometry()
            try require(workspace.currentFrame == original, "Cleanup undo mismatch")
            workspace.multiplicity = 2
            runtime.optimize(workspace, freezeSelection: true); try await wait()
            try require(workspace.currentFrame == original && workspace.errorMessage?.contains("electron count") == true, "Invalid spin changed geometry or lacked actionable error")
            workspace.errorMessage = nil; workspace.multiplicity = 1
            runtime.optimize(workspace, freezeSelection: true); runtime.cancel(); try await wait()
            try require(workspace.currentFrame == original, "Cancelled metal cleanup changed geometry")
            let water = [Atom(id: 0, element: "O", position: .zero), Atom(id: 1, element: "H", position: Vector3(1.1, 0, 0)), Atom(id: 2, element: "H", position: Vector3(0, 1.1, 0))]
            workspace.applyBuildingProject(try BuildingProject(atoms: water))
            workspace.selectedAtomIndices = [0]
            runtime.optimize(workspace, freezeSelection: true); try await wait()
            try require(runtime.status.contains("UFF converged") && runtime.status.contains("kcal/mol"), "Organic UFF regression: " + runtime.status)
            let angle = try GeometryEditor.angleDegrees(in: workspace.currentFrame!, firstAtomIndex: 1, vertexAtomIndex: 0, thirdAtomIndex: 2)
            try require(abs(angle - 104.51) < 0.02, "UFF water angle changed")
            print("METAL_CLEANUP_PASS: genuine local Cu GFN2-xTB, fixed atom, independent bond oracle, units, topology/selection preservation, undo, invalid spin refusal, cancellation and organic UFF regression")
            exit(0)
        } catch {
            runtime.cancel()
            fputs("METAL_CLEANUP_FAIL: \(error)\n", stderr); exit(1)
        }
    }
}
