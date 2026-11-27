#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."

[[ "$(uname -s)" == Darwin && "$(uname -m)" == arm64 ]] || {
  echo 'Shortcut concurrency tests with Thread Sanitizer require Apple Silicon macOS.' >&2
  exit 2
}

developer_dir=$(xcode-select -p)
test_runner="$developer_dir/Platforms/MacOSX.platform/Developer/Library/Xcode/Agents/xctest"
tsan_library=$(find "$developer_dir/Toolchains/XcodeDefault.xctoolchain" \
  -name libclang_rt.tsan_osx_dynamic.dylib -print -quit)
[[ -x "$test_runner" && -f "$tsan_library" ]] || {
  echo 'Could not find XCTest or the Thread Sanitizer runtime.' >&2
  exit 1
}

work=$(mktemp -d "${TMPDIR:-/tmp}/dict-shortcut-tests.XXXXXX")
trap 'rm -rf "$work"' EXIT
swift build --scratch-path .build/tsan --arch arm64 --build-tests --sanitize=thread
binary_dir=$(swift build --scratch-path .build/tsan --arch arm64 --sanitize=thread --show-bin-path)
mkdir "$work/logs"
DICT_LOG_DIR="$work/logs" DYLD_INSERT_LIBRARIES="$tsan_library" \
  "$test_runner" -XCTest ShortcutConcurrencyTests "$binary_dir/DictLocalAIPackageTests.xctest" \
  | tee "$work/result.txt"
if ! grep -Eq 'Executed [1-9][0-9]* tests?' "$work/result.txt"; then
  echo 'XCTest did not execute the shortcut concurrency tests.' >&2
  exit 1
fi
