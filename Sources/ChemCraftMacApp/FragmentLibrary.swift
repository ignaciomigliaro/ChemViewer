import ChemCraftCore
import Foundation

struct LibraryFragment: Decodable, Identifiable {
    struct Coordinate: Decodable { let element: String; let x: Float; let y: Float; let z: Float }
    let name: String
    let category: String
    let atoms: [Coordinate]
    var id: String { category + "/" + name }
    var geometry: [Atom] { atoms.enumerated().map { Atom(id: $0.offset, element: $0.element.element, position: Vector3($0.element.x, $0.element.y, $0.element.z)) } }
    static var catalog: [LibraryFragment] {
        let molecules = BuildingProject.fragmentNames.enumerated().map { index, name in
            LibraryFragment(name: name, category: "Molecules", atoms: BuildingProject.fragment(index).map { Coordinate(element: $0.element, x: $0.position.x, y: $0.position.y, z: $0.position.z) })
        }
        return molecules + all
    }
    static let all: [LibraryFragment] = {
        guard let url = ChemistryResources.bundle.url(forResource: "Fragments", withExtension: "json"),
              let data = try? Data(contentsOf: url), let items = try? JSONDecoder().decode([LibraryFragment].self, from: data) else { return [] }
        return items
    }()
}

enum ChemistryResources {
    static var bundle: Bundle {
        if let packaged = Bundle.main.resourceURL.flatMap({ Bundle(url: $0.appendingPathComponent("ChemViewer_ChemViewerApp.bundle")) }) {
            return packaged
        }
        // A shipped app must never use SwiftPM's absolute build-machine path.
        // Returning main lets callers report missing resources instead of trapping
        // in the generated Bundle.module accessor. That accessor is for swift run.
        if Bundle.main.bundleURL.pathExtension == "app" { return Bundle.main }
        return .module
    }

    static func validatePackaged() throws {
        guard Bundle.main.bundleURL.pathExtension == "app",
              let resourceRoot = Bundle.main.resourceURL?.resolvingSymlinksInPath().standardizedFileURL.path,
              bundle.bundleURL.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(resourceRoot + "/") else {
            throw ParseError.malformed("Resources must resolve inside the packaged app, without a development-build fallback.")
        }
        let names = ["Fragments.json", "MoleculeShaders.metal", "workflow_dashboard.js",
                     "remote_agent.py", "remote_bridge.py", "chemistry_bridge.py", "drawing_bridge.py",
                     "bostmc_catalog.py", "energy_landscape.py", "workflow_bridge.py"]
        for name in names {
            let file = bundle.bundleURL.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: file), !data.isEmpty else {
                throw ParseError.malformed("Missing packaged resource: \(name)")
            }
        }
        let fragments = try Data(contentsOf: bundle.bundleURL.appendingPathComponent("Fragments.json"))
        guard !(try JSONDecoder().decode([LibraryFragment].self, from: fragments)).isEmpty else {
            throw ParseError.malformed("Packaged fragment catalog is empty.")
        }
    }
}
