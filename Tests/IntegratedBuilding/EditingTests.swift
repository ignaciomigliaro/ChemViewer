import Foundation
#if !CHEMVIEWER_STANDALONE
import XCTest
@testable import ChemCraftCore
#endif


struct EditingChecks {
    static func main() throws {
        let water = IntegratedBuilding.builtInFragments.first { $0.name == "Water" }!.atoms
        let shifted = IntegratedBuilding.transformedAtoms(water, selection: Set(water.indices), translation: SIMD3(8,0,0), axis: SIMD3(0,0,1), radians: 0, pivot: .zero)
        let two = water + shifted
        precondition(IntegratedBuilding.connectedAtomSelection(two, seed: 0) == Set([0,1,2]))
        precondition(IntegratedBuilding.connectedAtomSelection(two, seed: 3) == Set([3,4,5]))
        precondition(IntegratedBuilding.connectedAtomSelection(two, seed: -1).isEmpty)
        let moved = IntegratedBuilding.transformedAtoms(two, selection: Set([0,1,2]), translation: SIMD3(2,-1,4), axis: SIMD3(1,2,3), radians: 1.27, pivot: SIMD3(0.2,0.3,0.4))
        for i in 0..<3 { for j in 0..<3 {
            precondition(abs(VectorMath.distance(IntegratedBuilding.position(two[i]), IntegratedBuilding.position(two[j])) - VectorMath.distance(IntegratedBuilding.position(moved[i]), IntegratedBuilding.position(moved[j]))) < 1e-10)
        } }
        for i in 3..<6 { precondition(IntegratedBuilding.position(two[i]) == IntegratedBuilding.position(moved[i])) }
        for fragment in IntegratedBuilding.builtInFragments {
            precondition(IntegratedBuilding.connectedAtomSelection(fragment.atoms, seed: 0).count == fragment.atoms.count, fragment.name)
        }
        let translated = IntegratedBuilding.transformedAtoms(water, selection: [0], translation: SIMD3(1,2,3), axis: .zero, radians: 2, pivot: .zero)
        precondition(IntegratedBuilding.position(translated[0]) == SIMD3(1,2,3))
        let methane = IntegratedBuilding.builtInFragments.first { $0.name == "Methane" }!.atoms
        let methyl = IntegratedBuilding.builtInFragments.first { $0.name == "Methyl" }!.atoms
        let joined = try IntegratedBuilding.attachFragment(host: methane, hostLeaving: 1, fragment: methyl, fragmentLeaving: 1)
        precondition(joined.atoms.count == 8 && joined.insertedIndices == Set(4..<8))
        precondition(abs(VectorMath.distance(IntegratedBuilding.position(joined.atoms[0]), IntegratedBuilding.position(joined.atoms[4])) - 1.52) < 1e-10)
        for i in 0..<4 { for j in 0..<4 {
            let keep = [0,2,3,4]
            precondition(abs(VectorMath.distance(IntegratedBuilding.position(methyl[keep[i]]), IntegratedBuilding.position(methyl[keep[j]])) - VectorMath.distance(IntegratedBuilding.position(joined.atoms[4+i]), IntegratedBuilding.position(joined.atoms[4+j]))) < 1e-10)
        } }
        let straightHost = [IntegratedBuilding.Atom(symbol: "C", x: 0, y: 0, z: 0), IntegratedBuilding.Atom(symbol: "H", x: 1.09, y: 0, z: 0)]
        let straightFragment = [IntegratedBuilding.Atom(symbol: "C", x: 0, y: 0, z: 0), IntegratedBuilding.Atom(symbol: "X", x: 1, y: 0, z: 0), IntegratedBuilding.Atom(symbol: "O", x: 0, y: 1.2, z: 0)]
        let opposite = try IntegratedBuilding.attachFragment(host: straightHost, hostLeaving: 1, fragment: straightFragment, fragmentLeaving: 1)
        precondition(VectorMath.distance(IntegratedBuilding.position(opposite.atoms[1]), SIMD3(1.52,0,0)) < 1e-10)
        precondition(abs(VectorMath.distance(IntegratedBuilding.position(opposite.atoms[1]), IntegratedBuilding.position(opposite.atoms[2])) - 1.2) < 1e-10)
        let pivot = IntegratedBuilding.position(methane[0])
        let rotation = IntegratedBuilding.transformedAtoms(methane, selection: Set(methane.indices), translation: .zero, axis: SIMD3(1,1,1), radians: .pi, pivot: pivot)
        precondition(VectorMath.distance(IntegratedBuilding.position(rotation[0]), pivot) < 1e-12)
        do { _ = try IntegratedBuilding.attachFragment(host: methane, hostLeaving: 0, fragment: methyl, fragmentLeaving: 1); preconditionFailure("heavy atom accepted") } catch {}
        do { _ = try IntegratedBuilding.attachFragment(host: methane, hostLeaving: 1, fragment: methyl, fragmentLeaving: 1, bondLength: .nan); preconditionFailure("NaN accepted") } catch {}
        print("Editing model checks passed: rigid transforms, isolated fragments, built-in connectivity, zero axis.")
    }
}

#if CHEMVIEWER_STANDALONE
@main struct EditingTests {
    static func main() throws { try EditingChecks.main() }
}
#else
final class IntegratedEditingTests: XCTestCase {
    func testMigratedEditingAcceptance() throws { try EditingChecks.main() }
}
#endif
