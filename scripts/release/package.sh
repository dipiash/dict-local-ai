#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
bash scripts/build/build.sh
python3 scripts/build/verify-portable-bundle.py "dist/Dict Local AI.app"
model_file=$(find 'dist/Dict Local AI.app' \( -name '*.mlmodelc' -o -name '*.mlpackage' -o -name '*.mlmodel' -o -name '*.safetensors' -o -name '*.onnx' -o -name '*.pth' -o -name '*.pt' -o -name 'weight.bin' \) -print -quit)
[[ -z "$model_file" ]] || { echo "Model weights must be excluded from the release: $model_file" >&2; exit 1; }
/usr/bin/ditto -c -k --sequesterRsrc --keepParent 'dist/Dict Local AI.app' dist/Dict-Local-AI-macOS-arm64.zip
(cd dist && shasum -a 256 Dict-Local-AI-macOS-arm64.zip > SHA256SUMS)
if [[ ${1:-} == --dmg ]]; then
    bash scripts/release/make-dmg.sh 'dist/Dict Local AI.app' 'dist/Dict-Local-AI.dmg'
    (cd dist && shasum -a 256 Dict-Local-AI.dmg >> SHA256SUMS)
fi
echo 'The archive and checksum are ready in dist/.'
