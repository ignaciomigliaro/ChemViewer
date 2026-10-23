#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
case "${1:-}" in
  "") bash "$project_dir/scripts/build-macos.sh" ;;
  --no-build) ;;
  *) echo "Usage: bash scripts/install-macos.sh [--no-build]" >&2; exit 2 ;;
esac
source_app="$project_dir/dist/ChemViewer.app"
codesign --verify --deep --strict "$source_app"
# Keep existing shortcuts to either conventional installation up to date.
install_targets=(/Applications/ChemViewer.app)
if [[ -d "$HOME/Applications/ChemViewer.app" ]]; then
    install_targets+=("$HOME/Applications/ChemViewer.app")
fi
for target in "${install_targets[@]}"; do
    ditto "$source_app" "$target"
    # ditto merges directories: remove only obsolete interpreter-generated files.
    find "$target/Contents/Resources" -type f \( -name '*.pyc' -o -name '*.pyo' \) -delete
    codesign --verify --deep --strict "$target"
    echo "Updated $target"
done
registration=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
if [[ -x "$registration" ]]; then
    "$registration" -f /Applications/ChemViewer.app
fi
echo "Quit and reopen ChemViewer to use the update."
