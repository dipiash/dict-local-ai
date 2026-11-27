#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
for tool in swiftlint shellcheck; do
  command -v "$tool" >/dev/null || { echo "Missing $tool; run task setup." >&2; exit 1; }
done
python3 scripts/development/check-swift-dependencies.py
swift format lint --strict --recursive Sources Tests Package.swift
swiftlint lint --strict --config .swiftlint.yml
shellcheck --external-sources --shell=bash install.sh scripts/*/*.sh
for script in install.sh scripts/*/*.sh; do bash -n "$script"; done
