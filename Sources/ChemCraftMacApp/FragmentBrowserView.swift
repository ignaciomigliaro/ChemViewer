import AppKit
import ChemCraftCore
import SwiftUI

@MainActor
enum FragmentThumbnails {
    private static let cache = NSCache<NSString, NSImage>()
    private static let renderer = MolecularMTKView()
    private static var revision = 0
    static func image(for item: LibraryFragment) -> NSImage? {
        if let cached = cache.object(forKey: item.id as NSString) { return cached }
        let frame = MoleculeFrame(id: 0, atoms: item.geometry)
        revision += 1
        renderer.scene = RenderScene(atoms: frame.atoms, bonds: BondBuilder.inferBonds(atoms: frame.atoms), displacements: [], amplitude: 0, animate: false, showDisplacementVectors: false, selectedAtomIndices: [], geometryID: revision)
        guard let cg = try? renderer.renderAnimationFrame(frame, positions: frame.atoms.map { SIMD3<Float>($0.position.x, $0.position.y, $0.position.z) }, size: 192) else { return nil }
        let image = NSImage(cgImage: cg, size: NSSize(width: 192, height: 192))
        cache.totalCostLimit = 16 * 1024 * 1024
        cache.setObject(image, forKey: item.id as NSString, cost: 192 * 192 * 4)
        return image
    }
}

struct FragmentBrowserView: View {
    @EnvironmentObject private var workspace: WorkspaceStore
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var category = "All"
    private var matches: [LibraryFragment] {
        LibraryFragment.catalog.filter { (category == "All" || $0.category == category) && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)) }
    }
    var body: some View {
        VStack(spacing: 12) {
            HStack { Text("Fragment library").font(.title2.bold()); Spacer(); Text("\(matches.count) structures").foregroundStyle(.secondary); Button("Close") { dismiss() } }
            HStack {
                TextField("Search fragments, ligands or metal centers", text: $search).textFieldStyle(.roundedBorder)
                Picker("Category", selection: $category) {
                    Text("All").tag("All")
                    ForEach(Array(Set(LibraryFragment.catalog.map(\.category))).sorted(), id: \.self) { Text($0).tag($0) }
                }.frame(width: 250)
            }
            Text("Choose a structure, then left-click empty space to place it or an atom to attach it. Right-click finishes.").font(.callout).frame(maxWidth: .infinity, alignment: .leading)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 155, maximum: 210), spacing: 12)], spacing: 12) {
                    ForEach(matches) { item in
                        FragmentPreviewCard(item: item) {
                            workspace.armFragment(item); workspace.isFragmentLibraryPresented = false; dismiss()
                        }
                    }
                }.padding(4)
            }
        }.padding(18).frame(minWidth: 850, idealWidth: 1000, minHeight: 600, idealHeight: 720)
            .background(Color(nsColor: .windowBackgroundColor))
    }
}
private struct FragmentPreviewCard: View {
    let item: LibraryFragment
    let choose: () -> Void
    @State private var image: NSImage?
    @State private var ready = false
    var body: some View {
        Button(action: choose) {
            VStack(spacing: 5) {
                ZStack {
                    Color.white
                    if let image { Image(nsImage: image).resizable().scaledToFit() }
                    else if !ready { ProgressView().controlSize(.small) }
                    else { Image(systemName: "atom").font(.largeTitle).foregroundStyle(.secondary) }
                }.frame(height: 130)
                Text(item.name).font(.callout.bold()).lineLimit(2).frame(height: 34)
                Text(item.category).font(.caption).foregroundStyle(.secondary)
            }.padding(8).frame(maxWidth: .infinity)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.3)))
        }.buttonStyle(.plain)
            .help("Place \(item.name)")
            .task(id: item.id) {
                await Task.yield()
                guard !Task.isCancelled else { return }
                image = FragmentThumbnails.image(for: item); ready = true
            }
    }
}
