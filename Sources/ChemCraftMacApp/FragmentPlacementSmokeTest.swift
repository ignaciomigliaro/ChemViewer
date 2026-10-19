import AppKit
import ChemCraftCore
import Foundation
import WebKit

@MainActor
enum FragmentPlacementSmokeTest {
    static var started = false
    static func run(workspace: WorkspaceStore) async {
        guard !started else { return }; started = true
        func require(_ condition: Bool, _ text: String) throws { if !condition { throw ParseError.malformed(text) } }
        func find<T: NSView>(_ type: T.Type, _ view: NSView) -> T? {
            if let result = view as? T { return result }
            return view.subviews.lazy.compactMap { find(type, $0) }.first
        }
        func viewport() throws -> MolecularMTKView {
            guard let view = NSApp.windows.filter({ $0.isVisible && $0.sheetParent == nil }).compactMap(\.contentView).compactMap({ find(MolecularMTKView.self, $0) }).first else { throw ParseError.noGeometry }
            return view
        }
        func click(_ view: MolecularMTKView, at point: CGPoint) {
            let location = view.convert(point, to: nil)
            func event(_ type: NSEvent.EventType) -> NSEvent { NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: 0, windowNumber: view.window!.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)! }
            view.mouseDown(with: event(.leftMouseDown)); view.mouseUp(with: event(.leftMouseUp))
        }
        let runtime = ChemistryRuntime.shared
        do {
            let evidence = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads/chemviewer-gallery-evidence")
            try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
            workspace.newMolecule(); workspace.presentFragmentLibrary()
            try await Task.sleep(nanoseconds: 800_000_000)
            try require(NSApp.windows.contains { $0.isVisible && $0.sheetParent != nil }, "Fragment browser did not pop up")
            for item in [LibraryFragment.all[0], LibraryFragment.all.last!] {
                guard let image = FragmentThumbnails.image(for: item), let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let data = bitmap.representation(using: .png, properties: [:]) else { throw ParseError.malformed("Metal preview missing") }
                try data.write(to: evidence.appendingPathComponent(item.category == "Metal centers" ? "metal-preview.png" : "organic-preview.png"))
            }
            if let content = NSApp.windows.first(where: { $0.isVisible && $0.sheetParent != nil })?.contentView, let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
                content.cacheDisplay(in: content.bounds, to: bitmap)
                if let png = bitmap.representation(using: .png, properties: [:]) { try png.write(to: evidence.appendingPathComponent("fragment-browser.png")) }
            }
            let item = LibraryFragment.all[0]
            workspace.armFragment(item); workspace.isFragmentLibraryPresented = false
            try await Task.sleep(nanoseconds: 300_000_000)
            let view = try viewport()
            let point = CGPoint(x: view.bounds.width * 0.65, y: view.bounds.height * 0.55)
            let expected = view.placementPosition(at: point)
            click(view, at: point)
            try await Task.sleep(nanoseconds: 200_000_000)
            let atoms = workspace.currentFrame!.atoms
            try require(atoms.count == item.geometry.count, "First empty click did not place a fragment")
            let centroid = atoms.reduce(Vector3.zero) { $0 + $1.position } * (1 / Float(atoms.count))
            try require((centroid - expected).length < 1e-4, "Fragment placed at wrong world position")
            let projected = atoms.indices.compactMap { view.projectedAtomPoint($0) }
            let cx = projected.reduce(CGFloat(0)) { $0 + $1.x } / CGFloat(projected.count)
            let cy = projected.reduce(CGFloat(0)) { $0 + $1.y } / CGFloat(projected.count)
            try require(hypot(cx - point.x, cy - point.y) < 2, "Placement reset camera or moved away from click")
            NotificationCenter.default.post(name: .init("ChemViewerViewportAction"), object: "left")
            NotificationCenter.default.post(name: .init("ChemViewerViewportAction"), object: "in")
            let secondPoint = CGPoint(x: view.bounds.width * 0.25, y: view.bounds.height * 0.4)
            let secondPosition = view.placementPosition(at: secondPoint)
            click(view, at: secondPoint)
            try await Task.sleep(nanoseconds: 150_000_000)
            let added = Array(workspace.currentFrame!.atoms.suffix(atoms.count))
            try require(workspace.currentFrame!.atoms.count == atoms.count * 2, "Second empty click failed")
            let secondCenter = added.reduce(Vector3.zero) { $0 + $1.position } * (1 / Float(added.count))
            try require((secondCenter - secondPosition).length < 1e-4, "Rotated/zoomed placement incorrect")
            NotificationCenter.default.post(name: .init("ChemViewerViewportAction"), object: "reset")
            let fitted = workspace.currentFrame!.atoms.indices.compactMap { view.projectedAtomPoint($0) }
            let fittedX = fitted.reduce(CGFloat(0)) { $0 + $1.x } / CGFloat(fitted.count)
            let fittedY = fitted.reduce(CGFloat(0)) { $0 + $1.y } / CGFloat(fitted.count)
            try require(abs(fittedX - view.bounds.midX) < 2 && abs(fittedY - view.bounds.midY) < 2, "Fit and Center did not refit freely placed fragments")
            workspace.clearSelection(); let count = workspace.currentFrame!.atoms.count
            click(view, at: CGPoint(x: 10, y: 10))
            try require(workspace.currentFrame!.atoms.count == count, "Inactive placement added a fragment")
            workspace.undoGeometry(); try require(workspace.currentFrame!.atoms.count == atoms.count, "Placement undo failed")
            workspace.applyBuildingProject(try BuildingProject(atoms: BuildingProject.fragment(0)))
            workspace.activeTab = "ChemRefine"; runtime.openWorkflow(workspace, destination: evidence)
            for _ in 0..<100 { if runtime.guiURL != nil { break }; try await Task.sleep(nanoseconds: 200_000_000) }
            try await Task.sleep(nanoseconds: 600_000_000)
            try require(workspace.activeTab == "ChemRefine", "ChemRefine did not use dedicated tab")
            try require(!NSApp.windows.contains { $0.isVisible && $0.sheetParent != nil }, "ChemRefine still opened a modal sheet")
            guard let web = NSApp.windows.compactMap(\.contentView).compactMap({ find(WKWebView.self, $0) }).first else { throw ParseError.malformed("ChemRefine tab has no web view") }
            var page = ""
            for _ in 0..<100 {
                page = (try? await web.evaluateJavaScript("document.body.innerText")) as? String ?? ""
                if page.contains("Workflow settings") { break }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            try require(page.contains("Workflow settings"), "ChemRefine tab did not render its local editor")
            _ = try await web.evaluateJavaScript("window.chemViewerStateProbe = 'preserved'")
            workspace.activeTab = "Image"; try await Task.sleep(nanoseconds: 150_000_000)
            workspace.activeTab = "ChemRefine"; try await Task.sleep(nanoseconds: 150_000_000)
            let returned = NSApp.windows.compactMap(\.contentView).compactMap({ find(WKWebView.self, $0) }).first
            try require(returned === web, "Switching tabs recreated the workflow editor")
            let state = try await web.evaluateJavaScript("window.chemViewerStateProbe") as? String
            try require(state == "preserved", "Switching tabs lost the workflow editor state")
            if let snapshot = try? await web.takeSnapshot(configuration: nil), let tiff = snapshot.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let data = bitmap.representation(using: .png, properties: [:]) { try data.write(to: evidence.appendingPathComponent("chemrefine-tab.png")) }
            runtime.stopWorkflowTestServer()
            print("FRAGMENT_PLACEMENT_PASS: popup gallery, Metal previews, empty-molecule mouse placement, repeated/rotated/zoomed placement, preserved framing, undo, inactive-click safety and persistent dedicated live ChemRefine tab")
            fflush(stdout); exit(0)
        } catch { runtime.stopWorkflowTestServer(); fputs("FRAGMENT_PLACEMENT_FAIL: \(error.localizedDescription)\n", stderr); fflush(stderr); exit(1) }
    }
}
