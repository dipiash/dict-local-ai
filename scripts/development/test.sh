#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."

# Run SwiftPM itself as ARM64 as well as its build and test host.
/usr/bin/arch -arm64 swift build --scratch-path .build/apple-silicon --build-tests --arch arm64 "$@"
binary_dir=$(/usr/bin/arch -arm64 swift build --scratch-path .build/apple-silicon --arch arm64 --show-bin-path "$@")
test_bundle="$binary_dir/DictLocalAIPackageTests.xctest"
developer_dir=$(xcode-select -p)
test_runner="$developer_dir/Platforms/MacOSX.platform/Developer/Library/Xcode/Agents/xctest"
exec /usr/bin/arch -arm64 "$test_runner" "$test_bundle"
