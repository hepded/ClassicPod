#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build
BIN_DIR="$(swift build --show-bin-path)"
swiftc -swift-version 6 -parse-as-library -D CLI_CHECKS -I "$BIN_DIR/Modules" \
    "$BIN_DIR"/PodCore.build/*.swift.o Tests/PodCoreTests/PodCoreTests.swift -o "$BIN_DIR/CoreChecks"
"$BIN_DIR/CoreChecks"
OBJECTS=()
while IFS= read -r object; do OBJECTS+=("$object"); done < <(find "$BIN_DIR/ClassicPod.build" -name '*.swift.o' ! -name ClassicPodApp.swift.o | sort)
swiftc -swift-version 6 -parse-as-library -I "$BIN_DIR/Modules" \
    "$BIN_DIR"/PodCore.build/*.swift.o "${OBJECTS[@]}" Checks/IntegrationChecks.swift -o "$BIN_DIR/IntegrationChecks"
"$BIN_DIR/IntegrationChecks"
