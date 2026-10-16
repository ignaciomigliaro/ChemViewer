# Reverse-engineering findings

Evidence types are kept distinct: **observed artifact**, **observed corpus**,
**documented behavior**, **inference**, and **unknown**. Static evidence does
not establish runtime behavior.

## Environment

- Observed: Windows 11 Home x64, Node 24.22, REA 6.5.0, Python launcher,
  Git, CMake, WSL, and .NET 8 are installed.
- Observed initially: Swift, Ghidra, IDA integration, Hopper, Wine, Clang,
  Ninja, and Visual Studio command-line tools were unavailable. On 2026-10-15,
  Ghidra 12.1.4 plus OpenJDK 21 became available through REA and passed its
  provider checks. Swift and a macOS runtime remain unavailable on this host.
- Observed: REA's Codex registration was initially absent. A reviewed setup
  action backed up `C:\Users\Ignac\.codex\config.toml` to
  `config.toml.rea.backup` and registered the installed REA 6.5.0 MCP command.
  The current session is connected to REA 6.5.0 and exposes the Ghidra provider.
- Observed: the bundled Windows-control helper failed before app control with
  `helper_unknown_error`. A separate project-local Python harness using UIA,
  Win32, screenshots, and calibrated input recovered the audit. Direct GUI
  evidence is documented in `windows-gui-audit.md`; helper failure must not be
  confused with application incompatibility.

## Windows artifact identity

- Path: `C:\Chemcraft\Chemcraft.exe`
- Size: 12,841,472 bytes.
- SHA-256: `79fe75015a1e48c4df29e7bac4c3c05e67057bf3a0ed03a7b77fe85528d4f05a`.
- Observed: unsigned according to Windows Authenticode inspection.
- Observed: native PE32+ x86-64, 15 sections, no CLI/.NET metadata.
- REA artifact Evidence: `ev_0c9f0c954791b774000004a1abebd6fd536c0ecfbc398824ba4a445307e48c84`.
- REA managed/native classification Evidence:
  `ev_dcac80936b8e7436946ddb1cb064e398bf50862b4015ab61dcf6273942cf024d`.
- Observed: strict REA PE-resource inspection rejected one resource range as
  not entirely file-backed in a section.
- Inference, low confidence: packing or virtualization may explain the unusual
  resource mapping. This is not established until PE layout/import analysis or
  runtime module evidence corroborates it.
- Observed: the surviving string inventory contains Delphi/VCL-style RTL and UI
  diagnostics plus `TMethodImplementationIntercept`. Inference, high confidence:
  the Windows program contains a Delphi/VCL runtime. The exact compiler release
  remains unknown.
- Unknown: molecular rendering backend, complete application API usage behind
  the protector, application-level function boundaries, and proprietary data
  formats.

Additional PE header evidence from GNU objdump:

- The executable maps a roughly 54 MB image from a 12.8 MB file and contains 15
  mostly unnamed sections with mixed code/data flags.
- Its static imports are deliberately narrow: mostly one bootstrap function from
  each Windows DLL plus `enigma_ide_x64.dll!EP_RegHardwareID`.
- Inference, high confidence: the shipped executable is protected/virtualized by
  Enigma and the visible import table describes the loader/protector boundary,
  not the application's complete runtime API usage.
- Policy boundary: no unpacking, license-call tracing, registration-data reading,
  or license bypass will be attempted. Scientific compatibility work proceeds
  from documented formats, authorized black-box behavior, and original code.

## Ghidra 12.1.4 static pass

Target discovery was recursive rather than filename-assumed. Only two `.exe`
files were found beneath `C:\Chemcraft`: the 12,841,472-byte application and
`unins000.exe`, whose version metadata identifies it as the Chemcraft 1.8
setup/uninstaller. Size, role, and metadata identify `Chemcraft.exe` as the main
application.

REA opened the exact application hash with `provider_id: "ghidra"`. The
ephemeral, immutable Ghidra analysis reports image base `0x400000`, 16 mapped
blocks (headers plus 15 PE sections), 42,914 analyzed procedures, and 514
Ghidra-defined strings. REA Evidence:

- binary overview: `ev_59878799b2527d32570d4f19b06f16874541b7fe7729f8f17006478faf592a92`;
- complete Ghidra-defined string inventory:
  `ev_542fee8caddad1a4bb699fdb34aeda171c8798167d3ee09f40720041c4195eb0`;
- static external-procedure search:
  `ev_a1db19ce9c93c4b5636d2802ef015fdb5b08fb6b5bef352d931627a323defc10`.

The PE dependency/name table contains `kernel32.dll`, `user32.dll`,
`advapi32.dll`, `oleaut32.dll`, `gdi32.dll`, `shell32.dll`, `version.dll`,
`ole32.dll`, `mpr.dll`, `comctl32.dll`, `msvcrt.dll`, `comdlg32.dll`,
`winspool.drv`, `oledlg.dll`, `winmm.dll`, `enigma_ide_x64.dll`, and
`oleacc.dll`. The narrow imported calls include `GetModuleHandleA`,
`GetProcAddress`, `ExitProcess`, `LoadLibraryA`, `MessageBoxA`, `RegCloseKey`,
`SysFreeString`, `CreateFontA`, `ShellExecuteA`, `GetFileVersionInfoA`,
`OleInitialize`, `WNetGetConnectionW`, `InitializeFlatSB`, `memset`,
`ChooseFontW`, `OpenPrinterW`, `OleUIObjectPropertiesW`, `sndPlaySoundW`,
`EP_RegHardwareID`, and `LresultFromObject`. These are static loader/import
facts, not a complete runtime dependency set.

The only Ghidra xrefs to `LoadLibraryA` and `GetProcAddress` are import-table
locations `0x3697278` and `0x3697268`; neither belongs to an analyzed procedure.
No static resolver caller can therefore be claimed. Evidence:
`ev_bf132f128710a41d6998ff29151edac10804812ce0fb889d6f0504557a84ae5c`
and `ev_2f55349ccbda426c41bd5f6c34ede40439b82f68a4bfeda7431c0a17ffbbc054`.

The PE entry is `0x3a36df4`. Ghidra classifies it as a two-byte thunk to
`0x3a36dfe`. Decompilation observes a loop XORing 0x60b bytes beginning at
`0x3a36e78`, a write/inversion through an anomalous address, bad instruction
data, and truncated control flow. Evidence:

- entry dossier: `ev_fa297c9c4fcdf83acd59d8bfffb3a1500a776d744c38cfe5873625285ec49ce8`;
- entry-target dossier:
  `ev_4b234ad5d430fdc29bd0ef1fc54c5eb76d1ed7f90e9bb218a16c756d63cd3d74`.

This is observed self-modifying/deobfuscation behavior at the entry boundary.
Together with the Enigma import it supports the protection finding, but the
decompiler output is pseudocode and not original source.

```text
0x3a36df4 entry thunk
    -> 0x3a36dfe protector/deobfuscation stub
         -> rewrites 0x60b bytes from 0x3a36e78
         -> subsequent static control flow unresolved
```

### Requested subsystem map

| Subsystem | Static result | Confidence and evidence |
|---|---|---|
| Windows UI/runtime | Delphi/VCL-style diagnostic strings and common-control/OLE/GDI imports are present | High-confidence compiler-framework inference; string inventory Evidence `ev_542fee...` |
| Generic bitmap/image support | Imaging/JPEG/canvas diagnostics occupy `0x29ad668` through approximately `0x29b0e9c` | Observed strings; selected strings at `0x29ade3e`, `0x29ae0ba`, `0x29b0c54`, and `0x29b0e18` have zero static xrefs |
| Molecular rendering | No defensible application function identified | Unresolved: no feature strings/symbols/xrefs; static `CreateFontA` does not establish a renderer |
| Geometry editing | No defensible application function identified | Unresolved for the same protected/stripped boundary |
| ORCA parsing | No defensible application function identified | Unresolved; a complete search of Ghidra-defined strings found no ORCA marker |
| Molecular-orbital visualization | No defensible application function identified | Unresolved |
| Vibrational animation | No defensible application function identified | Unresolved |
| Reaction pathways/IRC/NEB | No defensible application function identified | Unresolved |

The chemistry-string search Evidence is
`ev_b5eeec031667e78c30d29ea99c847d0644c2b437701044cd87138c7be8278422`;
its only match was the unrelated VCL message `Circular references not allowed`.
Selected surviving image-string xref searches also returned empty results
(`ev_e30c44913cba7736fff38135f827a9a1ea0660ce5440bb0885150171ad79c2a4`,
`ev_ad70473e75d12de803ab578cb8bdc70dbe0febfc90b5e6f23a570bea1f688c18`,
`ev_6fda5e0d546e33391b1971fdda07fb22d6f06b9e4802d728eb37559c0aaf38eb`,
and `ev_beb9ef422a4f44556bae0dff23631479c70f151a177a3a1678885b5754532c1d`). These
are bounded negative findings over Ghidra-defined objects, not proof that the
features or references are absent from the running unpacked program.

The strict PE-resource parser still rejects the protected resource mapping as
not entirely file-backed in one section. Static analysis therefore cannot map
the requested scientific subsystems without either an authorized unprotected
vendor build or runtime-unpacked evidence. Runtime unpacking or tracing around
`EP_RegHardwareID` would cross the project's licensing boundary and was not
performed.

## Installed data and corpus

- Observed top-level data includes `atomicmasses.txt`, `basissets1.txt`,
  `bonds4.bin`, `fragments2.bin`, rendering schemes, and preferences.
- No registration or user-data file contents were inspected.
- Observed corpus: 246 files, 93,456,461 bytes, grouped into 39 named program or
  format families. Dominant extensions are 78 `.out`, 27 `.inp`, 23 `.xyz`,
  15 `.cif`, 12 `.log`, and 10 `.gjf` files.
- Families include ADF, CFOUR, CIF, CRYSTAL, Dalton, Firefly, GAMESS-US/UK,
  Gaussian, GROMACS, Jaguar, Molcas, Molden, Molpro, NBO, NWChem, ORCA, PDB,
  PSI, Q-Chem, Quantum Espresso, SDF, Turbomole, VASP, and xTB.
- This is evidence that samples exist, not proof that every field or variant is
  supported correctly by the reference application.

## Official macOS b638m artifacts

- ARM DMG SHA-256 `603e4e9c2a6b7d2e4cffdd9686490327200dde637065b9e3ed78020689387814`;
  REA Evidence `ev_a32ceda74fb40556341c0aa358b187c2145cedf34a8cb53d811752a79d3d3b31`.
- Intel DMG SHA-256 `967100f1d25eb877287b94e47829832aefad9ac48ccbb36f6ba48e163ec2169b`;
  REA Evidence `ev_2324d30cd9c4e6563bedb122ae7455022ba9864583ca3cd86e461fb7b023d7fa`.
- ARM executable is thin arm64, SHA-256
  `c3a83812708d942afb59e9f2f13ad5448d4be9bee20c22129f81cfdc99e86441`;
  REA Evidence `ev_90805e8de5d4d03ab9ea67d0a1e437c14a4a8a5bd7c0991f6989e832c0b6859e`.
- Intel executable is thin x86-64, SHA-256
  `645bdf5291073f2e29edc101365b9803c43ecca360bc664597991169cc88a6f0`;
  REA Evidence `ev_581c6bb2f70bea8a76f8af881c698e49da29340ea5bafed93f7f44cedc1f4dbd`.
- Cross-platform load-command decoding finds 13 Apple-only dependencies in each
  executable, 364 ARM imports and 363 Intel imports.
- ARM is Free Pascal 3.2.2/aarch64 and Intel Free Pascal 3.2.0/x86-64; Lazarus
  LCL/Cocoa and TAChart strings are observed in both.
- ARM is ad-hoc/linker-signed (`flags 0x20002`) with no CMS certificate or
  hardened runtime. Intel has no embedded signature command.
- The official site explicitly states that the distributions lack a valid Apple
  certificate, reports frequent crashes for some users, and reports that many
  users find Intel more stable than ARM. These are publisher statements, not
  runtime observations on the target machine.
- Unknown: actual crash mechanism, Rosetta behavior, target macOS compatibility,
  and whether any instability is deterministic by workflow.

## ORCA frequency case

Observed in `ORCA/H2O_xyz_opt_freq_compound_jobs.out`:

- Multiple Cartesian geometry and energy blocks.
- Final energy `−76.360968646 Eh`.
- Nine Hessian modes numbered 0–8.
- Vibrations 6–8 at 1606.12, 3678.02, and 3777.72 cm⁻¹.
- IR intensities 45.965085, 2.615006, and 19.770076.
- A 9×9 normal-mode displacement matrix; ORCA states these Cartesian
  displacements are weighted by `1/sqrt(mass)` and normalized but not orthogonal.

The independent Python oracle reproduces these values. The Swift parser follows
the same section boundaries but still requires compilation and tests on macOS.

## Next evidence probes

1. Run bounded UI workflows once Windows automation is healthy; record menu and
   dialog behavior without inspecting or changing licensing.
2. If the vendor supplies an unprotected analysis build, bind its exact hash in
   Ghidra and repeat the feature-string, RTTI, call-graph, and decompilation pass.
3. Transfer the already authenticated ARM/Intel builds to the target Mac, gather
   crash reports, and run the read-only diagnostic script before choosing repair
   vs replacement conclusively.
