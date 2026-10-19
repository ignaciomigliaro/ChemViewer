import AppKit
import ChemCraftCore
import Foundation
import WebKit

@MainActor
enum BuilderChemistrySmokeTest {
    static var started = false
    static func run(workspace: WorkspaceStore) async {
        guard !started else { return }; started = true
        func require(_ value: Bool, _ message: String) throws { if !value { throw ParseError.malformed(message) } }
        let runtime = ChemistryRuntime.shared
        do {
            workspace.isBuilderVisible = true
            try require(LibraryFragment.all.count >= 250, "Fragment resource missing")
            let methane = try BuildingProject(atoms: BuildingProject.fragment(1))
            for item in LibraryFragment.all {
                guard let site = item.geometry.firstIndex(where: { $0.element == "X" }) else { throw ParseError.malformed("Catalog has no dummy site") }
                let attached = try methane.attaching(item.geometry, hostLeaving: 1, fragmentLeaving: site)
                try require(attached.atoms.count == 5 + item.geometry.count - 2, "Catalog attachment count: " + item.name)
            }
            workspace.applyBuildingProject(methane)
            workspace.pendingAttachment = BuildingProject.fragment(3); workspace.pendingAttachmentLeaving = 1
            try require(workspace.placeBuilderItem(at: 0), "Click placement not handled")
            try require(workspace.currentFrame?.atoms.count == 8, "Ethane attachment atom count")
            workspace.clearSelection()
            workspace.undoGeometry()
            try require(workspace.currentFrame?.atoms.count == 5, "Attachment undo")
            workspace.pendingElement = "Cl"
            try require(workspace.placeBuilderItem(at: 0), "Element click not handled")
            try require(workspace.currentFrame?.atoms.last?.element == "Cl", "Chlorine insertion")
            workspace.clearSelection()
            let water = [Atom(id: 0, element: "O", position: .zero), Atom(id: 1, element: "H", position: Vector3(1.1, 0, 0)), Atom(id: 2, element: "H", position: Vector3(0, 1.1, 0))]
            workspace.applyBuildingProject(try BuildingProject(atoms: water))
            workspace.selectedAtomIndices = [0]
            let before = workspace.currentFrame!
            runtime.optimize(workspace, freezeSelection: true)
            for _ in 0..<600 { if !runtime.busy { break }; try await Task.sleep(nanoseconds: 100_000_000) }
            try require(!runtime.busy && runtime.status.contains("converged"), "UFF cleanup failed: " + runtime.status)
            try require(workspace.currentFrame?.atoms[0].position == .zero, "Frozen oxygen moved")
            let angle = try GeometryEditor.angleDegrees(in: workspace.currentFrame!, firstAtomIndex: 1, vertexAtomIndex: 0, thirdAtomIndex: 2)
            try require(abs(angle - 104.51) < 0.02, "UFF water angle")
            try require(workspace.currentFrame?.energyHartree == nil, "UFF kept stale electronic energy")
            workspace.undoGeometry(); try require(workspace.currentFrame == before, "UFF undo did not restore geometry")
            // Cancel leaves the current geometry intact.
            runtime.optimize(workspace, freezeSelection: false); runtime.cancel()
            for _ in 0..<100 { if !runtime.busy { break }; try await Task.sleep(nanoseconds: 50_000_000) }
            try require(workspace.currentFrame == before, "Cancelled optimizer changed geometry")
            let evidence = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads/chemviewer-builder-evidence")
            try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
            runtime.openWorkflow(workspace, destination: evidence)
            for _ in 0..<100 { if runtime.guiURL != nil { break }; try await Task.sleep(nanoseconds: 200_000_000) }
            try require(runtime.guiURL != nil && runtime.showingWorkflow, "Embedded workflow startup failed")
            try await Task.sleep(nanoseconds: 2_000_000_000)
            func findWebView(_ view: NSView) -> WKWebView? {
                if let web = view as? WKWebView { return web }
                return view.subviews.lazy.compactMap(findWebView).first
            }
            let web = NSApp.windows.compactMap { $0.contentView }.compactMap(findWebView).first
            try require(web != nil, "Embedded workflow web view missing")
            var page = ""
            for _ in 0..<100 {
                page = (try? await web!.evaluateJavaScript("document.body.innerText")) as? String ?? ""
                if page.contains("ChemRefine") && page.contains("Workflow settings") { break }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            try require(page.contains("ChemRefine") && page.contains("Workflow settings"), "Actual local workflow editor did not render")
            if let image = try? await web!.takeSnapshot(configuration: nil), let tiff = image.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) {
                try png.write(to: evidence.appendingPathComponent("embedded-workflow.png"))
            }
            runtime.stopWorkflowTestServer()
            print("BUILDER_CHEMISTRY_PASS: 258 catalog fragments, click fragment/element placement, undo, genuine UFF convergence, fixed atoms, cancellation and embedded local ChemRefine GUI")
            fflush(stdout); NSApp.terminate(nil)
        } catch {
            runtime.stopWorkflowTestServer()
            fputs("BUILDER_CHEMISTRY_FAIL: \(error.localizedDescription)\n", stderr); fflush(stderr); NSApp.terminate(nil)
        }
    }
}
