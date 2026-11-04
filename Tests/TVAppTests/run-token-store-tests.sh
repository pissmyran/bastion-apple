#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT
# Compile the actual tvOS store with the shared token model and an in-memory
# Keychain, on Linux or macOS. The app itself still requires Xcode and the tvOS SDK.
{
  printf 'import Foundation\n#if canImport(FoundationNetworking)\nimport FoundationNetworking\n#endif\nimport XCTest\n'
  cat "$repo_root/Sources/SSHCore/OAuthToken.swift"
  sed '1d; $d; /^import SSHCore$/d' "$repo_root/App/TVApp/TVOAuthTokenStore.swift"
  cat "$repo_root/Tests/TVAppTests/TokenStoreTests.swift"
} > "$test_dir/main.swift"
swiftc -swift-version 5 "$test_dir/main.swift" -o "$test_dir/token-store-tests"
"$test_dir/token-store-tests"
