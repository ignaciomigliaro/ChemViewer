#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "usage: $0 /path/to/Chemcraft.app" >&2
    exit 2
fi

app="$1"
if [[ ! -d "$app" ]]; then
    echo "not an application bundle: $app" >&2
    exit 2
fi

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
stamp="$(date -u +%Y%m%dT%H%M%SZ)"
out="$project_dir/diagnostics/macos-$stamp"
mkdir -p "$out"

exec_path="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app/Contents/Info.plist")"
binary="$app/Contents/MacOS/$exec_path"

{
    sw_vers
    uname -a
    sysctl -n machdep.cpu.brand_string 2>/dev/null || true
} > "$out/system.txt" 2>&1
file "$binary" > "$out/file.txt" 2>&1 || true
lipo -info "$binary" > "$out/lipo.txt" 2>&1 || true
codesign -dvvv --entitlements :- "$app" > "$out/codesign.txt" 2>&1 || true
codesign --verify --deep --strict --verbose=4 "$app" > "$out/codesign-verify.txt" 2>&1 || true
spctl -a -vv --type execute "$app" > "$out/gatekeeper.txt" 2>&1 || true
xattr -lr "$app" > "$out/xattrs.txt" 2>&1 || true
otool -L "$binary" > "$out/dependencies.txt" 2>&1 || true
otool -l "$binary" > "$out/load-commands.txt" 2>&1 || true
find "$app" -type f -print0 | xargs -0 shasum -a 256 > "$out/sha256.txt"

crash_root="$HOME/Library/Logs/DiagnosticReports"
if [[ -d "$crash_root" ]]; then
    find "$crash_root" -maxdepth 1 -type f \( -iname 'Chemcraft*.crash' -o -iname 'Chemcraft*.ips' \) \
        -mtime -30 -exec cp {} "$out/" \;
fi

echo "Read-only diagnostics written to $out"
echo "No quarantine attributes or security settings were changed."
