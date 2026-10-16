# Windows reference evidence

Generated GUI runs are written to `runs/<UTC timestamp>/` and intentionally
ignored by version control because screenshots can contain proprietary UI and
opened user data. Each run includes `run.json`, input hashes, and captures.

Promoted, redistributable numeric reference records may be committed beside
this file after their provenance and licensing are reviewed.

`gui-scientific-reference.json` is the promoted machine-readable reference.
It contains hashes and observed numeric/display behavior, but no proprietary
binary, UI image, license identity, or third-party calculation text.

Run the deterministic harness from the repository root:

```powershell
.\Tests\gui\windows\.venv\Scripts\python.exe -m pytest .\Tests\gui\windows -q
.\Tests\gui\windows\.venv\Scripts\python.exe .\Tests\gui\windows\chemcraft_driver.py menus
.\Tests\gui\windows\.venv\Scripts\python.exe .\Tests\gui\windows\chemcraft_driver.py measurements --fixture .\Tests\fixtures\water.xyz
```

The GUI commands launch the licensed local Windows reference and write only to
the ignored `runs/` directory. They never modify `C:\Chemcraft`.
