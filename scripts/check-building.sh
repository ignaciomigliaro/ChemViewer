#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/building-tests
for test in Parser Editing State; do
  xcrun swiftc -module-cache-path .build/building-tests/module-cache Sources/ChemCraftCore/IntegratedBuilding.swift "Tests/IntegratedBuilding/${test}Tests.swift" -o ".build/building-tests/${test}Tests"
  ".build/building-tests/${test}Tests"
done
