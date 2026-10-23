#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
case "${1:-}" in
  ""|--require-xctest) ;;
  *) echo "Usage: bash scripts/build-macos.sh [--require-xctest]" >&2; exit 2 ;;
esac
if xcrun --find xctest >/dev/null 2>&1; then
    swift test
elif [[ "${1:-}" == --require-xctest ]]; then
    echo "XCTest requires full Xcode. Install Xcode and select its Developer directory." >&2
    exit 1
else
    echo "XCTest is unavailable; running the existing core assertions with the standalone runner."
    python3 scripts/check-core.py
fi
bash scripts/check-building.sh
swift build -c release --arch arm64 --product ChemViewer
bin_dir="$(swift build -c release --arch arm64 --show-bin-path)"
app_dir="$project_dir/dist/ChemViewer.app"
case "$app_dir" in
    "$project_dir"/dist/*.app) ;;
    *) echo "refusing to replace unexpected path: $app_dir" >&2; exit 2 ;;
esac
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$bin_dir/ChemViewer" "$app_dir/Contents/MacOS/ChemViewer"
cp "$project_dir/Packaging/Info.plist" "$app_dir/Contents/Info.plist"
bash "$project_dir/scripts/build-icon.sh"
cp "$project_dir/Packaging/ChemViewer.icns" "$app_dir/Contents/Resources/ChemViewer.icns"
resource_bundle="$(find "$bin_dir" -maxdepth 1 -name '*ChemViewerApp.bundle' -print -quit)"
if [[ -n "$resource_bundle" ]]; then
    # Replace generated resources rather than retaining obsolete Python bytecode
    # or removed assets from an earlier local build.
    rm -rf "$app_dir/Contents/Resources/$(basename "$resource_bundle")"
    ditto "$resource_bundle" "$app_dir/Contents/Resources/$(basename "$resource_bundle")"
else
    echo "missing SwiftPM Metal resource bundle" >&2; exit 1
fi
find "$app_dir/Contents/Resources" -type f \( -name '*.pyc' -o -name '*.pyo' \) -delete
cp "$project_dir/docs/third-party/xyzrender-LICENSE.txt" "$app_dir/Contents/Resources/xyzrender-LICENSE.txt"
codesign --force --deep --sign - "$app_dir"
codesign --verify --deep --strict --verbose=2 "$app_dir"
lipo "$app_dir/Contents/MacOS/ChemViewer" -verify_arch arm64
echo "Built $app_dir"
