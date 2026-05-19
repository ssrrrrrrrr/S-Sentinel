#!/usr/bin/env bash
set -euo pipefail

if [ -n "${RELEASE_REPORT_DIR:-}" ]; then
  REPORT_DIR="$RELEASE_REPORT_DIR"
elif [ -d "/data/nfs/slo-rollout-watcher/reports" ]; then
  REPORT_DIR="/data/nfs/slo-rollout-watcher/reports"
else
  REPORT_DIR="docs/release-reports"
fi

MEMORY_FILE="${RELEASE_MEMORY_FILE:-$REPORT_DIR/release-memory.jsonl}"
QUERY="${1:-latest}"
ARG="${2:-}"

usage() {
  cat <<'USAGE'
Usage:
  scripts/query-release-memory.sh <query> [args]

Queries:
  summary
  latest [N]
  failures [N]
  similar-failure <metric1,metric2,...> [N]

Examples:
  scripts/query-release-memory.sh summary
  scripts/query-release-memory.sh latest
  scripts/query-release-memory.sh failures 5
  scripts/query-release-memory.sh similar-failure error-rate,p95-latency 5
USAGE
}

if [ "$QUERY" = "-h" ] || [ "$QUERY" = "--help" ]; then
  usage
  exit 0
fi

if [ ! -f "$MEMORY_FILE" ]; then
  ./scripts/build-release-memory.sh >/dev/null
fi

python3 - "$MEMORY_FILE" "$QUERY" "$ARG" "${3:-}" <<'PY'
import json
import sys
from pathlib import Path

memory_file = Path(sys.argv[1])
query = sys.argv[2]
arg = sys.argv[3]
arg2 = sys.argv[4]

records = []
if memory_file.exists():
    for line in memory_file.read_text(encoding="utf-8").splitlines():
        if line.strip():
            records.append(json.loads(line))

records = sorted(records, key=lambda r: r.get("generatedAt") or "")

def latest_items(items, n=1):
    return list(reversed(items))[:n]

def emit(obj):
    print(json.dumps(obj, ensure_ascii=False, indent=2))

if query == "summary":
    failures = [r for r in records if str(r.get("releaseResult", "")).startswith("FAIL")]
    passes = [r for r in records if r.get("releaseResult") == "PASS"]
    emit({
        "query": "summary",
        "memoryFile": str(memory_file),
        "recordCount": len(records),
        "passCount": len(passes),
        "failureCount": len(failures),
        "latestRelease": records[-1] if records else None,
        "latestFailure": failures[-1] if failures else None,
    })

elif query == "latest":
    n = int(arg or "1")
    emit({
        "query": "latest",
        "count": n,
        "records": latest_items(records, n),
    })

elif query == "failures":
    n = int(arg or "10")
    failures = [r for r in records if str(r.get("releaseResult", "")).startswith("FAIL")]
    emit({
        "query": "failures",
        "count": n,
        "records": latest_items(failures, n),
    })

elif query == "similar-failure":
    if not arg:
        raise SystemExit("ERROR: similar-failure requires metrics, for example: error-rate,p95-latency")

    n = int(arg2 or "10")
    wanted = {x.strip() for x in arg.split(",") if x.strip()}

    matches = []
    for r in records:
        if not str(r.get("releaseResult", "")).startswith("FAIL"):
            continue
        metrics = set(r.get("failedMetrics") or [])
        overlap = sorted(wanted & metrics)
        if not overlap:
            continue
        item = dict(r)
        item["similarity"] = {
            "queryMetrics": sorted(wanted),
            "matchedMetrics": overlap,
            "score": len(overlap),
            "exactMetricSetMatch": metrics == wanted,
        }
        matches.append(item)

    matches = sorted(
        matches,
        key=lambda r: (r.get("similarity", {}).get("score", 0), r.get("generatedAt") or ""),
        reverse=True,
    )[:n]

    emit({
        "query": "similar-failure",
        "queryMetrics": sorted(wanted),
        "count": len(matches),
        "records": matches,
    })

else:
    raise SystemExit(f"ERROR: unknown query: {query}")
PY
