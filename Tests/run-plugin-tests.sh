#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
BUILD_DIR=$(mktemp -d /tmp/pocketsync-plugin-tests.XXXXXX)
trap 'rm -rf "$BUILD_DIR"' EXIT
xcrun swiftc -module-cache-path "$BUILD_DIR/cache" \
  PocketSync/Models/VideoModels.swift PocketSync/Models/PluginModels.swift PocketSync/Models/SDSyncManifest.swift \
  PocketSync/Services/VideoDatabase.swift PocketSync/Services/PluginService.swift PocketSync/Services/MediaStorage.swift \
  Tests/PluginServiceTests.swift -o "$BUILD_DIR/plugin-tests"
"$BUILD_DIR/plugin-tests" "$PWD/Tests/Fixtures/ImportPlugin.py"
