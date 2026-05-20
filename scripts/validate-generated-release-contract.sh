#!/usr/bin/env bash
set -u

TARGET_FILE="${1:-}"
MODE="${RELEASE_CONTRACT_VALIDATION_MODE:-warn}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

VALIDATOR="${RELEASE_CONTRACT_VALIDATOR:-$SCRIPT_DIR/validate-release-contracts.py}"
SCHEMA_DIR="${RELEASE_CONTRACT_SCHEMA_DIR:-$ROOT_DIR/schemas}"

warn_or_fail() {
  local message="$1"

  if [ "$MODE" = "strict" ]; then
    echo "ERROR: $message" >&2
    exit 1
  fi

  echo "WARN: $message" >&2
  exit 0
}

if [ "$MODE" = "off" ]; then
  exit 0
fi

if [ -z "$TARGET_FILE" ]; then
  warn_or_fail "release contract validation skipped: target file is empty"
fi

if [ ! -f "$TARGET_FILE" ]; then
  warn_or_fail "release contract validation skipped: target file not found: $TARGET_FILE"
fi

PYTHON_BIN="${PYTHON_BIN:-python3}"

if ! command -v "$PYTHON_BIN" >/dev/null 2>&1; then
  if command -v python >/dev/null 2>&1; then
    PYTHON_BIN="python"
  else
    warn_or_fail "release contract validation skipped: python3/python not found"
  fi
fi

if [ ! -f "$VALIDATOR" ]; then
  warn_or_fail "release contract validation skipped: validator not found: $VALIDATOR"
fi

if [ ! -d "$SCHEMA_DIR" ]; then
  warn_or_fail "release contract validation skipped: schema dir not found: $SCHEMA_DIR"
fi

echo "===== release contract validation ====="
echo "mode=$MODE"
echo "target=$TARGET_FILE"

if "$PYTHON_BIN" "$VALIDATOR" --schema-dir "$SCHEMA_DIR" "$TARGET_FILE"; then
  echo "Release contract validation passed: $TARGET_FILE"
  exit 0
fi

rc=$?

if [ "$MODE" = "strict" ]; then
  echo "ERROR: release contract validation failed: $TARGET_FILE" >&2
  exit "$rc"
fi

echo "WARN: release contract validation failed but continuing in warn mode: $TARGET_FILE" >&2
exit 0
