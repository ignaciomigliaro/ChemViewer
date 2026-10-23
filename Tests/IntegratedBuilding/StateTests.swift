import Foundation
#if !CHEMVIEWER_STANDALONE
import XCTest
@testable import ChemCraftCore
#endif
struct StateChecks {
 static func main() throws {
  let atoms = IntegratedBuilding.builtInFragments.first { $0.name == "Methane" }!.atoms
  let p = IntegratedBuilding.EditableProject(atoms: atoms, groups: [[0,1,2],[3,4]], selection: [1,3], charge: -1, multiplicity: 2)
  let deleted = try p.deleting([1,4])
  precondition(deleted.groups == [[0,1],[2]] && deleted.selection == [2])
  var history = try IntegratedBuilding.ProjectHistory(p, limit: 2)
  try history.apply(deleted)
  precondition(history.undo() && history.current.atoms.count == 5 && history.current.selection == [1,3])
  precondition(history.redo() && history.current.atoms.count == 3)
  precondition(history.undo()); try history.apply(try p.appending([atoms[0]])); precondition(!history.canRedo)
  let roundTrip = try JSONDecoder().decode(IntegratedBuilding.EditableProject.self, from: JSONEncoder().encode(p))
  precondition(roundTrip.groups == p.groups && roundTrip.charge == -1 && roundTrip.multiplicity == 2)
  let text = try p.orcaGeometryText(); precondition(text.contains("* xyz -1 2") && text.contains("Angstrom"))
  let xyz = try IntegratedBuilding.parse(p.xyzText()); precondition(xyz.frames[0].count == p.atoms.count)
  let methyl = IntegratedBuilding.builtInFragments.first { $0.name == "Methyl" }!.atoms
  let attached = try p.attaching(IntegratedBuilding.attachFragment(host: atoms, hostLeaving: 1, fragment: methyl, fragmentLeaving: 1), hostLeaving: 1)
  precondition(attached.groups == [[0,1],[2,3],[4,5,6,7]])
  precondition(attached.selection == [4,5,6,7])
  for invalid in [IntegratedBuilding.EditableProject(atoms: atoms, selection: [99]), IntegratedBuilding.EditableProject(atoms: atoms, groups:[[0,0]]), IntegratedBuilding.EditableProject(atoms: atoms, multiplicity: 0), IntegratedBuilding.EditableProject(atoms: [IntegratedBuilding.Atom(symbol:"C",x:.nan,y:0,z:0)])] {
   do { try invalid.validate(); preconditionFailure("Invalid project accepted") } catch {}
  }
  do { _ = try IntegratedBuilding.EditableProject(atoms: methyl).xyzText(); preconditionFailure("Dummy export accepted") } catch {}
  print("Project tests passed: index remapping, selection/history, Codable validation, charge/multiplicity export.")
 }
}

#if CHEMVIEWER_STANDALONE
@main struct StateTests {
    static func main() throws { try StateChecks.main() }
}
#else
final class IntegratedStateTests: XCTestCase {
    func testMigratedStateAcceptance() throws { try StateChecks.main() }
}
#endif
