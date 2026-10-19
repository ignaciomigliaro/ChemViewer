#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
source_icon="$project_dir/Packaging/ChemViewerIcon.png"
iconset_dir="$project_dir/.build/ChemViewer.iconset"
[[ -f "$source_icon" ]] || { echo "Missing ChemViewer icon source: $source_icon" >&2; exit 1; }
mkdir -p "$iconset_dir"
for logical_size in 16 32 128 256 512; do
    sips -z "$logical_size" "$logical_size" "$source_icon" --out "$iconset_dir/icon_${logical_size}x${logical_size}.png" >/dev/null
    retina_size=$((logical_size * 2))
    sips -z "$retina_size" "$retina_size" "$source_icon" --out "$iconset_dir/icon_${logical_size}x${logical_size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset_dir" -o "$project_dir/Packaging/ChemViewer.icns"
echo "Built Packaging/ChemViewer.icns"
