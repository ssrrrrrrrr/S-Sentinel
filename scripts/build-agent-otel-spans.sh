#!/usr/bin/env bash
set -euo pipefail

REPORT_DIR="${RELEASE_REPORT_DIR:-docs/release-reports}"
OUTPUT_DIR="${AGENT_OTEL_OUTPUT_DIR:-$REPORT_DIR}"
OUTPUT_FILE="${AGENT_OTEL_OUTPUT_FILE:-}"

usage() {
  cat <<'USAGE'
Usage:
  scripts/build-agent-otel-spans.sh [latest|AGENT_TRACE_JSON]

Environment:
  RELEASE_REPORT_DIR       Optional report directory. Defaults to docs/release-reports.
  AGENT_OTEL_OUTPUT_DIR    Optional output directory. Defaults to RELEASE_REPORT_DIR.
  AGENT_OTEL_OUTPUT_FILE   Optional exact output file.
  PYTHON_BIN               Optional python runtime.

Behavior:
  - Reads agent-trace-*.json as the trace source.
  - Generates otel-span-bundle-*.json and otel-span-bundle-latest.json.
  - Local file only: does not send telemetry, call collectors, modify cluster, commit, or push.
USAGE
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

if [ "$#" -gt 1 ]; then
  echo "ERROR: too many arguments" >&2
  usage >&2
  exit 1
fi

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

INPUT="${1:-latest}"

ARGS=(
  "$INPUT"
  --report-dir "$REPORT_DIR"
  --output-dir "$OUTPUT_DIR"
)

if [ -n "$OUTPUT_FILE" ]; then
  ARGS+=(--output-file "$OUTPUT_FILE")
fi

"$PYTHON_BIN" scripts/agent-trace-to-otel.py "${ARGS[@]}"
