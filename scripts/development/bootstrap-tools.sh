#!/usr/bin/env bash
set -euo pipefail
if [[ $(uname -s) != Darwin ]]; then
  echo 'On Linux use the Swift toolchain, Python 3 and SQLite development headers.' >&2
  exit 1
fi
command -v brew >/dev/null || { echo 'Install Homebrew: https://brew.sh' >&2; exit 1; }
for formula in swiftlint shellcheck go-task gitleaks; do
  brew list --versions "$formula" >/dev/null 2>&1 || brew install "$formula"
done
swift --version
swiftlint version
shellcheck --version
task --version
gitleaks version
