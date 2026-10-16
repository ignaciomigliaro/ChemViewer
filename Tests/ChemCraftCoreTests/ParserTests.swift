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
}
