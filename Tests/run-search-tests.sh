#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
SEARCH_BUILD_DIR=$(mktemp -d /tmp/pocketsync-search-tests.XXXXXX)
trap 'rm -rf "$SEARCH_BUILD_DIR"' EXIT
xcrun swiftc -module-cache-path "$SEARCH_BUILD_DIR/cache" \
  PocketSync/Models/VideoModels.swift PocketSync/Models/PluginModels.swift PocketSync/Models/SDSyncManifest.swift \
  PocketSync/Services/VideoDatabase.swift PocketSync/Services/PluginService.swift PocketSync/Services/MediaStorage.swift \
  PocketSync/VideoSearch.swift Tests/VideoSearchTests.swift -o "$SEARCH_BUILD_DIR/search-tests"
"$SEARCH_BUILD_DIR/search-tests"
