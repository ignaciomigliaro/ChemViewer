import ChemCraftCore
import Foundation

struct LibraryFragment: Decodable, Identifiable {
    struct Coordinate: Decodable { let element: String; let x: Float; let y: Float; let z: Float }
    let name: String
    let category: String
    let atoms: [Coordinate]
    var id: String { category + "/" + name }
    var geometry: [Atom] { atoms.enumerated().map { Atom(id: $0.offset, element: $0.element.element, position: Vector3($0.element.x, $0.element.y, $0.element.z)) } }
    static let all: [LibraryFragment] = {
        guard let url = ChemistryResources.bundle.url(forResource: "Fragments", withExtension: "json"),
              let data = try? Data(contentsOf: url), let items = try? JSONDecoder().decode([LibraryFragment].self, from: data) else { return [] }
        return items
    }()
}

enum ChemistryResources {
    static var bundle: Bundle {
        Bundle.main.resourceURL.flatMap { Bundle(url: $0.appendingPathComponent("ChemViewer_ChemViewerApp.bundle")) } ?? .module
    }
}
