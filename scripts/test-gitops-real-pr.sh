#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "===== test gitops real PR plan ====="
bash scripts/test-gitops-real-pr-plan.sh

echo "===== test gitops real PR local flow ====="
bash scripts/test-gitops-real-pr-local-flow.sh

echo "===== test controlled write guardrails ====="
bash scripts/test-gitops-real-pr-controlled-write-guardrails.sh

echo "===== test real PR safety contract ====="
bash scripts/test-gitops-real-pr-safety-contract.sh

echo "PASS test-gitops-real-pr"
