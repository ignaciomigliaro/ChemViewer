# Local evidence artifacts

Proprietary binaries are intentionally ignored and must not be committed or
redistributed. The local artifacts inspected on 2026-10-15 were downloaded from
the official ChemCraft site:

| Artifact | Bytes | SHA-256 |
|---|---:|---|
| `Chemcraft_b638m_MacARM.dmg` | 30,925,505 | `603e4e9c2a6b7d2e4cffdd9686490327200dde637065b9e3ed78020689387814` |
| `Chemcraft_b638m_MacIntel.dmg` | 30,924,918 | `967100f1d25eb877287b94e47829832aefad9ac48ccbb36f6ba48e163ec2169b` |
| `Chemcraft_ARM` executable | 13,091,048 | `c3a83812708d942afb59e9f2f13ad5448d4be9bee20c22129f81cfdc99e86441` |
| `Chemcraft_Intel` executable | 12,387,064 | `645bdf5291073f2e29edc101365b9803c43ecca360bc664597991169cc88a6f0` |

REA root Evidence IDs:

- ARM DMG: `ev_a32ceda74fb40556341c0aa358b187c2145cedf34a8cb53d811752a79d3d3b31`
- Intel DMG: `ev_2324d30cd9c4e6563bedb122ae7455022ba9864583ca3cd86e461fb7b023d7fa`
- ARM executable: `ev_90805e8de5d4d03ab9ea67d0a1e437c14a4a8a5bd7c0991f6989e832c0b6859e`
- Intel executable: `ev_581c6bb2f70bea8a76f8af881c698e49da29340ea5bafed93f7f44cedc1f4dbd`

`tools/macho_inventory.py` reproduces the cross-platform header, dependency,
symbol, and code-signature-container inventory. Certificate trust and runtime
behavior still require macOS-native tools.
