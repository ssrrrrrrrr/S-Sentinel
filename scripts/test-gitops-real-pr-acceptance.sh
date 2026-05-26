#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [ "${S_SENTINEL_ALLOW_GITHUB_WRITE:-false}" = "true" ]; then
  echo "ERROR: acceptance test must not run with S_SENTINEL_ALLOW_GITHUB_WRITE=true" >&2
  echo "This acceptance entry is local-only and must not create/close real GitHub PRs." >&2
  exit 1
fi

export S_SENTINEL_ALLOW_GITHUB_WRITE=false

echo "===== syntax checks ====="
bash -n scripts/test-gitops-real-pr.sh
bash -n scripts/test-gitops-real-pr-safety-contract.sh
bash -n scripts/test-evidence-store-gitops-real-pr.sh
bash -n scripts/test-evidence-record-gitops-real-pr-links.sh
bash -n scripts/test-gitops-real-pr-evidence-completeness.sh

echo "===== real PR local safety suite ====="
timeout 180s bash scripts/test-gitops-real-pr.sh

echo "===== real PR evidence completeness ====="
bash scripts/test-gitops-real-pr-evidence-completeness.sh

echo "===== real PR EvidenceStore indexing ====="
bash scripts/test-evidence-store-gitops-real-pr.sh

echo "===== real PR EvidenceRecord links ====="
bash scripts/test-evidence-record-gitops-real-pr-links.sh

echo "===== python compile ====="
python3 -m py_compile scripts/evidence-store.py scripts/validate-release-contracts.py

echo "===== watcher portal/evidence integration tests ====="
(
  cd watcher
  go test ./...
)

echo "PASS gitops real-pr acceptance"
