import AppKit
import ChemCraftCore

@MainActor
enum AtomEditingSmokeTest {
    static var started = false
    static func run(workspace: WorkspaceStore) async {
        guard !started else { return }; started = true
        func require(_ value: Bool, _ text: String) throws { if !value { throw ParseError.malformed(text) } }
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        func views() -> [NSView] { NSApp.windows.filter(\.isVisible).compactMap(\.contentView).flatMap(descendants) }
        func viewport() throws -> MolecularMTKView {
            guard let view = views().compactMap({ $0 as? MolecularMTKView }).first else { throw ParseError.noGeometry }
            return view
        }
        func click(_ view: MolecularMTKView, _ point: CGPoint, right: Bool = false) {
            let location = view.convert(point, to: nil)
            func event(_ type: NSEvent.EventType) -> NSEvent { NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: 0, windowNumber: view.window!.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)! }
            if right { view.rightMouseDown(with: event(.rightMouseDown)) }
            else { view.mouseDown(with: event(.leftMouseDown)); view.mouseUp(with: event(.leftMouseUp)) }
        }
        func choose(_ symbol: String) async throws {
            workspace.presentPeriodicTable()
            try await Task.sleep(nanoseconds: 600_000_000)
            let buttons = views().compactMap { $0 as? NSButton }.filter { $0.identifier?.rawValue.hasPrefix("periodic-element-") == true }
            try require(buttons.count == 118, "Periodic table must expose all 118 native element buttons, found \(buttons.count)")
            guard let button = buttons.first(where: { $0.identifier?.rawValue == "periodic-element-" + symbol }) else { throw ParseError.malformed("Missing element: " + symbol) }
            if symbol == "Fe", let content = button.window?.contentView, let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
                content.cacheDisplay(in: content.bounds, to: bitmap)
                if let png = bitmap.representation(using: .png, properties: [:]) {
                    try png.write(to: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads/chemviewer-periodic-table.png"))
                }
            }
            button.performClick(nil)
            try await Task.sleep(nanoseconds: 400_000_000)
            try require(workspace.pendingElement == symbol && !workspace.isPeriodicTablePresented, "Choosing element did not arm and dismiss the table")
        }
        do {
            workspace.newMolecule()
            workspace.atomPlacementMode = .replace
            try await choose("Fe")
            let view = try viewport()
            let point = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
            click(view, point)
            try await Task.sleep(nanoseconds: 200_000_000)
            let original = workspace.currentFrame!.atoms
            try require(original.count == 1 && original[0].element == "Fe", "Empty-space atom placement failed")
            try await choose("Ru")
            let camera = view.viewingRotation
            let pixel = view.projectedAtomPoint(0)!
            click(view, pixel)
            try await Task.sleep(nanoseconds: 200_000_000)
            try require(workspace.currentFrame!.atoms.count == 1 && workspace.currentFrame!.atoms[0].element == "Ru", "Replace mode added an atom instead of substituting")
            try require(workspace.currentFrame!.atoms[0].position == original[0].position && view.viewingRotation == camera, "Replacement moved geometry or camera")
            workspace.undoGeometry()
            try require(workspace.currentFrame!.atoms == original, "Element replacement undo failed")
            workspace.redoGeometry()
            workspace.atomPlacementMode = .bond
            try await choose("Cl")
            click(view, view.projectedAtomPoint(0)!)
            try await Task.sleep(nanoseconds: 200_000_000)
            let bonded = workspace.currentFrame!.atoms
            try require(bonded.count == 2 && bonded[0].element == "Ru" && bonded[1].element == "Cl", "Bond mode replaced the metal")
            try require((bonded[1].position - bonded[0].position).length > 1 && (bonded[1].position - bonded[0].position).length < 4, "Bonded atom has invalid distance")
            workspace.undoGeometry()
            try require(workspace.currentFrame!.atoms.count == 1, "Bond insertion undo failed")
            click(view, .zero, right: true)
            try require(workspace.pendingElement == nil, "Right-click did not finish the atom tool")
            // Exercise the actual Coordinates text field and Apply button, not just the store.
            workspace.document?.frames[0].energyHartree = -123.45
            workspace.activeTab = "Coord"
            try await Task.sleep(nanoseconds: 500_000_000)
            guard let field = views().compactMap({ $0 as? NSTextField }).first(where: { $0.placeholderString == "Element" }) else {
                throw ParseError.malformed("Editable element field missing in Coordinates")
            }
            func typeElement(_ value: String) throws {
                field.window?.makeFirstResponder(field)
                guard let editor = field.currentEditor() as? NSTextView else { throw ParseError.malformed("Element field could not receive keyboard focus") }
                editor.selectAll(nil); editor.insertText(value, replacementRange: editor.selectedRange())
                field.window?.makeFirstResponder(nil)
            }
            try typeElement("NoSuchElement")
            try await Task.sleep(nanoseconds: 150_000_000)
            func pressApply() throws {
                guard let window = field.window else { throw ParseError.noGeometry }
                window.makeKeyAndOrderFront(nil)
                for eventType: NSEvent.EventType in [.keyDown, .keyUp] {
                    let event = NSEvent.keyEvent(with: eventType, location: .zero, modifierFlags: [], timestamp: 0,
                        windowNumber: window.windowNumber, context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)!
                    window.sendEvent(event)
                }
            }
            try pressApply()
            try await Task.sleep(nanoseconds: 150_000_000)
            try require(workspace.currentFrame!.atoms[0].element == "Ru", "Invalid symbol was allowed to modify the structure")
            try typeElement(" pt ")
            try await Task.sleep(nanoseconds: 150_000_000)
            try pressApply()
            try await Task.sleep(nanoseconds: 300_000_000)
            try require(workspace.currentFrame!.atoms[0].element == "Pt", "Coordinates element was not applied/canonicalized")
            try require(workspace.currentFrame!.atoms[0].position == original[0].position, "Coordinate symbol edit changed position")
            try require(workspace.currentFrame!.energyHartree == nil, "Edited chemistry retained stale calculation energy")
            workspace.undoGeometry()
            try require(workspace.currentFrame!.atoms[0].element == "Ru" && workspace.currentFrame!.energyHartree == -123.45, "Coordinate element undo did not restore calculation energy")
            print("ATOM_EDITING_PASS: all 118 elements, native periodic-table selection, empty placement, replacement, bond insertion, camera preservation, right-click, actual Coordinates typing/validation/Apply and undo/energy invalidation")
            fflush(stdout); exit(0)
        } catch { fputs("ATOM_EDITING_FAIL: \(error.localizedDescription)\n", stderr); fflush(stderr); exit(1) }
    }
}
