#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$BASE_DIR"

REPORT_DIR="${RELEASE_REPORT_DIR:-docs/release-reports}"
TOOL="${1:-}"
shift || true

usage() {
  cat <<'USAGE'
Usage:
  scripts/agent-tool-router.sh <tool> [args]

Safe tools:
  list-tools
  get-latest-release-summary
  get-latest-release-evidence
  get-latest-failure-evidence [json|markdown]
  collect-failure-evidence [latest|RELEASE_CONTEXT_JSON]
  evaluate-change-risk [latest|CHANGE_CONTEXT_JSON]
  build-action-plan [latest|RELEASE_EVIDENCE_JSON]
  build-release-memory
  query-release-memory [summary|latest|failures|similar-failure METRICS]
  run-offline-eval

Safety:
  - This router only exposes advisory/read/evaluation tools.
  - It does not rollback, promote, patch, delete, modify GitOps, modify Kubernetes, build images, commit, or push.
USAGE
}

list_tools() {
  cat <<'TOOLS'
list-tools
get-latest-release-summary
get-latest-release-evidence
get-latest-failure-evidence [json|markdown]
collect-failure-evidence [latest|RELEASE_CONTEXT_JSON]
evaluate-change-risk [latest|CHANGE_CONTEXT_JSON]
build-action-plan [latest|RELEASE_EVIDENCE_JSON]
build-release-memory
query-release-memory [summary|latest|failures|similar-failure METRICS]
run-offline-eval
TOOLS
}

latest_file() {
  local pattern="$1"
  ls -t $pattern 2>/dev/null | head -1 || true
}

require_file() {
  local file="$1"
  local label="$2"

  if [ -z "$file" ] || [ ! -f "$file" ]; then
    echo "ERROR: $label not found: ${file:-not provided}" >&2
    exit 1
  fi
}

print_file_with_header() {
  local label="$1"
  local file="$2"

  require_file "$file" "$label"

  echo "toolStatus: success"
  echo "toolName: $TOOL"
  echo "toolOutputFile: $file"
  echo
  cat "$file"
}

resolve_release_context() {
  local input="${1:-latest}"

  if [ "$input" = "latest" ]; then
    input="$(latest_file "$REPORT_DIR/release-context-*.json")"
  fi

  require_file "$input" "release context"
  echo "$input"
}

resolve_change_context() {
  local input="${1:-latest}"

  if [ "$input" = "latest" ]; then
    input="$REPORT_DIR/change-context-latest.json"
  fi

  require_file "$input" "change context"
  echo "$input"
}

resolve_release_evidence() {
  local input="${1:-latest}"

  if [ "$input" = "latest" ]; then
    input="$(latest_file "$REPORT_DIR/release-evidence-*.json")"
  fi

  require_file "$input" "release evidence"
  echo "$input"
}

case "$TOOL" in
  ""|-h|--help|help)
    usage
    ;;

  list-tools)
    list_tools
    ;;

  get-latest-release-summary)
    file="$(latest_file "$REPORT_DIR/release-summary-*.md")"
    print_file_with_header "latest release summary" "$file"
    ;;

  get-latest-release-evidence)
    file="$(latest_file "$REPORT_DIR/release-evidence-*.json")"
    print_file_with_header "latest release evidence" "$file"
    ;;

  get-latest-failure-evidence)
    format="${1:-json}"

    case "$format" in
      json)
        file="$(latest_file "$REPORT_DIR/failure-evidence-*.json")"
        ;;
      markdown|md)
        file="$(latest_file "$REPORT_DIR/failure-evidence-*.md")"
        ;;
      *)
        echo "ERROR: unsupported failure evidence format: $format" >&2
        echo "Supported formats: json, markdown" >&2
        exit 1
        ;;
    esac

    print_file_with_header "latest failure evidence" "$file"
    ;;

  collect-failure-evidence)
    context_file="$(resolve_release_context "${1:-latest}")"

    echo "toolStatus: running"
    echo "toolName: $TOOL"
    echo "releaseContext: $context_file"
    echo "executionMode: advisory_only"
    echo "collectK8sEvidence: ${COLLECT_K8S_EVIDENCE:-false}"
    echo

    FAILURE_EVIDENCE_OUTPUT_DIR="${FAILURE_EVIDENCE_OUTPUT_DIR:-$REPORT_DIR}" \
    COLLECT_K8S_EVIDENCE="${COLLECT_K8S_EVIDENCE:-false}" \
      ./scripts/collect-failure-evidence.sh "$context_file"
    ;;

  evaluate-change-risk)
    change_context_file="$(resolve_change_context "${1:-latest}")"

    echo "toolStatus: running"
    echo "toolName: $TOOL"
    echo "changeContext: $change_context_file"
    echo "executionMode: advisory_only"
    echo

    ./scripts/evaluate-change-risk.sh "$change_context_file"
    ;;

  build-action-plan)
    release_evidence_file="$(resolve_release_evidence "${1:-latest}")"

    echo "toolStatus: running"
    echo "toolName: $TOOL"
    echo "releaseEvidence: $release_evidence_file"
    echo "executionMode: dry_run"
    echo "willExecute: false"
    echo

    ./scripts/build-action-plan.sh "$release_evidence_file"
    ;;

  build-release-memory)
    echo "toolStatus: running"
    echo "toolName: $TOOL"
    echo "executionMode: advisory_only"
    echo

    ./scripts/build-release-memory.sh
    ;;

  query-release-memory)
    echo "toolStatus: running"
    echo "toolName: $TOOL"
    echo "executionMode: advisory_only"
    echo

    ./scripts/query-release-memory.sh "${1:-summary}" "${2:-}" "${3:-}"
    ;;

  run-offline-eval)
    echo "toolStatus: running"
    echo "toolName: $TOOL"
    echo "executionMode: advisory_only"
    echo

    ./scripts/test-release-pipeline.sh
    ;;

  *)
    echo "ERROR: unknown tool: $TOOL" >&2
    echo >&2
    usage >&2
    exit 1
    ;;
esac
