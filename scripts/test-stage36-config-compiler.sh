#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "===== Stage 36: Config Compiler acceptance ====="

echo
echo "===== syntax check ====="
bash -n scripts/compile-release-config.sh
bash -n scripts/test-config-compiler.sh
bash -n scripts/test-config-compiler-drift.sh

echo
echo "===== compiler multi-env test ====="
./scripts/test-config-compiler.sh

echo
echo "===== compiler drift test ====="
./scripts/test-config-compiler-drift.sh

echo
echo "PASS: Stage 36 Config Compiler acceptance passed"
