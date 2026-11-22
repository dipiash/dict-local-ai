#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
python3 - <<'PY'
import pathlib, plistlib
root=pathlib.Path('Sources/DictLocalAI')
all_code='\n'.join(p.read_text() for p in root.rglob('*.swift'))
for forbidden in ('import ScreenCaptureKit','CGPreflightScreenCaptureAccess(', 'CGRequestScreenCaptureAccess(', 'SCStream(', 'SCShareableContent.'):
    assert forbidden not in all_code, f'Unexpected video/screen TCC API: {forbidden}'
with open('Resources/App/Info.plist','rb') as file:
    info=plistlib.load(file)
assert 'NSAudioCaptureUsageDescription' in info
assert 'NSMicrophoneUsageDescription' in info
assert info['CFBundleIdentifier']=='app.dictlocalai.desktop'
assert 'AudioHardwareCreateProcessTap' in all_code
assert 'AudioHardwareCreateAggregateDevice' in all_code
assert 'AudioDeviceCreateIOProcIDWithBlock' in all_code
print('PASS: audio-only capture, required Info.plist key, stable Bundle ID')
PY
