import AppKit
import ChemCraftCore
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var workspace: WorkspaceStore
    @ObservedObject private var chemistry = ChemistryRuntime.shared
    @ObservedObject private var remote = RemoteConnection.shared

    private let tabs = ["Image", "Abstract", "Source", "Coord", "Image/Abs", "ChemRefine", "Draw"]

    var body: some View {
        VStack(spacing: 0) {
            ClassicMenuBar()
            if let documents = workspace.documents { DocumentTabStrip(documents: documents) }
            if let warnings = workspace.document?.warnings, !warnings.isEmpty {
                HStack { Image(systemName: "info.circle"); Text(warnings.joined(separator: " ")).font(.caption).lineLimit(2); Spacer() }
                    .padding(5).background(Color.yellow.opacity(0.12)).help(warnings.joined(separator: "\n"))
            }
            HStack(spacing: 5) {
                ForEach(tabs, id: \.self) { tab in
                    Button { workspace.activeTab = tab } label: {
                        Text(tab).font(.system(size: 17, weight: workspace.activeTab == tab ? .semibold : .regular))
                            .frame(width: tab == "Image/Abs" ? 115 : 100, height: 31)
                            .background(workspace.activeTab == tab ? Color.white : Color.clear)
                            .overlay(Rectangle().stroke(workspace.activeTab == tab ? Color.accentColor : .clear, lineWidth: 1))
                    }.buttonStyle(.plain)
                }
                Spacer()
            }.padding(.horizontal, 5).padding(.vertical, 4).background(Color(nsColor: .windowBackgroundColor))
            Divider()
            if workspace.activeTab != "Draw" { ScrollView(.horizontal, showsIndicators: false) { classicToolbar } }
            Divider()
            if workspace.isDraggingEnabled && !["ChemRefine", "Draw"].contains(workspace.activeTab) { ManipulationToolbar() }
            if !workspace.buildingHint.isEmpty && !["ChemRefine", "Draw"].contains(workspace.activeTab) {
                HStack {
                    if let element = workspace.pendingElement {
                        Button(element + "…") { workspace.presentPeriodicTable() }.help("Choose another element")
                        Picker("Atom action", selection: $workspace.atomPlacementMode) {
                            ForEach(AtomPlacementMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }.frame(width: 205)
                    }
                    Text(workspace.buildingHint).font(.caption); Spacer(); Button("Fit all") { viewportAction("reset") }; Button("Finish placement") { workspace.clearSelection() } }.padding(6)
            }
            Divider()
            HSplitView {
                if remote.explorerVisible || (workspace.showExplorer && !["ChemRefine", "Draw"].contains(workspace.activeTab)) {
                    VSplitView {
                        if remote.explorerVisible { RemoteExplorerView() }
                        if workspace.showExplorer && !["ChemRefine", "Draw"].contains(workspace.activeTab) { sidebar.frame(minHeight: 160) }
                    }.frame(minWidth: 230, idealWidth: 280, maxWidth: 380)
                }
                tabContent
                if workspace.isBuilderVisible && !["ChemRefine", "Draw"].contains(workspace.activeTab) { BuilderPanel() }
            }
        }
        .preferredColorScheme(.light)
        .background(GeometryNavigationKeys(enabled: !["Source", "Coord", "ChemRefine", "Draw"].contains(workspace.activeTab), step: workspace.stepFrame,
            clear: workspace.clearSelection,
            selectAll: { workspace.selectedAtomIndices = Array(workspace.currentFrame?.atoms.indices ?? 0..<0) })
            .frame(width: 0, height: 0).allowsHitTesting(false))
        .task {
            if CommandLine.arguments.contains(where: { $0.hasSuffix("smoke-test") }) { try? await Task.sleep(nanoseconds: 800_000_000) }
            if CommandLine.arguments.contains("--remote-explorer-smoke-test") { await RemoteExplorerSmokeTest.run(workspace: workspace) }
            if CommandLine.arguments.contains("--remote-tree-smoke-test") { await RemoteTreeSmokeTest.run(workspace: workspace) }
            if CommandLine.arguments.contains("--document-workspace-smoke-test") { await DocumentWorkspaceSmokeTest.run(workspace: workspace) }
            if CommandLine.arguments.contains("--remote-navigation-smoke-test") { await RemoteNavigationSmokeTest.run() }
            if CommandLine.arguments.contains("--remote-session-smoke-test") { await RemoteSessionSmokeTest.run(workspace: workspace) }
            if CommandLine.arguments.contains("--remote-live-smoke-test") { await RemoteLiveSmokeTest.run(workspace: workspace) }
            if CommandLine.arguments.contains("--remote-connection-smoke-test") { await RemoteConnectionSmokeTest.run(workspace: workspace) }
            if CommandLine.arguments.contains("--workflow-runner-smoke-test") { await Task { @MainActor in await WorkflowRunnerSmokeTest.run(workspace: workspace) }.value }
            if CommandLine.arguments.contains("--drawing-labels-smoke-test") { await DrawingAndLabelsSmokeTest.run(workspace: workspace) }
            if CommandLine.arguments.contains("--atom-editing-smoke-test") { await AtomEditingSmokeTest.run(workspace: workspace) }
            if CommandLine.arguments.contains("--fragment-placement-smoke-test") { await FragmentPlacementSmokeTest.run(workspace: workspace) }
            if CommandLine.arguments.contains("--builder-chemistry-smoke-test") { await BuilderChemistrySmokeTest.run(workspace: workspace) }
            if CommandLine.arguments.contains("--neb-smoke-test") { await NEBSmokeTest.run(workspace: workspace) }
            if CommandLine.arguments.contains("--merge-smoke-test") { await MergeSmokeTest.run(workspace: workspace) }
            if CommandLine.arguments.contains("--animation-smoke-test") { await AnimationSmokeTest.run(workspace: workspace) }
            if CommandLine.arguments.contains("--smooth-smoke-test") { await SmoothInteractionSmokeTest.run(workspace: workspace) }
            if CommandLine.arguments.contains("--render-benchmark") { await RenderBenchmark.run(workspace: workspace) }
            if CommandLine.arguments.contains("--manipulation-smoke-test") { await ManipulationSmokeTest.run(workspace: workspace) }
            if CommandLine.arguments.contains("--energy-smoke-test") { await EnergyWorkflowSmokeTest.run(workspace: workspace) }
            if CommandLine.arguments.contains("--smoke-test") { await AppSmokeTest.run(workspace: workspace) }
        }
        .fileImporter(
            isPresented: $workspace.isImporterPresented,
            allowedContentTypes: [.plainText, .data],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                for url in urls { if let documents = workspace.documents { documents.open(url) } else { workspace.open(url) } }
            case .failure(let error):
                workspace.errorMessage = error.localizedDescription
            }
        }
        .fileExporter(
            isPresented: $workspace.isExporterPresented,
            document: workspace.exportDocument,
            contentType: UTType(filenameExtension: "xyz") ?? .plainText,
            defaultFilename: "geometry.xyz"
        ) { result in
            if case .failure(let error) = result {
                workspace.errorMessage = error.localizedDescription
            }
        }
        .onOpenURL { url in
            if let documents = workspace.documents { documents.open(url) } else { workspace.open(url) }
        }
        .alert("ChemViewer error", isPresented: Binding(
            get: { workspace.errorMessage != nil },
            set: { if !$0 { workspace.errorMessage = nil } }
        )) {
            Button("OK") { workspace.errorMessage = nil }
        } message: {
            Text(workspace.errorMessage ?? "Unknown error")
        }
        .sheet(isPresented: $remote.presented) { RemoteConnectionView().environmentObject(workspace) }
        .sheet(isPresented: $workspace.isPeriodicTablePresented) { PeriodicTableView() }
        .sheet(isPresented: $workspace.isFragmentLibraryPresented) { FragmentBrowserView() }
        .sheet(isPresented: $workspace.isAnimationExportPresented) { AnimationExportView() }
        .sheet(isPresented: $workspace.isEnergyLandscapePresented) {
            EnergyLandscapeView()
        }
        .sheet(isPresented: $workspace.isSpectrumPresented) {
            if let modes = workspace.document?.vibrationalModes {
                SpectrumView(modes: modes)
                    .frame(minWidth: 760, minHeight: 480)
            }
        }
        .sheet(isPresented: $workspace.isCoordinateEditorPresented) {
            if let frame = workspace.currentFrame {
                CoordinateEditorView(frame: frame) { atoms in
                    workspace.replaceCurrentAtoms(atoms)
                }
            }
        }
    }

    private func viewportAction(_ action: String) {
        NotificationCenter.default.post(name: .init("ChemViewerViewportAction"), object: action)
    }

    private func tool(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).frame(width: 23, height: 23) }
            .buttonStyle(ClassicButtonStyle()).controlSize(.small).help(title).accessibilityLabel(title)
    }

    private var classicToolbar: some View {
        HStack(spacing: 5) {
            tool("Open chemistry file", "folder") { workspace.isImporterPresented = true }
            tool("Export PNG image", "camera") {
                workspace.activeTab = "Image"
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { viewportAction("export") }
            }.disabled(workspace.currentFrame == nil)
            Divider().frame(height: 24)
            Menu("Build") {
                Button("Fragment Library…") { workspace.presentFragmentLibrary() }
                Button("Add Atom…") { workspace.presentPeriodicTable() }
                Toggle("Build & Edit Panel", isOn: $workspace.isBuilderVisible)
            }.fixedSize()
            tool("Fragment library", "plus") { workspace.presentFragmentLibrary() }
            tool("Add atom / replace element", "atom") { workspace.presentPeriodicTable() }
            tool("Toggle dragging", "hand.point.up.fill") { workspace.isDraggingEnabled.toggle() }
            tool("Select connected molecule", "globe") { workspace.selectConnectedGroup() }
            Button("H") { workspace.showHydrogens.toggle() }.buttonStyle(ClassicButtonStyle()).help("Toggle hydrogen visibility")
            ForEach([(AtomCaption.numbers, "1"), (.elements, "C1"), (.elementNumbers, "A"), (.none, "●")], id: \.0) { caption, title in
                Button(title) { workspace.atomCaption = caption }.buttonStyle(ClassicButtonStyle()).help(caption.rawValue)
            }
            tool("Show result explorer", "sidebar.left") { workspace.showExplorer.toggle() }
            tool("Fit and center molecule", "arrow.up.left.and.arrow.down.right") { viewportAction("reset") }
            tool("Undo coordinate edit", "arrow.uturn.backward") { workspace.undoGeometry() }
                .disabled(!workspace.canUndoGeometry)
            tool("Redo coordinate edit", "arrow.uturn.forward") { workspace.redoGeometry() }.disabled(!workspace.canRedoGeometry)
            tool("Export XYZ coordinates", "square.and.arrow.down") { workspace.requestXYZExport() }
                .disabled(workspace.currentFrame == nil)
            Divider().frame(height: 24)
            tool(workspace.isVibrating ? "Pause frequency" : "Animate frequency", workspace.isVibrating ? "pause.fill" : "play.fill") { workspace.isVibrating.toggle() }
                .disabled(workspace.selectedMode == nil)
            Toggle("Vectors", isOn: $workspace.showDisplacementVectors).toggleStyle(.checkbox)
                .disabled(workspace.selectedMode == nil)
            tool("Play or pause geometries", "film") { workspace.toggleTrajectoryPlayback() }
                .disabled((workspace.document?.frames.count ?? 0) < 2)
            tool("Export trajectory or frequency GIF", "photo.on.rectangle.angled") { workspace.presentAnimationExport() }
                .disabled(workspace.currentFrame == nil)
            tool("Energy landscape", "chart.xyaxis.line") { workspace.isEnergyLandscapePresented = true }
                .disabled((workspace.document?.frames.count ?? 0) < 2 && workspace.document?.nebProfile == nil)
            tool("IR spectrum", "waveform.path") { workspace.isSpectrumPresented = true }
                .disabled(!(workspace.document?.vibrationalModes.contains { $0.infraredIntensity != nil } ?? false))
            Picker("Display", selection: $workspace.renderingStyle) {
                ForEach(MolecularStyle.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.labelsHidden().frame(width: 135)
            Spacer()
            Text("ChemViewer").font(.caption).foregroundStyle(.secondary)
        }.padding(.horizontal, 8).padding(.vertical, 5).background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder private var tabContent: some View {
        switch workspace.activeTab {
        case "Draw": DrawView(drawing: workspace.drawing)
        case "ChemRefine": LocalWorkflowView(embedded: true)
        case "Abstract": abstractPanel
        case "Source": SourceTextView(text: workspace.sourceText, focusLine: workspace.sourceFocusLine)
        case "Coord":
            if let frame = workspace.currentFrame {
                CoordinateEditorView(frame: frame, embedded: true) { workspace.replaceCurrentAtoms($0) }
                    .id("\(workspace.frameIndex)-\(workspace.geometryRevision)")
            } else { Text("Open a structure to edit coordinates.").frame(maxWidth: .infinity, maxHeight: .infinity) }
        case "Image/Abs":
            HSplitView { mainPanel; abstractPanel.frame(minWidth: 280, idealWidth: 340) }
        default: mainPanel
        }
    }

    private var abstractPanel: some View {
        CalculationAbstractView(showStructure: workspace.activeTab == "Abstract")
    }

    @ViewBuilder
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let document = workspace.document {
                Text(document.title)
                    .font(.headline)
                    .lineLimit(2)
                    .padding()
                Divider()
                ScrollViewReader { proxy in
                List {
                    Section("Geometries") {
                        ForEach(Array(document.frames.enumerated()), id: \.offset) { index, frame in
                            Button {
                                workspace.selectFrame(index)
                            } label: {
                                HStack {
                                    Image(systemName: workspace.frameIndex == index ? "circle.inset.filled" : "circle")
                                    Text("Geometry \(index + 1)")
                                    Spacer()
                                    if let energy = frame.energyHartree {
                                        Text(energy, format: .number.precision(.fractionLength(6)))
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .id("geometry-\(index)")
                            .listRowBackground(workspace.frameIndex == index ? Color.accentColor.opacity(0.12) : Color.clear)
                        }
                    }
                    if !workspace.availableModes.isEmpty {
                        Section("Frequencies (cm⁻¹)") {
                            ForEach(workspace.availableModes) { mode in
                                Button {
                                    workspace.selectMode(mode.index)
                                } label: {
                                    HStack {
                                        Image(systemName: workspace.selectedModeIndex == mode.index ? "waveform.circle.fill" : "waveform.circle")
                                        Text("Mode \(mode.index)")
                                        Spacer()
                                        Text(mode.frequencyCM1, format: .number.precision(.fractionLength(2)))
                                            .monospacedDigit()
                                            .foregroundStyle(mode.isImaginary ? Color.red : Color.primary)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .onAppear { proxy.scrollTo("geometry-\(workspace.frameIndex)", anchor: .center) }
                .onChange(of: workspace.frameIndex) { index in proxy.scrollTo("geometry-\(index)", anchor: .center) }
                }
                HStack {
                    Button { workspace.stepFrame(-1) } label: { Image(systemName: "chevron.up") }
                        .disabled(workspace.frameIndex == 0)
                    Text("\(workspace.frameIndex + 1) / \(document.frames.count)").monospacedDigit()
                    Button { workspace.stepFrame(1) } label: { Image(systemName: "chevron.down") }
                        .disabled(workspace.frameIndex + 1 >= document.frames.count)
                    Spacer()
                    Text("Arrow keys").font(.caption).foregroundStyle(.secondary)
                }.padding(8)
                if !document.warnings.isEmpty {
                    Divider()
                    ForEach(document.warnings, id: \.self) { warning in
                        Label(warning, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .padding(.horizontal)
                            .padding(.vertical, 4)
                    }
                }
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "atom")
                        .font(.system(size: 42))
                        .foregroundStyle(.secondary)
                    Text("No calculation open")
                        .font(.headline)
                    Text("Open an XYZ or ORCA output file.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            }
        }
    }

    @ViewBuilder
    private var mainPanel: some View {
        if workspace.isLoading {
            ProgressView("Parsing calculation…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let document = workspace.document,
                  document.frames.indices.contains(workspace.frameIndex) {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                MoleculeMetalView(
                    frame: document.frames[workspace.frameIndex],
                    mode: workspace.selectedMode,
                    isAnimating: workspace.isVibrating,
                    amplitude: workspace.vibrationAmplitude,
                    showDisplacementVectors: workspace.showDisplacementVectors,
                    style: workspace.renderingStyle,
                    showHydrogens: workspace.showHydrogens, atomCaption: workspace.atomCaption, vibrationSpeed: workspace.vibrationSpeed,
                    selectedAtomIndices: $workspace.selectedAtomIndices,
                    showMeasurementOverlay: workspace.showMeasurementOverlay, measurementSelections: workspace.pinnedMeasurementSelections,
                    draggingEnabled: workspace.isDraggingEnabled, dragAxis: workspace.dragAxis,
                    onEmptyBuilderClick: workspace.placeBuilderItem(inEmptySpace:),
                    onBuilderClick: workspace.placeBuilderItem,
                    onClearSelection: workspace.clearSelection,
                    onManipulationSelection: { _ = workspace.selectManipulationSeed($0) },
                    onBeginAtomDrag: workspace.beginAtomDrag,
                    onDragAtomIndices: { workspace.manipulationIndices },
                    onPreviewAtomDrag: workspace.previewAtomDrag,
                    onFinishAtomDrag: workspace.finishAtomDrag,
                    onRenderingFailure: { workspace.errorMessage = $0 },
                    documentID: workspace.documentIdentity, viewportEpoch: workspace.viewportEpoch, viewportState: workspace.viewportState,
                    onSaveViewportState: { [workspace, epoch = workspace.viewportEpoch] state in if workspace.viewportEpoch == epoch { workspace.viewportState = state } }
                )
                Divider()
                VStack(spacing: 7) {
                    tool("Rotate left", "arrow.counterclockwise") { viewportAction("left") }
                    tool("Rotate right", "arrow.clockwise") { viewportAction("right") }
                    tool("Rotate up", "arrow.up") { viewportAction("up") }
                    tool("Rotate down", "arrow.down") { viewportAction("down") }
                    Divider()
                    tool("Roll left", "rotate.left") { viewportAction("rollLeft") }
                    tool("Roll right", "rotate.right") { viewportAction("rollRight") }
                    tool("Pan up", "arrow.up.to.line") { viewportAction("panUp") }
                    tool("Pan down", "arrow.down.to.line") { viewportAction("panDown") }
                    tool("Zoom in", "plus.magnifyingglass") { viewportAction("in") }
                    tool("Zoom out", "minus.magnifyingglass") { viewportAction("out") }
                    tool("Fit and center", "scope") { viewportAction("reset") }
                    Spacer()
                }.padding(5).frame(width: 37).background(Color(nsColor: .windowBackgroundColor))
                }
                Divider()
                // Reserve a stable inspector area: selecting atoms must not resize the camera viewport.
                GeometryReader { area in
                    ScrollView([.horizontal, .vertical]) {
                        SelectionInspector().frame(width: max(560, area.size.width), alignment: .leading)
                    }
                }.frame(height: 140)
                Divider()
                statusBar(document).frame(height: 30)
            }
        } else {
            VStack(spacing: 16) {
                Image(systemName: "atom")
                    .font(.system(size: 72))
                    .foregroundStyle(.secondary)
                Text("ChemViewer")
                    .font(.largeTitle)
                Text("Molecular structures and ORCA calculations")
                    .foregroundStyle(.secondary)
                Button("New molecule / Build fragments") { workspace.newMolecule(); workspace.presentFragmentLibrary() }.buttonStyle(.bordered)
                Button("Open chemistry file…") { workspace.isImporterPresented = true }
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func statusBar(_ document: ParsedDocument) -> some View {
        HStack(spacing: 8) {
            Button("Set") { workspace.isBuilderVisible = true }.buttonStyle(ClassicButtonStyle())
            Button("Show") { workspace.showExplorer.toggle() }.buttonStyle(ClassicButtonStyle())
            Button("↔") { workspace.translateManipulation(axis: Vector3(1, 0, 0), sign: -1) }.buttonStyle(ClassicButtonStyle()).disabled(!workspace.isDraggingEnabled)
            Button("→") { workspace.translateManipulation(axis: Vector3(1, 0, 0), sign: 1) }.buttonStyle(ClassicButtonStyle()).disabled(!workspace.isDraggingEnabled)
            Text(document.sourceFormat)
            Text("Frame \(workspace.frameIndex + 1)/\(document.frames.count)")
            Text("\(document.frames[workspace.frameIndex].atoms.count) atoms")
            if !workspace.selectedAtomIndices.isEmpty {
                Divider().frame(height: 18)
                Text(selectionSummary(for: document.frames[workspace.frameIndex]))
                    .monospacedDigit()
            }
            if let mode = workspace.selectedMode {
                Divider().frame(height: 18)
                Text("Mode \(mode.index): \(mode.frequencyCM1, specifier: "%.2f") cm⁻¹")
                    .foregroundStyle(mode.isImaginary ? Color.red : Color.primary)
                Toggle("Animate", isOn: $workspace.isVibrating)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                Slider(value: $workspace.vibrationAmplitude, in: 0.05...2.0) {
                    Text("Amplitude")
                }
                .frame(width: 140)
            }
            Spacer()
            Text(workspace.isDraggingEnabled ? "Drag \(workspace.dragScope.rawValue.lowercased()) • right-click clears" : "Drag to rotate • Option-drag to pan • right-click clears • scroll to zoom")
                .lineLimit(1).truncationMode(.tail).layoutPriority(-1)
                .help("Drag to rotate • Option-drag to pan • right-click clears • scroll to zoom")
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func selectionSummary(for frame: MoleculeFrame) -> String {
        let indices = workspace.selectedAtomIndices.filter(frame.atoms.indices.contains)
        let atoms = indices.map { "\(frame.atoms[$0].element)\($0 + 1)" }.joined(separator: ", ")
        do {
            switch indices.count {
            case 2:
                let value = try GeometryEditor.distance(
                    in: frame, firstAtomIndex: indices[0], secondAtomIndex: indices[1]
                )
                return "\(atoms)  d = \(value.formatted(.number.precision(.fractionLength(5)))) Å"
            case 3:
                let value = try GeometryEditor.angleDegrees(
                    in: frame,
                    firstAtomIndex: indices[0],
                    vertexAtomIndex: indices[1],
                    thirdAtomIndex: indices[2]
                )
                return "\(atoms)  angle = \(value.formatted(.number.precision(.fractionLength(3))))°"
            case 4:
                let value = try GeometryEditor.dihedralDegrees(
                    in: frame,
                    firstAtomIndex: indices[0],
                    secondAtomIndex: indices[1],
                    thirdAtomIndex: indices[2],
                    fourthAtomIndex: indices[3]
                )
                return "\(atoms)  dihedral = \(value.formatted(.number.precision(.fractionLength(3))))°"
            default:
                return indices.count > 4 ? "\(indices.count) atoms selected" : "\(indices.count) selected: \(atoms)"
            }
        } catch {
            return indices.count > 4 ? "\(indices.count) atoms selected" : "\(indices.count) selected: \(atoms)"
        }
    }
}

struct XYZExportDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [UTType(filenameExtension: "xyz") ?? .plainText]
    }

    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.text = text
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

/// AppKit text storage keeps large calculation source files selectable without
/// constructing a SwiftUI view for every output line.
struct SourceTextView: NSViewRepresentable {
    let text: String
    var focusLine: Int? = nil
    final class Coordinator { var focusedLine: Int? }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
        let view = NSTextView(frame: scroll.bounds)
        view.isRichText = false; view.usesFindPanel = true
        view.minSize = .zero
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.isEditable = false; view.isSelectable = true
        view.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        view.textContainerInset = NSSize(width: 12, height: 12)
        view.autoresizingMask = [.width]; view.isVerticallyResizable = true
        scroll.documentView = view
        return scroll
    }
    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        (scroll.documentView as? NSTextView)?.string = ""
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? NSTextView else { return }
        let source = text as NSString
        var focusStart = 0
        if let focusLine {
            for _ in 1..<max(1, focusLine) {
                guard focusStart < source.length else { break }
                focusStart = NSMaxRange(source.lineRange(for: NSRange(location: focusStart, length: 0)))
            }
        }
        let limit = 2_000_000
        var offset = source.length > limit && focusStart > limit ? max(0, focusStart - limit / 2) : 0
        if offset > 0 { offset = source.lineRange(for: NSRange(location: offset, length: 0)).location }
        let length = min(limit, source.length - offset)
        let notice = source.length > limit ? "[Source preview excerpt; original text retained. Starts at UTF-16 offset \(offset).]\n" : ""
        let displayed = notice + source.substring(with: NSRange(location: offset, length: length))
        if view.string != displayed { view.string = displayed; view.sizeToFit(); context.coordinator.focusedLine = nil }
        if let focusLine, focusLine != context.coordinator.focusedLine {
            context.coordinator.focusedLine = focusLine
            guard focusStart < source.length, focusStart >= offset, focusStart < offset + length else { return }
            let line = source.lineRange(for: NSRange(location: focusStart, length: 0))
            let range = NSRange(location: (notice as NSString).length + line.location - offset, length: min(line.length, offset + length - line.location))
            view.setSelectedRange(range)
            DispatchQueue.main.async { view.scrollRangeToVisible(range) }
        }
    }
}
