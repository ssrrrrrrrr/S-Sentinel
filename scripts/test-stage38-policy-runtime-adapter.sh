#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "===== Stage 38 syntax checks ====="
python3 -m py_compile scripts/policy-runtime-adapter.py scripts/evidence-store.py
bash -n scripts/ai-release-advisor.sh
bash -n scripts/test-policy-runtime-adapter.sh
bash -n scripts/test-policy-guard.sh
bash -n scripts/test-evidence-store.sh
rm -rf scripts/__pycache__
echo "PASS: syntax checks passed"

echo
echo "===== Stage 38 adapter contract regression ====="
./scripts/test-policy-runtime-adapter.sh
rm -rf scripts/__pycache__
echo "PASS: policy runtime adapter regression passed"

echo
echo "===== Stage 38 legacy policy guard regression ====="
./scripts/test-policy-guard.sh
echo "PASS: legacy policy guard regression passed"

echo
echo "===== Stage 38 EvidenceStore compatibility regression ====="
./scripts/test-evidence-store.sh
rm -rf scripts/__pycache__
echo "PASS: EvidenceStore compatibility regression passed"

echo
echo "===== Stage 38 integration checks ====="
grep -q "POLICY_RUNTIME_ADAPTER" scripts/ai-release-advisor.sh
grep -q "POLICY_EVALUATOR_MODE=\"runtime-adapter\"" scripts/ai-release-advisor.sh
grep -q -- "--decision-output" scripts/ai-release-advisor.sh
grep -q '"object_type": "policyInput"' scripts/evidence-store.py
grep -q '"object_type": "policyRuntimeResult"' scripts/evidence-store.py
grep -q "policy.input/v1alpha1" scripts/policy-runtime-adapter.py
grep -q "policy.runtime.result/v1alpha1" scripts/policy-runtime-adapter.py
echo "PASS: Stage 38 integration checks passed"

echo
echo "PASS: Stage 38 Policy Runtime Adapter acceptance passed"
