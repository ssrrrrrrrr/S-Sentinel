#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

OUT="/tmp/ssentinel-real-pr-safety-summary.txt"
bash scripts/print-gitops-real-pr-safety-summary.sh > "$OUT"

grep -q "Real GitOps PR Safety Summary" "$OUT"

grep -q "push-branch" "$OUT"
grep -q "create-pr" "$OUT"
grep -q "cleanup-pr" "$OUT"

grep -q "S_SENTINEL_ALLOW_GITHUB_WRITE=true" "$OUT"
grep -q "S_SENTINEL_GITHUB_WRITE_OPERATION=push-branch" "$OUT"
grep -q "S_SENTINEL_GITHUB_WRITE_OPERATION=create-pr" "$OUT"
grep -q "S_SENTINEL_GITHUB_WRITE_OPERATION=cleanup-pr" "$OUT"

grep -q "no kubectl" "$OUT"
grep -q "no PR merge" "$OUT"
grep -q "no direct Kubernetes runtime mutation" "$OUT"

echo "PASS gitops real-pr safety summary"
