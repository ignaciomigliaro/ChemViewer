import Foundation
@main struct StateTests {
 static func main() throws {
  let atoms = IntegratedBuilding.builtInFragments.first { $0.name == "Methane" }!.atoms
  let p = IntegratedBuilding.EditableProject(atoms: atoms, groups: [[0,1,2],[3,4]], selection: [1,3], charge: -1, multiplicity: 2)
  let deleted = try p.deleting([1,4])
  assert(deleted.groups == [[0,1],[2]] && deleted.selection == [2])
  var history = try IntegratedBuilding.ProjectHistory(p, limit: 2)
  try history.apply(deleted)
  assert(history.undo() && history.current.atoms.count == 5 && history.current.selection == [1,3])
  assert(history.redo() && history.current.atoms.count == 3)
  assert(history.undo()); try history.apply(try p.appending([atoms[0]])); assert(!history.canRedo)
  let roundTrip = try JSONDecoder().decode(IntegratedBuilding.EditableProject.self, from: JSONEncoder().encode(p))
  assert(roundTrip.groups == p.groups && roundTrip.charge == -1 && roundTrip.multiplicity == 2)
  let text = try p.orcaGeometryText(); assert(text.contains("* xyz -1 2") && text.contains("Angstrom"))
  let xyz = try IntegratedBuilding.parse(p.xyzText()); assert(xyz.frames[0].count == p.atoms.count)
  let methyl = IntegratedBuilding.builtInFragments.first { $0.name == "Methyl" }!.atoms
  let attached = try p.attaching(IntegratedBuilding.attachFragment(host: atoms, hostLeaving: 1, fragment: methyl, fragmentLeaving: 1), hostLeaving: 1)
  assert(attached.groups == [[0,1],[2,3],[4,5,6,7]])
  assert(attached.selection == [4,5,6,7])
  for invalid in [IntegratedBuilding.EditableProject(atoms: atoms, selection: [99]), IntegratedBuilding.EditableProject(atoms: atoms, groups:[[0,0]]), IntegratedBuilding.EditableProject(atoms: atoms, multiplicity: 0), IntegratedBuilding.EditableProject(atoms: [IntegratedBuilding.Atom(symbol:"C",x:.nan,y:0,z:0)])] {
   do { try invalid.validate(); assertionFailure("Invalid project accepted") } catch {}
  }
  do { _ = try IntegratedBuilding.EditableProject(atoms: methyl).xyzText(); assertionFailure("Dummy export accepted") } catch {}
  print("Project tests passed: index remapping, selection/history, Codable validation, charge/multiplicity export.")
 }
}
