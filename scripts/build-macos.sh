#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"

swift test
swift build -c release --arch arm64 --product ChemViewer

app_dir="$project_dir/dist/ChemViewer.app"
case "$app_dir" in
    "$project_dir"/dist/*.app) ;;
    *) echo "refusing to replace unexpected path: $app_dir" >&2; exit 2 ;;
esac
rm -rf -- "$app_dir"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$project_dir/.build/arm64-apple-macosx/release/ChemViewer" "$app_dir/Contents/MacOS/ChemViewer"
cp "$project_dir/Packaging/Info.plist" "$app_dir/Contents/Info.plist"

resource_bundle="$(find "$project_dir/.build/arm64-apple-macosx/release" -maxdepth 1 -name '*ChemViewerApp.bundle' -print -quit)"
if [[ -n "$resource_bundle" ]]; then
    # SwiftPM's generated Bundle.module accessor resolves this bundle relative
    # to Bundle.main.bundleURL, which is the .app root for a packaged app.
    ditto "$resource_bundle" "$app_dir/$(basename "$resource_bundle")"
else
    echo "missing SwiftPM Metal resource bundle" >&2
    exit 1
fi

codesign --force --deep --sign - "$app_dir"
codesign --verify --deep --strict --verbose=2 "$app_dir"
echo "Built $app_dir"
