#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT
# Compile the actual tvOS store with the shared token model and an in-memory
# Keychain, on Linux. The assembled test file ends in XCTMain, which exists only
# in swift-corelibs-xctest and not in Apple's XCTest, so macOS is not supported.
# The app itself still requires Xcode and the tvOS SDK.
if [ "$(uname -s)" != "Linux" ]; then
  echo "run-token-store-tests.sh runs on Linux only (XCTMain is not in Apple's XCTest)." >&2
  exit 1
fi
{
  printf 'import Foundation\n#if canImport(FoundationNetworking)\nimport FoundationNetworking\n#endif\nimport XCTest\n'
  cat "$repo_root/Sources/SSHCore/OAuthToken.swift"
  sed '1d; $d; /^import SSHCore$/d' "$repo_root/App/TVApp/TVOAuthTokenStore.swift"
  cat "$repo_root/Tests/TVAppTests/TokenStoreTests.swift"
} > "$test_dir/main.swift"
swiftc -swift-version 5 "$test_dir/main.swift" -o "$test_dir/token-store-tests"
"$test_dir/token-store-tests"
