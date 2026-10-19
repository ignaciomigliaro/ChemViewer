# ChemViewer 0.7.0 — unified app

ChemViewer is the maintained app and project. The earlier MoleculeView 0.3 implementation (local commit 07968ae) was compared at source level and merged; no vendor binary, assets or recovered proprietary source were copied. The active project remains `/Users/nacho/Documents/software/ChemViewer`, installed as `~/Applications/ChemViewer.app`.

## Feature reconciliation

| Earlier MoleculeView capability | Unified ChemViewer implementation |
| --- | --- |
| Chemcraft-inspired menu strip, tabs, beveled controls, white canvas, right camera rail and footer | ClassicMenuBar/ClassicButtonStyle, Image/Abstract/Source/Coord/Image-Abs tabs, compact scrollable toolbar, Set/Show/translation footer, camera roll/pan/rotation/zoom/fit |
| Optional right builder inspector | + toolbar button, Edit → Build & Edit, View → Build & Edit Panel, Cmd-B; hidden initially |
| Geometry/mode/amplitude/speed inspector | BuilderPanel calculation controls, existing optional result explorer and arrow navigation; live cycles/s slider |
| Seven fragment templates | Water, Methane, Ammonia, Methyl, Carbonyl, Benzene, Ethylene; original approximate coordinates retained |
| Imported XYZ fragment and explicit leaving site | Import XYZ, choose H/X leaving site, add or attach |
| Attachment replacing terminal H/X at both ends | Original rigid alignment, heavy-atom anchor checks, initial covalent-radius bond length; selected inserted group |
| Insert/replace element, duplicate/delete atoms | Builder panel and menus; topology-changing edits invalidate calculated energies and modes |
| Numeric 1-based selection/ranges, All, Connected, imported Fragment | Builder selection controls; ordered selection and unlimited click toggling from ChemViewer retained |
| Rigid translate/rotate on X/Y/Z or saved bond axis; center/first/origin pivots | Builder move/rotate controls, Set bond axis; existing mouse drag scopes and ±axis controls retained |
| Snapshot history and redo | Bounded 100-entry per-frame snapshot history including geometry, groups, selection, charge/multiplicity and edited status; redo for all geometry edits |
| Saved projects and legacy .mvproject loading | Save .cvproject; compatible JSON reader for .mvproject and .cvproject; saves working geometry/groups/selection/charge/multiplicity, not original outputs/modes |
| XYZ and ORCA geometry export | Existing XYZ export retained; dummy/empty chemistry export rejected; explicit ORCA `* xyz charge multiplicity` export (not a complete input deck) |
| ORCA charge/multiplicity, keywords, convergence/termination and thermochemical facts with source links | Original fact extraction supplements the existing clean numeric Abstract in collapsed Output details; editable export charge/multiplicity initialized from printed facts, otherwise visible 0/1 defaults |
| Compound-job per-geometry modes | Earlier complete mode tables supplement ChemViewer's existing final-mode parser; selecting another geometry exposes its own earlier modes without attaching vectors to later geometries |
| Gaussian Input/Standard orientation geometry reading | ParserRegistry fallback through the integrated independent parser; no Gaussian vibrational/energy support is implied |
| Atom numbers/elements/both and hydrogen hiding | H / 1 / C1 / A / ● toolbar controls and Display menu; labels/projected positions share the current native camera; hidden atoms omitted from picking, bonds and captions |
| Camera ±X/±Y/±Z, vertical pan | Existing yaw/pitch plus new roll/pan rail controls; full camera rotation copied to GIF renderer |
| Bounded file/project/source preview and spatial bond search | 100 MB input, 10 MB project, 10,000 atoms/frame, 2,000 frames/500,000 aggregate atoms; 2M UTF-16 source excerpt with original retained and source-jump recentering; bounded cell search using existing ChemViewer bond thresholds |
| Original tests and feature evidence | Tests/IntegratedBuilding, synthetic fixtures and docs/integrated-moleculeview; check-building.sh runs the original parser/editing/state suites during every packaged build |

## ChemViewer capabilities preserved

The renderer remains native instanced Metal, with the xyzrender-derived Paton palette/gradients, distance-independent colors, all prior styles and MSAA/depth. Existing SCF/geometry energies, thermochemistry/correction sums, clean numeric copying, coordinate editing/copying, source links, Matplotlib publication exports, IR plotting, arrow browsing, unlimited ordered selection, bond/angle editing, signed-dihedral readout, measurement guides, atom/fragment/molecule mouse dragging, per-gesture undo, PNG export and annotated trajectory/frequency GIFs remain in the app. GIF speed choices, current viewing angle, no fog, per-frame measurement labels and fixed animation framing are retained. Hydrogen visibility and atom captions also carry through image/GIF export.

## Architecture and limits

The original parser/building/project algorithms are namespaced in `ChemCraftCore/IntegratedBuilding.swift`, accessed through `BuildingProject`. This avoids replacing the newer ORCA/thermochemistry logic. All scientific geometry/project logic stays in the core target. `WorkspaceStore` now keeps atomic geometry/group/selection history snapshots and per-frame mode/group state. The UI uses SwiftUI/AppKit classic controls around the same Metal view rather than embedding the older SceneKit renderer.

The two original apps were both partial Chemcraft replacements. Combining their implemented features does not supply unimplemented force fields, arbitrary bond orders, orbital surfaces, constraints, full Gaussian parsing or other missing Chemcraft functions. Fragment structures remain initial approximations, not optimized geometries. The builder uses Float coordinates through ChemViewer's established model; original source values remain in source text. JSON legacy coordinates are converted to that model. Projects preserve a working geometry rather than an entire calculation session. Spatial bond inference caps comparisons at 2M and bonds at 30k for pathological dense inputs and can omit connectivity; it is a visualization heuristic.

The classic layout is adapted to the current app: optional explorer on the left, optional builder on the right, existing measurement inspector below the canvas, native menus plus the in-window menu strip. Controls overflowing the compact toolbar are horizontally scrollable; all exports remain in menus. This is an implemented layout adaptation, not a claim of pixel-identical Chemcraft/MoleculeView rendering or complete manual GUI acceptance.

## Verification and retirement

The build invokes the existing standalone core assertion adaptation when XCTest is unavailable, plus the migrated parser/editing/project suites. Full Xcode CI retains real XCTest. Packaged native checks include `--merge-smoke-test` plus the existing base, energy, manipulation, smooth-interaction and animation checks. The merge check exercises actual workspace operations and live Metal/SwiftUI controls, legacy project reopening, groups, topology history, saved bond-axis rotation, export metadata, captions and H visibility. Numeric fixtures check ethane's 1.52 Å attachment length, project index remapping, 90° transform results and Gaussian coordinates; spatial inference is compared to an independent all-pairs oracle.

After successful verification the old Downloads/MoleculeView folder and its app/build copies are moved together to a recoverable Trash location, with a separate source-only migration backup (including Git history) under Downloads/chemviewer-migration-backups. The old finished background worker is not running. No user calculation files or Chemcraft installations are removed. Final paths and check results are recorded in the handoff.

## 0.7.0 final verification and retirement outcome

23 core assertion methods passed using the explicit standalone runner; all three migrated original parser/editing/state suites passed. All six packaged native workflows passed: merge, base, energy, manipulation, smooth interaction and annotated/slow GIF export. The installed signed arm64 app independently passed the merge check after retirement of the old source folder. `swift test` was attempted before/after; both remain unavailable because this host lacks XCTest/full Xcode (this is not reported as XCTest passing). `git diff --check` passes. No commit/push was performed.

Installed: `/Users/nacho/Applications/ChemViewer.app`, version 0.7.0 (build 9). Active source: `/Users/nacho/Documents/software/ChemViewer`. Old `/Users/nacho/Downloads/MoleculeView` and both app copies were moved together to `/Users/nacho/.Trash/MoleculeView-retired-2026-10-19`; no MoleculeView.app remains in the searched active Downloads/Applications locations. No old app was running and its historical worker had finished. Recoverable source-only tar and verified complete Git bundle are in `/Users/nacho/Downloads/chemviewer-migration-backups`, with SHA256 manifest. User calculation inputs and Chemcraft installations were left untouched.

Native evidence/logs are in `/Users/nacho/Downloads/chemviewer-merge-work`. Actual window-server screenshot capture was unavailable (`could not create image from window`). `merged-layout-offscreen.png` caches the real SwiftUI controls but cannot capture the Metal layer (it appears black); `merged-molecule.png` is the separate real GPU output and renders white correctly. These were inspected separately and are not described as a desktop screenshot. Full human GUI ergonomics and broad real-calculation coverage remain pending.
