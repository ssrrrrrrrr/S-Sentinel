#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [ -z "${PYTHON_BIN:-}" ]; then
  if command -v python3 >/dev/null 2>&1; then
    PYTHON_BIN="python3"
  elif command -v python >/dev/null 2>&1; then
    PYTHON_BIN="python"
  else
    echo "ERROR: python runtime not found. Set PYTHON_BIN=/path/to/python." >&2
    exit 1
  fi
fi

export PYTHON_BIN

echo "===== Stage 36: Config Compiler acceptance ====="

echo
echo "===== syntax check ====="
bash -n scripts/compile-release-config.sh
bash -n scripts/validate-compiler-profile.sh
bash -n scripts/test-stage46-compiler-profile-validation.sh
bash -n scripts/test-config-compiler.sh
bash -n scripts/test-config-compiler-drift.sh
bash -n scripts/test-release-gitops-compiler-integration.sh

echo
echo "===== compiler profile validation ====="
./scripts/validate-compiler-profile.sh

echo
echo "===== compiler multi-env test ====="
./scripts/test-config-compiler.sh

echo
echo "===== compiler drift test ====="
./scripts/test-config-compiler-drift.sh

echo
echo "===== release script compiler integration test ====="
./scripts/test-release-gitops-compiler-integration.sh

echo
echo "PASS: Stage 36 Config Compiler acceptance passed"
