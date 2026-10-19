# ChemViewer 0.6.0 — Paton appearance and animated GIFs

The native renderer defaults to **xyzrender · Paton**. The toolbar Display picker and Display → Drawing Style retain Publication, Soft spheres, Large spheres and Sticks. This is a native Metal adaptation, not the xyzrender Python/SVG engine or a promise of pixel-identical SVG output. Paton uses the upstream CPK table with exact C #D9D9D9, H #FAFAFA and N #7F7FBF overrides; 2.5 × .075 display radii, hydrogen .6 scaling, thin black silhouettes, upper-left HLS radial gradients (.15 hue/.1 lightness/.1 saturation shifts), white background, single black bonds, and quadratic depth fog (1 Å near exclusion, strength 1, cap .7). Common-element display VdW radii are tabulated; other elements use xyzrender's 1.5 Å fallback. Bond perception still uses ChemViewer's covalent-distance inference, not xyzgraph.

Reference: https://github.com/aligfellow/xyzrender at locally inspected revision 828e721e40b18f1944c87f949ce224af812dc649. The MIT license is retained in docs/third-party/xyzrender-LICENSE.txt and the installed app. The native HLS gradient and CPK table adapt that licensed implementation. Remaining Metal depth/lighting, fog legibility and contour rasterization differences mean the two engines may differ visually.

## Use

1. Open a multi-frame XYZ or ORCA output. Rotate the molecule to the desired angle in Image or Image/Abs.
2. Choose File → Export Animation as GIF… or the animation-export toolbar button.
3. Choose Geometry trajectory, or select a normal mode first and choose Selected frequency. Select appearance, image size and frame rate; optionally enable forward/backward trajectory playback.
4. Save GIF. Progress and cancellation appear in the sheet. A frequency exports one seamless sinusoidal cycle, using the viewer's displacement amplitude. Its playback rate is illustrative rather than a physical vibrational period.

GIF export copies the **active viewport's yaw and pitch** into a separate Metal renderer. It never imposes a new view orientation. A single center/scale fits the whole trajectory or the frequency's positive/negative displacement envelope; it remains fixed across all exported frames. Pan and zoom are replaced by that fit. Export is square (256–1024 px), white, continuously looping, and omits selection highlights, measurement guides and vectors. The visible document, selection, camera and animation phase are untouched.

Trajectory coordinates are used in file order without interpolation. Ping-pong omits duplicated endpoints. Frequencies require a complete normal-mode displacement set and the unedited mode-source geometry. Negative frequencies are retained. GIF export permits 2–2,000 frames at 1–50 fps internally (UI offers 5/10/12/20/25/30 fps). Larger trajectories currently require an externally reduced file. No energy values, geometry coordinates or source data are changed by exporting.

Frames render to independent MSAA/depth textures using the viewer's existing instanced meshes and shaders. BGRA readback becomes an sRGB CGImage. A serial ImageIO actor encodes frames away from the AppKit event loop; only one explicit readback image is held by the caller at a time. ImageIO's internal GIF memory use is not bounded by this guarantee. GPU submission/readback occurs on the main actor, with a yield between frames. Cancellation preserves an existing destination and removes the temporary sibling file; final replacement happens only after successful finalization.

## Validation

`bash scripts/build-macos.sh` runs 19 core assertion methods through the standalone runner (XCTest remains unavailable under Command Line Tools), builds arm64 and verifies the signed package. Opt-in packaged GUI check:

```
open -W -n -a dist/ChemViewer.app Tests/fixtures/water.xyz --args --animation-smoke-test --animation-evidence /tmp/chemviewer-animation -ApplePersistenceIgnoreState YES
```

The check rotates a live viewport with mouse handlers, compares the copied camera matrices through both export-renderer stages, verifies Paton palette/default and all five appearance renders, independently reopens trajectory and frequency GIFs with ImageIO, checks count/dimensions/frame timing/loop metadata/nonstatic pixels, checks the signed-frequency sinusoidal displacement extrema, confirms document/frame/camera preservation, cancellation against an existing file, and presents the actual GIF sheet. Local evidence is kept outside the repo at `/Users/nacho/Downloads/chemviewer-animation-work`. This is programmatic native-Mac coverage, not full manual dialog/trackpad acceptance or full Chemcraft feature parity.

Final local results: 19 standalone core methods passed; all five packaged checks (base, energy, manipulation, smooth interaction, animation) passed. After correcting the final Paton shader selector, animation/base/smooth checks were repeated and passed. Independent Pillow 11.3 decoding confirmed trajectory 4 frames/3 unique images and frequency 12 frames/7 unique images, each 256×256, 100 ms delay and loop count 0 (the repeated frames follow ping-pong/sinusoidal symmetry). Cancellation was exercised after rendering had started and preserved the existing destination. The actual export sheet presented successfully. Window screenshot capture was unavailable in this run; no human visual-dialog acceptance is claimed. The signed arm64 0.6.0 package was copied to `/Users/nacho/Applications/ChemViewer.app`, signature verified, and opened with the independent trajectory fixture.

## 0.6.1 — uniform shading by distance

At the user’s request, depth fog is disabled for both atoms and bonds. The shared native render path now sends zero fog weight, so farther objects retain the same element colors and surface gradient as nearer objects. This applies to the viewport, PNGs and GIFs. Paton palette, outlines and radial shading remain. Verify by rotating a deep structure and comparing near/far atoms of the same element. This supersedes the 0.6.0 depth-fog behavior.

## 0.6.2 — measurement labels and slower GIFs

Select 2 atoms for length, 3 for angle (B is the vertex in A→B→C), or 4 for a signed dihedral, in order. Choose File → Export Animation as GIF… and enable **Include measurement label and guides**. The current ordered selection supplies one measurement per GIF. Its numeric value and projected guides are recomputed from each frame's actual coordinates, including sinusoidal frequency displacements. Labels use Å or degrees, retain the viewer’s angle, and use the same guide/dihedral-plane drawing as the native view. The toggle starts enabled when the viewer’s measurement overlay was enabled. Labels require stable atom ordering and matching element sequences across trajectory frames. If a selected angle/dihedral is undefined in a frame, export reports an error rather than writing a misleading value; temporary output is removed and any existing destination remains intact.

Playback speed offers Normal, Half, Quarter and Eighth; Half is the new dialog default. Frame-rate choices now include 1 and 2 fps. Every frame is retained; GIF delay is `1 / (fps × speed)`, with an approximate loop duration shown. GIF centisecond quantization/player behavior may slightly change actual timing. These choices apply to both trajectories and frequencies. Display speed remains illustrative, not physical vibrational time. Coordinates, amplitude and camera orientation are unchanged.

0.6.2 final local results: 19 standalone core cases, expanded packaged annotation/GIF checks and base viewer smoke checks passed. Independent Pillow decoded all 12 frames at 100 ms normally versus 400 ms at quarter speed (1.2 s versus 4.8 s). Angle/dihedral PNGs were visually inspected for guide alignment. Native selection, camera, cancellation and scientific frame data remain covered. Signed arm64 app installed at ~/Applications/ChemViewer.app. Relaunch to load 0.6.2. Human dialog/playback acceptance remains pending.

## 0.7.4 — draggable measurement labels

Enable Show bond length/angle/dihedral, then drag the white numeric label box to move it away from the structure. The hand cursor identifies the draggable area. Only the label receives those drag events; clicks outside it continue to select atoms or rotate/drag the molecule, and right-click still clears selection. The numeric measurement and its atom guides remain tied to the selected atoms. Reset label restores automatic placement.

Offsets are stored locally per geometry and ordered atom selection, as fractions of viewport width/height. Reselecting the same measurement restores its placement during the current view session. PNG capture uses the live placement; the independent GIF renderer copies the offset map and applies the same normalized offset at its output resolution while recomputing each frame's value. Export still fits all frames once, so absolute pixel placement can differ with aspect ratio/framing. Labels stay inside image bounds. New file/view sessions and atom-count changes clear positions; working project files do not serialize label positions. Dragging a label does not change coordinates, selection, animation or camera and does not add geometry undo entries.

Native regression coverage uses mouse handlers on 2/3/4-atom label boxes, verifies 70×30-point label motion, pass-through away from the box, unchanged numeric values/geometry/camera, retained placement on reselection, PNG exports, offset preservation through both GIF renderer copies, an actual moved-dihedral GIF, reset, and prior smooth camera/selection/drag checks. Scientific core tests remain unchanged. Manual pointer feel and all output sizes still require user acceptance.

## 0.8.1 — transparent GIFs and box-free atom captions

GIF export now defaults to **Transparent background**; clear that checkbox for the previous white background. Atom-number, element and combined captions have no painted background in the viewport, PNGs or GIFs. Transparent GIF measurement text also omits its white box, while its numeric value, guide lines and moved placement are retained. The live draggable measurement-label box remains for normal viewing. Camera angle, scientific coordinates, playback speed and label offsets are unchanged.

The independent Metal export targets clear to RGBA zero and preserve alpha through readback. MSAA coverage colors are unpremultiplied in linear space to avoid dark fringes. Caption/measurement compositing clears its bitmap before drawing. GIF supports binary transparency, not partial opacity; export thresholds coverage at 50 percent, retaining opaque white atoms rather than color-keying white. Subtle semitransparent guide planes cannot retain fractional opacity in GIF.

GIFWriter now uses ImageIO to quantize each independent frame, then streams GIF89a image blocks with local palettes, an infinite-loop extension, explicit delay and disposal-to-background (method 2). Independent full-image frames prevent the differential-frame/disposal interaction that otherwise causes stale atom trails or disappearing stationary atoms. No Python installation is required for export. Existing temp-file cancellation and atomic final replacement remain.

Validation: 25 standalone core cases and the three integrated suites passed during the signed arm64 build. Expanded native animation tests verify transparent corners, frame-by-frame masks against independently rendered alpha images, preserved white atoms, an opaque-white option, all three caption modes with zero white-background pixels, timing/loops/cancellation/measurements and unchanged document/camera. Independent Pillow compositing checked all 12 frequency frames at every pixel: disposal 2, no trails or missing opaque atoms, and no caption boxes. The smooth/label-placement workflow is also checked. Evidence is outside the repository in Downloads/chemviewer-transparent-work.
