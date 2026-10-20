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
            let ligand = LibraryFragment.all.first { $0.name == "Triphenylphosphine donor" }!
            workspace.armFragment(ligand); workspace.isFragmentLibraryPresented = false
            workspace.isBuilderVisible = true; try await Task.sleep(nanoseconds: 200_000_000)
            try require(workspace.pendingAttachment?[workspace.pendingAttachmentLeaving].element == "X", "Opening edit controls replaced the dummy attachment site with a ligand hydrogen")
            workspace.isBuilderVisible = false
            let item = LibraryFragment.all[0]
            workspace.armFragment(item)
            try await Task.sleep(nanoseconds: 300_000_000)
            let view = try viewport()
            let point = CGPoint(x: view.bounds.width * 0.65, y: view.bounds.height * 0.55)
            let expected = view.placementPosition(at: point)
            try require(expected.length < 25, "Empty-canvas placement used the clipping plane: distance \(expected.length) Å from origin")
            click(view, at: point)
            try await Task.sleep(nanoseconds: 200_000_000)
            let atoms = workspace.currentFrame!.atoms
            try require(atoms.count == item.geometry.count, "First empty click did not place a fragment")
            let centroid = atoms.reduce(Vector3.zero) { $0 + $1.position } * (1 / Float(atoms.count))
            try require((centroid - expected).length < 1e-4, "Fragment placed at wrong world position")
            let projected = atoms.indices.compactMap { view.projectedAtomPoint($0) }
            let cx = projected.reduce(CGFloat(0)) { $0 + $1.x } / CGFloat(projected.count)
            let cy = projected.reduce(CGFloat(0)) { $0 + $1.y } / CGFloat(projected.count)
            try require(hypot(cx - point.x, cy - point.y) < 2, "Placement moved: expected \(point), projected \(cx),\(cy), bounds \(view.bounds.size), drawable \(view.drawableSize)")
            let cameraEvidence = evidence.appendingPathComponent("camera-0.9.2")
            try FileManager.default.createDirectory(at: cameraEvidence, withIntermediateDirectories: true)
            func visiblePixels(_ name: String) async throws -> Int {
                let path = cameraEvidence.appendingPathComponent(name + ".png")
                try? FileManager.default.removeItem(at: path)
                view.capture(to: path)
                for _ in 0..<100 {
                    if let data = try? Data(contentsOf: path), let bitmap = NSBitmapImageRep(data: data), let pixels = bitmap.bitmapData, bitmap.bitsPerSample == 8, bitmap.samplesPerPixel >= 3 {
                        var count = 0
                        for y in 0..<bitmap.pixelsHigh {
                            for x in 0..<bitmap.pixelsWide {
                                let offset = y * bitmap.bytesPerRow + x * bitmap.samplesPerPixel
                                if pixels[offset] < 235 || pixels[offset + 1] < 235 || pixels[offset + 2] < 235 { count += 1 }
                            }
                        }
                        print("CAMERA_VISIBILITY \(name): \(count) nonwhite pixels")
                        return count
                    }
                    try await Task.sleep(nanoseconds: 30_000_000)
                }
                throw ParseError.malformed("Viewport capture timed out: " + name)
            }
            try require(try await visiblePixels("initial-placement") > 100, "Placed molecule did not actually render")
            let unchanged = workspace.currentFrame!
            let anchored = view.placementPosition(at: point)
            for step in 1...4 {
                view.zoomBy(factor: 0.7, at: point)
                try require(try await visiblePixels("zoom-out-\(step)") > 10, "Molecule disappeared while zooming out")
                try require((view.placementPosition(at: point) - anchored).length < 1e-4, "Pointer anchor drifted during zoom")
                try require(workspace.currentFrame == unchanged, "Zoom changed molecular coordinates")
            }
            for _ in 0..<4 { view.zoomBy(factor: 1 / 0.7, at: point) }
            try require(try await visiblePixels("zoom-restored") > 100, "Molecule disappeared after zooming back in")
            func span() -> CGFloat {
                let points = atoms.indices.compactMap { view.projectedAtomPoint($0) }
                return (points.map(\.x).max()! - points.map(\.x).min()!) + (points.map(\.y).max()! - points.map(\.y).min()!)
            }
            for step in 1...2 {
                view.zoomBy(factor: 1.25, at: point)
                try require(try await visiblePixels("zoom-in-\(step)") > 100, "Zoom-in clipped away the structure")
            }
            view.zoomBy(factor: 1 / (1.25 * 1.25), at: point)
            let beforeScroll = span()
            view.applyScrollZoom(delta: -10000, precise: true, at: point)
            try require(span() / beforeScroll > 0.8, "One large trackpad event shrank the structure abruptly")
            view.zoomBy(factor: exp(0.18), at: point)
            let orbitBefore = atoms.indices.compactMap { view.projectedAtomPoint($0) }
            let orbitX = orbitBefore.reduce(CGFloat(0)) { $0 + $1.x } / CGFloat(atoms.count)
            let orbitY = orbitBefore.reduce(CGFloat(0)) { $0 + $1.y } / CGFloat(atoms.count)
            let start = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
            func orbitEvent(_ type: NSEvent.EventType, _ p: CGPoint) -> NSEvent {
                NSEvent.mouseEvent(with: type, location: view.convert(p, to: nil), modifierFlags: [], timestamp: 0, windowNumber: view.window!.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
            }
            view.mouseDown(with: orbitEvent(.leftMouseDown, start))
            let finish = CGPoint(x: start.x + 40, y: start.y + 20)
            view.mouseDragged(with: orbitEvent(.leftMouseDragged, finish)); view.mouseUp(with: orbitEvent(.leftMouseUp, finish))
            let orbitAfter = atoms.indices.compactMap { view.projectedAtomPoint($0) }
            let afterX = orbitAfter.reduce(CGFloat(0)) { $0 + $1.x } / CGFloat(atoms.count)
            let afterY = orbitAfter.reduce(CGFloat(0)) { $0 + $1.y } / CGFloat(atoms.count)
            try require(hypot(afterX - orbitX, afterY - orbitY) < 2, "Rotating swung the off-center molecule around the canvas origin")
            try require(try await visiblePixels("after-orbit") > 100, "Orbit clipped away the structure")
            try require(workspace.currentFrame == unchanged, "Orbit modified the molecule")
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
            print("FRAGMENT_PLACEMENT_PASS: popup gallery, Metal previews, empty-molecule mouse placement, repeated/rotated/zoomed placement, preserved framing, undo, inactive-click safety and persistent dedicated live ChemRefine tab; camera-plane depth, rendered zoom visibility, bounded trackpad zoom and stable orbit pivot")
            fflush(stdout); exit(0)
        } catch { runtime.stopWorkflowTestServer(); fputs("FRAGMENT_PLACEMENT_FAIL: \(error.localizedDescription)\n", stderr); fflush(stderr); exit(1) }
    }
}
