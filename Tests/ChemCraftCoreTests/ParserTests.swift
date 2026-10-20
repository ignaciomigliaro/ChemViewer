import XCTest
@testable import ChemCraftCore

final class ParserTests: XCTestCase {
    func testMultiFrameXYZ() throws {
        let text = """
        2
        frame one
        H 0 0 0
        H 0 0 0.74
        2
        frame two
        1 0 0 0
        1 0 0 0.75
        """
        let document = try XYZParser.parse(text: text)
        XCTAssertEqual(document.frames.count, 2)
        XCTAssertEqual(document.frames[1].atoms[0].element, "H")
        XCTAssertEqual(document.frames[1].atoms[1].position.z, 0.75, accuracy: 1e-6)
    }

    func testXYZExportRoundTripIsDeterministic() throws {
        let frame = MoleculeFrame(id: 3, atoms: [
            Atom(id: 0, element: "O", position: Vector3(0, -0.0, 0)),
            Atom(id: 1, element: "H", position: Vector3(0.9572, 0, 0)),
            Atom(id: 2, element: "H", position: Vector3(-0.2399872, 0.9266272, 0))
        ], comment: "edited\ngeometry")

        let first = XYZWriter.string(frame: frame)
        let second = XYZWriter.string(frame: frame)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.split(separator: "\n", omittingEmptySubsequences: false)[1], "edited geometry")

        let parsed = try XYZParser.parse(text: first)
        XCTAssertEqual(parsed.frames.count, 1)
        XCTAssertEqual(parsed.frames[0].atoms.map(\.element), ["O", "H", "H"])
        for index in frame.atoms.indices {
            XCTAssertEqual(parsed.frames[0].atoms[index].position.x, frame.atoms[index].position.x, accuracy: 1e-7)
            XCTAssertEqual(parsed.frames[0].atoms[index].position.y, frame.atoms[index].position.y, accuracy: 1e-7)
            XCTAssertEqual(parsed.frames[0].atoms[index].position.z, frame.atoms[index].position.z, accuracy: 1e-7)
        }
    }

    func testORCAFrequencyAndDisplacements() throws {
        let text = """
        CARTESIAN COORDINATES (ANGSTROEM)
        ---------------------------------
        O 0.0 0.0 0.0
        H 0.0 0.7 0.5
        H 0.0 -0.7 0.5

        FINAL SINGLE POINT ENERGY -76.123456
        VIBRATIONAL FREQUENCIES
        -----------------------
        0: 0.00 cm**-1
        6: 1606.12 cm**-1
        7: -42.50 cm**-1
        NORMAL MODES
        ------------
             0       6       7
        0 0.000 0.000 0.010
        1 0.000 0.010 0.000
        2 0.000 0.020 0.000
        3 0.000 0.000 0.000
        4 0.000 -0.300 0.000
        5 0.000 0.400 0.000
        6 0.000 0.000 0.000
        7 0.000 0.300 0.000
        8 0.000 0.400 0.000
        IR SPECTRUM
        -----------
        6: 1606.12 45.965085 ( 0.0 0.0 1.0)
        7: -42.50 2.5 ( 0.0 0.0 1.0)
        THERMOCHEMISTRY AT 298.15K
        """
        let document = try ORCAParser.parse(text: text)
        XCTAssertEqual(document.frames.count, 1)
        XCTAssertEqual(document.frames[0].energyHartree!, -76.123456, accuracy: 1e-9)
        XCTAssertEqual(document.vibrationalModes.count, 3)
        XCTAssertEqual(document.vibrationalModes[1].displacements.count, 3)
        XCTAssertEqual(document.vibrationalModes[1].infraredIntensity!, 45.965085, accuracy: 1e-9)
        XCTAssertTrue(document.vibrationalModes[2].isImaginary)
    }

    func testBondInference() {
        let atoms = [
            Atom(id: 0, element: "O", position: Vector3(0, 0, 0)),
            Atom(id: 1, element: "H", position: Vector3(0, 0, 0.96)),
            Atom(id: 2, element: "H", position: Vector3(5, 5, 5))
        ]
        let bonds = BondBuilder.inferBonds(atoms: atoms)
        XCTAssertEqual(bonds.count, 1)
        XCTAssertEqual(bonds[0].first, 0)
        XCTAssertEqual(bonds[0].second, 1)
    }

    func testBroadeningUsesHalfWidthAtHalfMaximum() {
        for shape in SpectralLineShape.allCases {
            let points = SpectrumBroadening.sample(
                lines: [SpectralLine(position: 1000, intensity: 8)],
                from: 1000,
                to: 1010,
                pointCount: 2,
                halfWidthAtHalfMaximum: 10,
                shape: shape
            )
            XCTAssertEqual(points[0].y, 8, accuracy: 1e-12)
            XCTAssertEqual(points[1].y, 4, accuracy: 1e-12)
        }
    }

    func testORCAUsesLastFrequencyJobAndAssociatesEnergiesByPosition() throws {
        let text = """
        CARTESIAN COORDINATES (ANGSTROEM)
        ---------------------------------
        H 0 0 0

        FINAL SINGLE POINT ENERGY -1.0
        VIBRATIONAL FREQUENCIES
        0: 100.0 cm**-1
        NORMAL MODES
             0
        0 0.1
        1 0.0
        2 0.0
        IR SPECTRUM
        0: 100.0 1.0
        THERMOCHEMISTRY
        CARTESIAN COORDINATES (ANGSTROEM)
        ---------------------------------
        H 0 0 1

        FINAL SINGLE POINT ENERGY -2.0
        VIBRATIONAL FREQUENCIES
        0: -25.0 cm**-1
        NORMAL MODES
             0
        0 0.0
        1 0.0
        2 0.2
        IR SPECTRUM
        0: -25.0 3.0
        THERMOCHEMISTRY
        """
        let document = try ORCAParser.parse(text: text)
        XCTAssertEqual(document.frames.count, 2)
        XCTAssertEqual(document.frames[0].energyHartree!, -1.0, accuracy: 1e-12)
        XCTAssertEqual(document.frames[1].energyHartree!, -2.0, accuracy: 1e-12)
        XCTAssertEqual(document.vibrationalModes.count, 1)
        XCTAssertEqual(document.vibrationalModes[0].frequencyCM1, -25.0, accuracy: 1e-12)
        XCTAssertEqual(document.vibrationalModes[0].infraredIntensity!, 3.0, accuracy: 1e-12)
        XCTAssertEqual(document.vibrationalModes[0].displacements[0].z, 0.2, accuracy: 1e-6)
    }

    func testGeometryEditingIsRigidAndReversibleByValue() throws {
        let frame = MoleculeFrame(id: 0, atoms: [
            Atom(id: 0, element: "C", position: Vector3(0, 0, 0)),
            Atom(id: 1, element: "H", position: Vector3(1, 0, 0)),
            Atom(id: 2, element: "H", position: Vector3(0, 1, 0))
        ])
        let stretched = try GeometryEditor.settingBondLength(
            in: frame, fixedAtomIndex: 0, movingAtomIndex: 1, to: 1.5
        )
        XCTAssertEqual(
            try GeometryEditor.distance(in: stretched, firstAtomIndex: 0, secondAtomIndex: 1),
            1.5,
            accuracy: 1e-6
        )
        XCTAssertEqual(stretched.atoms[2].position, frame.atoms[2].position)

        let translated = try GeometryEditor.translating(
            in: stretched, atomIndices: [1, 2], by: Vector3(0.2, -0.3, 0.4)
        )
        XCTAssertEqual(translated.atoms[0].position, frame.atoms[0].position)
        XCTAssertEqual(translated.atoms[1].position.x, 1.7, accuracy: 1e-6)
        XCTAssertEqual(translated.atoms[2].position.z, 0.4, accuracy: 1e-6)
    }

    func testWindowsReferenceDistanceAngleAndDihedralConventions() throws {
        let water = MoleculeFrame(id: 0, atoms: [
            Atom(id: 0, element: "O", position: Vector3(0, 0, 0)),
            Atom(id: 1, element: "H", position: Vector3(0.9572, 0, 0)),
            Atom(id: 2, element: "H", position: Vector3(-0.239987208, 0.926627207, 0))
        ])
        XCTAssertEqual(
            try GeometryEditor.distance(in: water, firstAtomIndex: 2, secondAtomIndex: 0),
            0.9572,
            accuracy: 1e-5
        )
        XCTAssertEqual(
            try GeometryEditor.angleDegrees(
                in: water, firstAtomIndex: 2, vertexAtomIndex: 0, thirdAtomIndex: 1
            ),
            104.520,
            accuracy: 1e-3
        )

        let chain = MoleculeFrame(id: 0, atoms: [
            Atom(id: 0, element: "C", position: Vector3(0, 0, 0)),
            Atom(id: 1, element: "C", position: Vector3(1.54, 0, 0)),
            Atom(id: 2, element: "C", position: Vector3(2.31, 1.3336791218, 0)),
            Atom(id: 3, element: "C", position: Vector3(3.08, 1.3336791218, 1.3336791218))
        ])
        XCTAssertEqual(
            try GeometryEditor.dihedralDegrees(
                in: chain,
                firstAtomIndex: 0,
                secondAtomIndex: 1,
                thirdAtomIndex: 2,
                fourthAtomIndex: 3
            ),
            116.565,
            accuracy: 1e-3
        )
    }
    func testWindowsAndClassicMacLineEndingsPreserveCompleteGeometriesAndVectors() throws {
        let xyz = "2\nhydrogen\nH 0 0 0\nH 0 0 0.74\n"
        let orca = """
        CARTESIAN COORDINATES (ANGSTROEM)
        ---------------------------------
        O 0 0 0
        H 0.9572 0 0
        H -0.239987208 0.926627207 0

        FINAL SINGLE POINT ENERGY -76.123456
        VIBRATIONAL FREQUENCIES
        6: -42.50 cm**-1
        NORMAL MODES
              6
        0 0.000
        1 0.010
        2 0.020
        3 0.000
        4 -0.300
        5 0.400
        6 0.000
        7 0.300
        8 0.400
        IR SPECTRUM
        6: -42.50 2.5
        THERMOCHEMISTRY
        """
        for newline in ["\n", "\r\n", "\r"] {
            let structure = try XYZParser.parse(text: xyz.replacingOccurrences(of: "\n", with: newline))
            XCTAssertEqual(structure.frames[0].atoms.count, 2)
            XCTAssertEqual(structure.frames[0].atoms[1].position.z, 0.74, accuracy: 1e-6)
            let output = try ORCAParser.parse(text: orca.replacingOccurrences(of: "\n", with: newline))
            XCTAssertEqual(output.frames[0].atoms.count, 3)
            XCTAssertEqual(output.vibrationalModes[0].displacements.count, 3)
            XCTAssertEqual(output.vibrationalModes[0].displacements[2].z, 0.4, accuracy: 1e-6)
            XCTAssertEqual(output.vibrationalModes[0].frequencyCM1, -42.5, accuracy: 1e-9)
        }
    }

    func testFrequencyGeometryIsNotALaterJobAndIncompleteVectorsAreNotInvented() throws {
        let prefix = """
        CARTESIAN COORDINATES (ANGSTROEM)
        ---------------------------------
        H 0 0 0

        VIBRATIONAL FREQUENCIES
        0: -25.0 cm**-1
        NORMAL MODES
             0
        0 0.1
        1 0.2
        2 0.3
        IR SPECTRUM
        0: -25.0 2.0
        """
        let later = """

        CARTESIAN COORDINATES (ANGSTROEM)
        ---------------------------------
        O 0 0 0
        H 0 0 1

        """
        let parsed = try ORCAParser.parse(text: prefix + "\n" + later)
        XCTAssertEqual(parsed.vibrationalFrameIndex, 0)
        XCTAssertEqual(parsed.frames.last!.atoms.count, 2)
        XCTAssertEqual(parsed.vibrationalModes[0].displacements.count, 1)
        XCTAssertEqual(parsed.vibrationalModes[0].displacements[0].z, 0.3, accuracy: 1e-6)
        let incomplete = try ORCAParser.parse(text: prefix.replacingOccurrences(of: "2 0.3", with: ""))
        XCTAssertTrue(incomplete.vibrationalModes[0].displacements.isEmpty)
        XCTAssertTrue(!incomplete.warnings.isEmpty)
    }

    func testMissingFinalModeMatrixDoesNotBorrowPreviousJobAndRejectsNaN() throws {
        let text = """
        CARTESIAN COORDINATES (ANGSTROEM)
        ----
        H 0 0 0

        VIBRATIONAL FREQUENCIES
        0: 100.0 cm**-1
        NORMAL MODES
             0
        0 0.1
        1 0.2
        2 0.3
        IR SPECTRUM
        0: 100.0 4.0
        CARTESIAN COORDINATES (ANGSTROEM)
        ----
        H 0 0 1

        VIBRATIONAL FREQUENCIES
        0: -99.0 cm**-1
        """
        let output = try ORCAParser.parse(text: text)
        XCTAssertEqual(output.vibrationalFrameIndex, 1)
        XCTAssertEqual(output.vibrationalModes[0].frequencyCM1, -99.0, accuracy: 1e-9)
        XCTAssertTrue(output.vibrationalModes[0].displacements.isEmpty)
        XCTAssertTrue(output.vibrationalModes[0].infraredIntensity == nil)
        var rejectedXYZ = false
        do { _ = try XYZParser.parse(text: "1\nbad\nH nan 0 0\n") } catch { rejectedXYZ = true }
        XCTAssertTrue(rejectedXYZ)
        var rejectedORCA = false
        do { _ = try ORCAParser.parse(text: "CARTESIAN COORDINATES (ANGSTROEM)\n----\nH nan 0 0\n") } catch { rejectedORCA = true }
        XCTAssertTrue(rejectedORCA)
    }

    func testXYZEnergyUnitsAndProvenance() throws {
        let comments = ["Energy=-76.125 Eh", "E=-2.7211386245981e1 eV", "energy_hartree=-1.5D+00", "-2.0", "temperature 298.15", "Energy=-1 banana"]
        let text = comments.map { "1\n\($0)\nH 0 0 0\n" }.joined()
        let doc = try XYZParser.parse(text: text)
        XCTAssertEqual(doc.energyRecords.count, 4)
        XCTAssertEqual(doc.frames[0].energyHartree!, -76.125, accuracy: 1e-10)
        XCTAssertEqual(doc.frames[1].energyHartree!, -1, accuracy: 1e-12)
        XCTAssertEqual(doc.frames[2].energyHartree!, -1.5, accuracy: 1e-12)
        XCTAssertTrue(doc.frames[3].energyHartree == nil)
        XCTAssertEqual(doc.energyRecords[3].hartree(assuming: .hartree)!, -2, accuracy: 1e-12)
        XCTAssertEqual(doc.energyRecords[0].sourceLine, 2)
        XCTAssertEqual(doc.energyRecords[1].sourceLine, 5)
        XCTAssertEqual(EnergyUnit.kilojoulePerMole.perHartree, 2625.4996394799, accuracy: 1e-8)
        XCTAssertEqual(EnergyUnit.kilocaloriePerMole.perHartree, 627.5094740631, accuracy: 1e-8)
    }

    func testFreeFragmentPlacement() throws {
        let fragment = BuildingProject.fragment(3)
        let empty = try BuildingProject(atoms: [])
        let point = Vector3(3, -2, 1)
        let first = try empty.placing(fragment, at: point)
        let centroid = first.atoms.reduce(Vector3.zero) { $0 + $1.position } * (1 / Float(first.atoms.count))
        XCTAssertEqual((centroid - point).length, 0, accuracy: 1e-5)
        XCTAssertEqual(first.atoms.count, fragment.count)
        XCTAssertEqual(first.atoms.map(\.element), fragment.map(\.element))
        let second = try first.placing(fragment, at: Vector3(-4, 2, 0))
        XCTAssertEqual(Array(second.atoms.prefix(fragment.count)), first.atoms)
        XCTAssertEqual(second.atoms.count, fragment.count * 2)
        let a = (fragment[0].position - fragment[1].position).length
        let b = (first.atoms[0].position - first.atoms[1].position).length
        XCTAssertEqual(a, b, accuracy: 1e-5)
        var rejected = false
        do { _ = try empty.placing(fragment, at: Vector3(.nan, 0, 0)) } catch { rejected = true }
        XCTAssertTrue(rejected)
    }

    func testBuilderClickAttachmentAndAnyElement() throws {
        let host = try BuildingProject(atoms: BuildingProject.fragment(1)) // methane
        let methyl = BuildingProject.fragment(3)
        let attached = try host.attachingAtAtom(methyl, hostAtom: 0, fragmentLeaving: 1)
        XCTAssertEqual(attached.atoms.filter { $0.element == "C" }.count, 2)
        XCTAssertEqual(attached.atoms.filter { $0.element == "H" }.count, 6)
        XCTAssertEqual(attached.atoms.count, 8)
        let carbons = attached.atoms.filter { $0.element == "C" }
        XCTAssertEqual((carbons[0].position - carbons[1].position).length, 1.52, accuracy: 0.01)
        XCTAssertTrue(attached.atoms.allSatisfy { $0.element != "X" })
        let fluorinated = try host.attachingAtom("F", hostAtom: 0)
        XCTAssertEqual(fluorinated.atoms.filter { $0.element == "H" }.count, 3)
        XCTAssertEqual(fluorinated.atoms.filter { $0.element == "F" }.count, 1)
        let hydrogen = try host.attachingAtom("H", hostAtom: 0)
        XCTAssertEqual(hydrogen.atoms.count, 5)
        let xenon = try host.attachingAtom("Xe", hostAtom: 0)
        XCTAssertEqual(xenon.atoms.last!.element, "Xe")
        var rejected = false
        do { _ = try host.attachingAtom("Invalid", hostAtom: 0) } catch { rejected = true }
        XCTAssertTrue(rejected)
        // An unsaturated single atom has no H/X; a new direction is generated.
        let bare = try BuildingProject(atoms: [Atom(id: 0, element: "Fe", position: .zero)])
        let metal = try bare.attachingAtAtom(methyl, hostAtom: 0, fragmentLeaving: 1)
        XCTAssertEqual(metal.atoms.count, 5)
        XCTAssertEqual(metal.atoms[0].position, .zero)
    }

    func testORCATrajectoryCommentEnergies() throws {
        // Independently generated ORCA-style comments, not personal calculation data.
        let comments = ["Coordinates from ORCA-job sample E -10.125",
                        "Coordinates from ORCA-job sample_path E -1.000D+01",
                        "Coordinates from ORCA-job sample E -9.875",
                        "generic comment E -10.0", "Coordinates from ORCA-job sample E nan"]
        let doc = try XYZParser.parse(text: comments.map { "1\n\($0)\nH 0 0 0\n" }.joined())
        XCTAssertEqual(doc.frames.count, 5)
        XCTAssertEqual(doc.energyRecords.count, 3)
        XCTAssertEqual(doc.frames[0].energyHartree!, -10.125, accuracy: 1e-12)
        XCTAssertEqual(doc.frames[1].energyHartree!, -10, accuracy: 1e-12)
        XCTAssertEqual(doc.frames[2].energyHartree!, -9.875, accuracy: 1e-12)
        XCTAssertEqual(doc.energyRecords.map(\.sourceLine), [2, 5, 8])
        XCTAssertEqual(doc.energyRecords.map(\.frameIndex), [0, 1, 2])
        XCTAssertTrue(doc.energyRecords.allSatisfy { $0.unit == .hartree })
        XCTAssertEqual(doc.energyRecords[0].sourceText, comments[0])
        XCTAssertTrue(doc.frames[3].energyHartree == nil && doc.frames[4].energyHartree == nil)
    }

    func testSCFAndFinalEnergyStayDistinct() throws {
        let text = """
        CARTESIAN COORDINATES (ANGSTROEM)
        ----
        H 0 0 0

        TOTAL SCF ENERGY
        ----------------
        Total Energy       : -1.123456789012 Eh -30.57 eV
        FINAL SINGLE POINT ENERGY -1.223456789012
        CARTESIAN COORDINATES (ANGSTROEM)
        ----
        H 1 0 0

        TOTAL SCF ENERGY
        Total Energy : -1.234567890123 Eh
        """
        let doc = try ORCAParser.parse(text: text)
        XCTAssertEqual(doc.energyRecords.count, 3)
        XCTAssertEqual(doc.energyRecords.map(\.kind), [.scf, .singlePoint, .scf])
        XCTAssertEqual(doc.energyRecords.map(\.frameIndex), [0, 0, 1])
        XCTAssertEqual(doc.frames[0].energyHartree!, -1.223456789012, accuracy: 1e-12)
        XCTAssertEqual(doc.frames[1].energyHartree!, -1.234567890123, accuracy: 1e-12)
        XCTAssertTrue(doc.energyRecords[0].sourceText.contains("-1.123456789012"))
    }

    func testDistanceModesPreserveFixedAtomOrMidpoint() throws {
        let frame = MoleculeFrame(id: 0, atoms: [
            Atom(id: 0, element: "H", position: Vector3(1, 2, 3)),
            Atom(id: 1, element: "H", position: Vector3(1, 2, 5)),
            Atom(id: 2, element: "O", position: Vector3(-1, -2, -3))
        ])
        let second = try GeometryEditor.settingDistance(in: frame, first: 0, second: 1, to: 3, movement: .secondAtom)
        XCTAssertEqual(second.atoms[0], frame.atoms[0])
        XCTAssertEqual(second.atoms[1].position, Vector3(1, 2, 6))
        let both = try GeometryEditor.settingDistance(in: frame, first: 0, second: 1, to: 1, movement: .bothAtoms)
        XCTAssertEqual(both.atoms[0].position, Vector3(1, 2, 3.5))
        XCTAssertEqual(both.atoms[1].position, Vector3(1, 2, 4.5))
        XCTAssertEqual(both.atoms[2], frame.atoms[2])
        XCTAssertEqual(try GeometryEditor.distance(in: both, firstAtomIndex: 0, secondAtomIndex: 1), 1, accuracy: 1e-6)
        var rejected = false
        do { _ = try GeometryEditor.settingDistance(in: frame, first: 0, second: 1, to: .infinity, movement: .bothAtoms) } catch { rejected = true }
        XCTAssertTrue(rejected)
    }

    func testAngleEditPreservesBothLengthsAndOtherAtoms() throws {
        let frame = MoleculeFrame(id: 0, atoms: [
            Atom(id: 0, element: "H", position: Vector3(3, 1, 1)),
            Atom(id: 1, element: "O", position: Vector3(1, 1, 1)),
            Atom(id: 2, element: "H", position: Vector3(1, 4, 1)),
            Atom(id: 3, element: "C", position: Vector3(4, 5, 6))
        ])
        let result = try GeometryEditor.settingAngle(in: frame, first: 0, vertex: 1, third: 2, toDegrees: 60)
        // Independent analytic coordinate: B + 3(cos60, sin60, 0).
        XCTAssertEqual(result.atoms[2].position.x, 2.5, accuracy: 1e-6)
        XCTAssertEqual(result.atoms[2].position.y, 3.598076211, accuracy: 1e-6)
        XCTAssertEqual(result.atoms[2].position.z, 1, accuracy: 1e-6)
        XCTAssertEqual(result.atoms[0], frame.atoms[0])
        XCTAssertEqual(result.atoms[1], frame.atoms[1])
        XCTAssertEqual(result.atoms[3], frame.atoms[3])
        XCTAssertEqual(try GeometryEditor.angleDegrees(in: result, firstAtomIndex: 0, vertexAtomIndex: 1, thirdAtomIndex: 2), 60, accuracy: 1e-4)
        XCTAssertEqual(try GeometryEditor.distance(in: result, firstAtomIndex: 1, secondAtomIndex: 2), 3, accuracy: 1e-6)
        var rejected = false
        do { _ = try GeometryEditor.settingAngle(in: frame, first: 0, vertex: 1, third: 2, toDegrees: .nan) } catch { rejected = true }
        XCTAssertTrue(rejected)
        let collinear = try GeometryEditor.settingAngle(in: frame, first: 0, vertex: 1, third: 2, toDegrees: 180)
        let bentAgain = try GeometryEditor.settingAngle(in: collinear, first: 0, vertex: 1, third: 2, toDegrees: 90)
        XCTAssertEqual(try GeometryEditor.angleDegrees(in: bentAgain, firstAtomIndex: 0, vertexAtomIndex: 1, thirdAtomIndex: 2), 90, accuracy: 1e-4)
    }

    func testXYZEnergyExportRetainsUnits() throws {
        let original = try XYZParser.parse(text: "1\nenergy=-27.211386245981 eV\nH 0 0 0\n").frames[0]
        let exported = XYZWriter.string(frame: original)
        let parsed = try XYZParser.parse(text: exported)
        XCTAssertEqual(parsed.frames[0].energyHartree!, -1, accuracy: 1e-12)
        XCTAssertTrue(exported.contains("energy_hartree=-1"))
        XCTAssertEqual(XYZWriter.string(frame: parsed.frames[0]), exported)
    }

    func testThermochemistrySumsUseFullCorrectionsAndPreserveTemperature() throws {
        let text = """
        CARTESIAN COORDINATES (ANGSTROEM)
        ----
        H 0 0 0

        FINAL SINGLE POINT ENERGY -10.05
        THERMOCHEMISTRY AT 298.15K
        Temperature ... 298.15 K
        Pressure ... 1.00 atm
        Electronic energy ... -10.0 Eh
        Zero point energy ... 0.15 Eh
        Thermal Enthalpy correction ... 0.00094421 Eh
        Total Enthalpy ... -9.8 Eh
        Final Gibbs free energy ... -9.9 Eh
        G-E(el) ... 0.1 Eh
        CARTESIAN COORDINATES (ANGSTROEM)
        ----
        H 1 0 0

        THERMOCHEMISTRY AT 600.00K
        Electronic energy ... -20.0 Eh
        Total Enthalpy ... -19.75 Eh
        Final Gibbs free enthalpy ... -19.9 Eh
        """
        let doc = try ORCAParser.parse(text: text)
        XCTAssertEqual(doc.thermochemistry.count, 2)
        let first = doc.thermochemistry[0], second = doc.thermochemistry[1]
        XCTAssertEqual(first.temperatureKelvin!, 298.15, accuracy: 1e-10)
        XCTAssertEqual(second.temperatureKelvin!, 600, accuracy: 1e-10)
        XCTAssertEqual(first.frameIndex, 0)
        XCTAssertEqual(second.frameIndex, 1)
        XCTAssertEqual(first.enthalpyCorrection!, 0.2, accuracy: 1e-12)
        XCTAssertEqual(first.gibbsCorrection!, 0.1, accuracy: 1e-12)
        XCTAssertEqual(first.summedEnthalpy(electronicEnergy: -10.05)!, -9.85, accuracy: 1e-12)
        XCTAssertEqual(first.summedGibbs(electronicEnergy: -10.05)!, -9.95, accuracy: 1e-12)
        XCTAssertEqual(second.gibbsCorrection!, 0.1, accuracy: 1e-12)
        let partial = try ORCAParser.parse(text: text.components(separatedBy: "Total Enthalpy")[0])
        XCTAssertTrue(partial.thermochemistry[0].enthalpy == nil)
        XCTAssertTrue(partial.thermochemistry[0].summedEnthalpy(electronicEnergy: -10) == nil)
    }

    func testSymmetricAngleRotatesBothEndsEqually() throws {
        let frame = MoleculeFrame(id: 0, atoms: [
            Atom(id: 0, element: "H", position: Vector3(2, 0, 0)),
            Atom(id: 1, element: "O", position: .zero),
            Atom(id: 2, element: "H", position: Vector3(0, 3, 0))
        ])
        let result = try GeometryEditor.settingAngle(in: frame, first: 0, vertex: 1, third: 2, toDegrees: 60, movement: .bothEnds)
        XCTAssertEqual(result.atoms[0].position.x, 1.931851653, accuracy: 1e-6)
        XCTAssertEqual(result.atoms[0].position.y, 0.517638090, accuracy: 1e-6)
        XCTAssertEqual(result.atoms[2].position.x, 0.776457135, accuracy: 1e-6)
        XCTAssertEqual(result.atoms[2].position.y, 2.897777479, accuracy: 1e-6)
        XCTAssertEqual(result.atoms[1], frame.atoms[1])
        XCTAssertEqual(try GeometryEditor.angleDegrees(in: result, firstAtomIndex: 0, vertexAtomIndex: 1, thirdAtomIndex: 2), 60, accuracy: 1e-4)
    }

    func testFragmentBoundaryAndRigidRotationKeepOtherAtomsFixed() throws {
        let frame = MoleculeFrame(id: 0, atoms: [
            Atom(id: 0, element: "C", position: .zero),
            Atom(id: 1, element: "C", position: Vector3(1.4, 0, 0)),
            Atom(id: 2, element: "C", position: Vector3(2.8, 0, 0)),
            Atom(id: 3, element: "O", position: Vector3(10, 0, 0))
        ])
        XCTAssertEqual(try GeometryEditor.connectedAtoms(in: frame, seed: 0), [0, 1, 2])
        let fragment = try GeometryEditor.fragment(in: frame, fixed: 0, moving: 1)
        XCTAssertEqual(fragment, [1, 2])
        let result = try GeometryEditor.rotating(in: frame, atomIndices: fragment, around: frame.atoms[1].position, axis: Vector3(0, 0, 1), degrees: 90)
        XCTAssertEqual(result.atoms[2].position.x, 1.4, accuracy: 1e-6)
        XCTAssertEqual(result.atoms[2].position.y, 1.4, accuracy: 1e-6)
        XCTAssertEqual(result.atoms[0], frame.atoms[0])
        XCTAssertEqual(result.atoms[3], frame.atoms[3])
        XCTAssertEqual(try GeometryEditor.distance(in: result, firstAtomIndex: 1, secondAtomIndex: 2), 1.4, accuracy: 1e-6)
        let moved = try GeometryEditor.translating(in: frame, atomIndices: fragment, by: Vector3(0, 2, 0))
        XCTAssertEqual(moved.atoms[1].position.y, 2)
        XCTAssertEqual(moved.atoms[0], frame.atoms[0])
        var ring = frame
        ring.atoms[2].position = Vector3(0.7, 1.212435565, 0)
        var rejected = false
        do { _ = try GeometryEditor.fragment(in: ring, fixed: 0, moving: 1) } catch { rejected = true }
        XCTAssertTrue(rejected)
    }

    func testIntegratedFragmentAttachmentAndProjectCompatibility() throws {
        let methane = BuildingProject.fragment(1), methyl = BuildingProject.fragment(3)
        let project = try BuildingProject(atoms: methane, groups: [[0, 1, 2], [3, 4]], selection: [1], charge: -1, multiplicity: 2)
        let ethane = try project.attaching(methyl, hostLeaving: 1, fragmentLeaving: 1)
        XCTAssertEqual(ethane.atoms.count, 8)
        XCTAssertTrue(!ethane.atoms.contains { $0.element == "X" })
        XCTAssertEqual(ethane.selection, [4, 5, 6, 7])
        XCTAssertEqual(ethane.groups, [[0, 1], [2, 3], [4, 5, 6, 7]])
        let frame = MoleculeFrame(id: 0, atoms: ethane.atoms)
        XCTAssertEqual(try GeometryEditor.distance(in: frame, firstAtomIndex: 0, secondAtomIndex: 4), 1.52, accuracy: 0.00001)
        let decoded = try JSONDecoder().decode(BuildingProject.self, from: JSONEncoder().encode(ethane))
        XCTAssertEqual(decoded.atoms, ethane.atoms)
        XCTAssertEqual(decoded.groups, ethane.groups)
        XCTAssertEqual(decoded.selection, ethane.selection)
        XCTAssertTrue(try decoded.orcaGeometryText().contains("* xyz -1 2"))
        let legacy = "{\"atoms\":[{\"symbol\":\"O\",\"x\":0,\"y\":0,\"z\":0}],\"groups\":[[0]],\"selection\":[0],\"charge\":0,\"multiplicity\":1}"
        XCTAssertEqual(try JSONDecoder().decode(BuildingProject.self, from: Data(legacy.utf8)).atoms[0].element, "O")
    }
    func testIntegratedBuildingSelectionDeletionAndValidation() throws {
        XCTAssertEqual(try BuildingProject.selection("3,1-2,3", atomCount: 4), [2, 0, 1])
        let p = try BuildingProject(atoms: BuildingProject.fragment(1), groups: [[0, 1, 2], [3, 4]], selection: [1, 3])
        let deleted = try p.deleting([1, 4])
        XCTAssertEqual(deleted.groups, [[0, 1], [2]])
        XCTAssertEqual(deleted.selection, [2])
        var rejected = 0
        do { _ = try BuildingProject.selection("0,999", atomCount: 5) } catch { rejected += 1 }
        do { _ = try BuildingProject(atoms: p.atoms, groups: [[0, 0]]) } catch { rejected += 1 }
        do { _ = try BuildingProject(atoms: p.atoms, multiplicity: 0) } catch { rejected += 1 }
        do { _ = try BuildingProject(atoms: BuildingProject.fragment(3)).orcaGeometryText() } catch { rejected += 1 }
        XCTAssertEqual(rejected, 4)
        let transformed = try p.transformed(selection: [0, 1], translation: Vector3(2, 0, 0), axis: Vector3(0, 0, 1), degrees: 90, pivot: .zero)
        XCTAssertEqual(transformed.atoms[0].position.x, 2, accuracy: 0.00001)
        XCTAssertEqual(transformed.atoms[1].position.y, p.atoms[1].position.x, accuracy: 0.00001)
        XCTAssertEqual(transformed.atoms[2], p.atoms[2])
    }
    func testIntegratedGaussianGeometryReading() throws {
        let text = "Standard orientation:\n -----\n Center Atomic Atomic Coordinates (Angstroms)\n Number Number Type X Y Z\n -----\n 1 8 0 0.0 0.0 0.0\n 2 1 0 0.95 0.0 0.0\n -----\n"
        let parsed = try ParserRegistry.parse(text: text, fileName: "synthetic.log")
        XCTAssertEqual(parsed.sourceFormat, "Gaussian")
        XCTAssertEqual(parsed.frames[0].atoms.map(\.element), ["O", "H"])
        XCTAssertEqual(parsed.frames[0].atoms[1].position.x, 0.95, accuracy: 0.00001)
    }

    func testSpatialBondInferenceMatchesDistanceOracle() throws {
        let atoms = (0..<120).map { i in Atom(id: i, element: i % 3 == 0 ? "H" : "C", position: Vector3(Float(i % 7) * 0.9, Float((i / 7) % 5) * 1.1, Float(i / 35) * 1.3)) }
        var expected: [String] = []
        for i in atoms.indices { for j in atoms.indices where j > i {
            let distance = (atoms[i].position - atoms[j].position).length
            if distance > 0.1 && distance <= 1.22 * (ElementTable.covalentRadius(for: atoms[i].element) + ElementTable.covalentRadius(for: atoms[j].element)) { expected.append("\(i)-\(j)") }
        } }
        XCTAssertEqual(BondBuilder.inferBonds(atoms: atoms).map { "\($0.first)-\($0.second)" }, expected)
    }

    func testNEBTSFinalSummaryAndRefinedBarriers() throws {
        let lines = """
        PATH SUMMARY
        Image Dist.(Ang.) E(Eh) dE(kcal/mol) max RMS
        0 0.0 -10.00 0.00 0 0
        1 1.0 -9.80 125.50 0 0 <= CI
        2 2.0 -9.95 31.38 0 0

        THE TS OPTIMIZATION HAS CONVERGED
        PATH SUMMARY FOR NEB-TS
        All forces in Eh/Bohr.
        Image E(Eh) dE(kcal/mol) max RMS
        0 -10.00000 0.00 0 0
        1 -9.80000 125.50 0 0 <= CI
        TS -9.85000 94.13 0 0 <= TS
        2 -9.95000 31.38 0 0
        ----------
        """.components(separatedBy: "\n")
        let profile = ORCANEBParser.parse(lines: lines)!
        XCTAssertEqual(profile.images.count, 4)
        XCTAssertTrue(profile.isNEBTS && profile.tsConverged)
        XCTAssertEqual(profile.forwardBarrierKcal!, 94.13, accuracy: 1e-8)
        XCTAssertEqual(profile.reverseBarrierKcal!, 62.75, accuracy: 1e-8)
        XCTAssertEqual(profile.reactionEnergyKcal, 31.38, accuracy: 1e-8)
        XCTAssertEqual(profile.transitionState!.energyHartree, -9.85, accuracy: 1e-10)
        XCTAssertTrue(profile.images[1].isClimbingImage && !profile.images[1].isTransitionState)
        XCTAssertTrue(profile.sourceLine > 5)
        XCTAssertTrue(ORCANEBParser.parse(lines: lines + ["PATH SUMMARY FOR NEB-TS", "Image E(Eh) dE(kcal/mol)", "0 -10.0 0.0", "TS invalid 1.0"]) == nil)
    }
    func testNEBPlainSummaryUnitsAndMalformedRows() throws {
        let text = "PATH SUMMARY\nImage Dist.(Ang.) E(Eh) dE(kcal/mol)\n0 0.0 -10.0 0.0\n1 1.0 -9.9 62.75\n2 2.0 -10.1 -62.75\n\n"
        let result = ORCANEBParser.parse(lines: text.components(separatedBy: "\n"))!
        XCTAssertEqual(result.images.count, 3)
        XCTAssertTrue(result.transitionState == nil && result.forwardBarrierKcal == nil)
        XCTAssertEqual(result.product.imageIndex, 2)
        XCTAssertTrue(ORCANEBParser.parse(lines: ("Number of intermediate images .... 2\n" + text).components(separatedBy: "\n")) == nil)
        XCTAssertTrue(ORCANEBParser.parse(lines: text.replacingOccurrences(of: "2 2.0 -10.1 -62.75", with: "bad-coordinate-row").components(separatedBy: "\n")) == nil)
        XCTAssertTrue(ORCANEBParser.parse(lines: text.replacingOccurrences(of: "1 1.0 -9.9", with: "1 1.0 NaN").components(separatedBy: "\n")) == nil)
        XCTAssertTrue(ORCANEBParser.parse(lines: text.replacingOccurrences(of: "2 2.0", with: "3 2.0").components(separatedBy: "\n")) == nil)
    }

    func testElementReplacementPreservesGeometryAndProjectState() throws {
        let atoms = [Atom(id: 0, element: "Fe", position: Vector3(1.2, -3.4, 5.6)),
                     Atom(id: 1, element: "N", position: Vector3(2.7, -3.4, 5.6))]
        let project = try BuildingProject(atoms: atoms, groups: [[0, 1]], selection: [0], charge: 2, multiplicity: 3)
        for input in [" ru ", "44", "Pt", "Og", "X"] {
            let result = try project.replacingElement(at: 0, with: input)
            XCTAssertEqual(result.atoms[0].element, BuildingProject.validatedElement(input))
            XCTAssertEqual(result.atoms.map(\.position), atoms.map(\.position))
            XCTAssertEqual(result.atoms.map(\.id), [0, 1])
            XCTAssertEqual(result.atoms[1], atoms[1])
            XCTAssertEqual(result.groups, [[0, 1]])
            XCTAssertEqual(result.selection, [0])
            XCTAssertEqual(result.charge, 2)
            XCTAssertEqual(result.multiplicity, 3)
        }
        for input in ["", "  ", "Foo", "119", "-1"] {
            XCTAssertTrue(BuildingProject.validatedElement(input) == nil)
            var rejected = false
            do { _ = try project.replacingElement(at: 0, with: input) } catch { rejected = true }
            XCTAssertTrue(rejected)
        }
        var rejectedIndex = false
        do { _ = try project.replacingElement(at: 2, with: "Cu") } catch { rejectedIndex = true }
        XCTAssertTrue(rejectedIndex)
        XCTAssertEqual(project.atoms, atoms)
    }

}
