#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

FIXTURE_DIR="${RELEASE_CONTRACT_FIXTURE_DIR:-tests/fixtures/release-contracts}"

if [[ ! -d "$FIXTURE_DIR" ]]; then
  echo "ERROR: fixture directory not found: $FIXTURE_DIR" >&2
  exit 1
fi

mapfile -t JSON_FILES < <(find "$FIXTURE_DIR" -type f -name "*.json" | sort)

if [[ "${#JSON_FILES[@]}" -eq 0 ]]; then
  echo "ERROR: no JSON fixtures found in $FIXTURE_DIR" >&2
  exit 1
fi

echo "===== validate release contract fixtures ====="
echo "fixtureDir=$FIXTURE_DIR"
echo "fixtureCount=${#JSON_FILES[@]}"

python3 scripts/validate-release-contracts.py "${JSON_FILES[@]}"

echo "===== release contract fixtures passed ====="
