import Foundation
#if !CHEMVIEWER_STANDALONE
import XCTest
@testable import ChemCraftCore
#endif
struct ParserChecks {
 static func main(referenceFile: String? = nil) throws {
  let geometry = "CARTESIAN COORDINATES (ANGSTROEM)\n---\nH 0 0 0\n\n"
  let mode = "VIBRATIONAL FREQUENCIES\n0: -123 cm**-1\nNORMAL MODES\n0\n0 0.1\n1 -0.2\n2 0.3\nIR SPECTRUM\n"
  let compound = "JOB NUMBER 1\n" + geometry + mode + "JOB NUMBER 2\n" + geometry.replacingOccurrences(of:"H 0 0 0",with:"O 0 0 0\nH 0 0 1") + "FINAL SINGLE POINT ENERGY -75.25\n"
  let d = try IntegratedBuilding.parse(compound.replacingOccurrences(of:"\n",with:"\r\n"))
  precondition(d.frames.map(\.count) == [1,2])
  precondition(d.modes(forFrame:0).count == 1 && d.modes(forFrame:1).isEmpty)
  precondition(d.modesByFrame[0][0].displacements[0] == SIMD3(0.1,-0.2,0.3))
  precondition(d.abstractText.contains("-75.25 Eh") && d.abstractText.contains("source line"))
  precondition(!d.abstractText.contains("Charge:"))
  let dummy = try IntegratedBuilding.parse("2\nattachment dummy\nC 0 0 0\nX 1.5 0 0\n")
  precondition(dummy.frames[0][1].symbol == "X")
  let newJob = try IntegratedBuilding.parse(geometry + "$new_job\n" + mode)
  precondition(newJob.modesByFrame[0].isEmpty)
  let pressure = try IntegratedBuilding.parse(geometry + "Pressure 1.01325 bar\n")
  precondition(pressure.abstractText.contains("1.01325 bar"))
  do { _ = try IntegratedBuilding.parse("CARTESIAN COORDINATES (ANGSTROEM)\n---\nH 0 0 0"); preconditionFailure("accepted unterminated table") } catch {}
  let noGeometry = try IntegratedBuilding.parse(geometry + "JOB NUMBER 2\n" + mode)
  precondition(noGeometry.modesByFrame[0].isEmpty)
  for corrupt in [mode.replacingOccurrences(of:"2 0.3",with:""),mode.replacingOccurrences(of:"2 0.3",with:"2 NaN"),mode.replacingOccurrences(of:"2 0.3",with:"2 0.3\n2 0.4")] {
   precondition(IntegratedBuilding.parseOrcaModes(corrupt,atomCount:1).isEmpty)
  }
  precondition(IntegratedBuilding.parseOrcaModes(mode.replacingOccurrences(of:"2 0.3",with:"2 1e300"),atomCount:1).isEmpty)
  precondition(IntegratedBuilding.parseOrcaModes(mode.replacingOccurrences(of:"-123",with:"1e300"),atomCount:1).isEmpty)
  do { _ = try IntegratedBuilding.parse(geometry.replacingOccurrences(of:"H 0 0 0",with:"H 0 0 0\nO NaN 0 1")); preconditionFailure("accepted malformed row") } catch {}
  do { _ = try IntegratedBuilding.parse("2\ntruncated\nH 0 0 0\n"); preconditionFailure("accepted truncated XYZ") } catch {}
  let xyz = try IntegratedBuilding.parse("1\nframe one\nC 0 0 0\n1\nframe two\nC 1 0 0\n")
  precondition(xyz.frames.count == 2)
  if let referenceFile {
   let water = try IntegratedBuilding.loadDocument(URL(fileURLWithPath:referenceFile))
   precondition(water.frames.count == 6 && water.frames.allSatisfy { $0.count == 3 })
   precondition(water.modesByFrame.dropLast().allSatisfy(\.isEmpty))
   let modes = water.modesByFrame.last!
   precondition(modes.count == 9 && modes[6].frequency == 1606.12)
   precondition(abs(modes[6].displacements[1].y + 0.434645) < 1e-10)
   precondition(abs(modes[8].displacements[2].z - 0.467702) < 1e-10)
  }
  print("Parser tests passed: compound job association, CRLF, vector values, malformed tables/coordinates, summaries and multi-frame XYZ.")
 }
}

#if CHEMVIEWER_STANDALONE
@main struct ParserTests {
    static func main() throws { try ParserChecks.main(referenceFile: CommandLine.arguments.dropFirst().first) }
}
#else
final class IntegratedParserTests: XCTestCase {
    func testMigratedParserAcceptance() throws { try ParserChecks.main() }
}
#endif
