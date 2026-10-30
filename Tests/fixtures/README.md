# Test fixtures

Only independently generated or redistributable fixtures belong here. Windows
ChemCraft samples remain in `C:\Chemcraft\samples` and are referenced by exact
path and SHA-256; they are not copied into the clean-room source tree.

| Fixture | Purpose | SHA-256 |
|---|---|---|
| `water.xyz` | Atom picking, O-H distance, H-O-H angle, structure export | `ad9798ab5b0e47faa79fd95b835b23295353c3801a0e9cba36109cd83c8aa1f6` |
| `methane.xyz` | Rotation, zoom, and translation image-difference checks | `5bb58ad835f2af3b796eba40097193b33fe3ee42616c7058fd4d529dd68f2955` |
| `dihedral.xyz` | Four-atom selection and signed dihedral convention | `2c8cf8aaac94de44aff27431ec554814804ef06756acc291cfadf4c99b5e4e14` |

These small geometries were authored for this project and may be committed.

`desktop-imaginary.out` is original, synthetic ORCA-style parser/UI test text.
It deliberately uses an arbitrary −250 cm⁻¹ H2 mode, IR intensity 7.5 and energy
−1.123456789012 Hartree. It is not output from a real calculation and makes no
physical transition-state claim. It may be redistributed with these tests.
