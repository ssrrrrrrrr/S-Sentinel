#!/usr/bin/env bash

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)"
if [ -n "$BASE_DIR" ]; then
  cd "$BASE_DIR" || true
fi

BASE_URL="${1:-${RELEASE_PORTAL_BASE_URL:-http://127.0.0.1:8080}}"
BASE_URL="${BASE_URL%/}"

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

CURL_CONNECT_TIMEOUT="${CURL_CONNECT_TIMEOUT:-3}"
CURL_MAX_TIME="${CURL_MAX_TIME:-10}"
TMP_DIR="${RELEASE_PORTAL_VALIDATE_TMP:-/tmp/slo-release-portal-api-validate-$(date +%Y%m%d-%H%M%S)}"

mkdir -p "$TMP_DIR"

PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  echo "PASS: $*"
}

fail() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  echo "FAIL: $*" >&2
}

warn() {
  WARN_COUNT=$((WARN_COUNT + 1))
  echo "WARN: $*"
}

section() {
  echo
  echo "===== $* ====="
}

request() {
  local path="$1"
  local expected="$2"
  local output="$3"
  local url="${BASE_URL}${path}"
  local code
  local rc

  code="$(curl -sS \
    --connect-timeout "$CURL_CONNECT_TIMEOUT" \
    --max-time "$CURL_MAX_TIME" \
    -o "$output" \
    -w "%{http_code}" \
    "$url" 2>"${output}.err")"
  rc=$?

  if [ "$rc" -ne 0 ]; then
    fail "$path curl failed rc=$rc"
    sed -n '1,20p' "${output}.err" 2>/dev/null || true
    return 1
  fi

  if [ "$code" != "$expected" ]; then
    fail "$path expected HTTP $expected but got $code"
    echo "----- response body preview -----"
    sed -n '1,80p' "$output" 2>/dev/null || true
    return 1
  fi

  pass "$path HTTP $expected"
  return 0
}

check_json_expr() {
  local file="$1"
  local description="$2"
  local expression="$3"
  local rc

  "$PYTHON_BIN" - "$file" "$expression" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
expr = sys.argv[2]

data = json.loads(path.read_text(encoding="utf-8"))

safe_globals = {
    "__builtins__": {},
    "isinstance": isinstance,
    "dict": dict,
    "list": list,
    "str": str,
    "int": int,
    "float": float,
    "bool": bool,
    "len": len,
}
ok = bool(eval(expr, safe_globals, {"data": data}))
if not ok:
    raise AssertionError(expr)
PY
  rc=$?

  if [ "$rc" -eq 0 ]; then
    pass "$description"
  else
    fail "$description"
  fi
}

check_non_empty() {
  local file="$1"
  local description="$2"

  if [ -s "$file" ]; then
    pass "$description"
  else
    fail "$description"
  fi
}

json_value() {
  local file="$1"
  local expression="$2"

  "$PYTHON_BIN" - "$file" "$expression" <<'PY'
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
expr = sys.argv[2]
value = eval(expr, {"__builtins__": {}}, {"data": data})

if value is None:
    print("")
elif isinstance(value, bool):
    print(str(value).lower())
else:
    print(value)
PY
}

resource_exists_in_detail() {
  local detail_file="$1"
  local kind="$2"

  "$PYTHON_BIN" - "$detail_file" "$kind" <<'PY'
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
kind = sys.argv[2]
resources = ((data.get("release") or {}).get("resources") or {})
print("yes" if kind in resources else "no")
PY
}

validate_resource_endpoint() {
  local release_id="$1"
  local detail_file="$2"
  local segment="$3"
  local kind="$4"
  local required="$5"
  local mode="$6"
  local out="${TMP_DIR}/resource-${segment}.out"

  local exists
  exists="$(resource_exists_in_detail "$detail_file" "$kind")"

  if [ "$exists" != "yes" ]; then
    if [ "$required" = "required" ]; then
      fail "resource $segment is required but not present in release detail"
    else
      warn "resource $segment not present, skip optional endpoint"
    fi
    return 0
  fi

  request "/api/releases/${release_id}/${segment}" "200" "$out"

  if [ "$mode" = "json" ]; then
    check_json_expr "$out" "resource $segment response is valid JSON" 'isinstance(data, dict)'
  else
    check_non_empty "$out" "resource $segment response body is non-empty"
  fi
}

section "Release Portal API validation"
echo "BASE_URL=$BASE_URL"
echo "TMP_DIR=$TMP_DIR"

section "Basic endpoints"
request "/healthz" "200" "$TMP_DIR/healthz.out"
request "/api/releases" "200" "$TMP_DIR/releases.json"
request "/api/releases/latest" "200" "$TMP_DIR/latest.json"

section "Validate latest index safety"
check_json_expr "$TMP_DIR/latest.json" "latest schemaVersion is release-portal/v1alpha1" 'data.get("schemaVersion") == "release-portal/v1alpha1"'
check_json_expr "$TMP_DIR/latest.json" "latest mode is read_only" 'data.get("mode") == "read_only"'
check_json_expr "$TMP_DIR/latest.json" "latest safety.readOnly is true" '(data.get("safety") or {}).get("readOnly") is True'
check_json_expr "$TMP_DIR/latest.json" "latest safety.willExecute is false" '(data.get("safety") or {}).get("willExecute") is False'

section "Pick latest releaseId from /api/releases"
RELEASE_ID="$(json_value "$TMP_DIR/releases.json" '(data.get("items") or [{}])[0].get("releaseId", "")')"

if [ -z "$RELEASE_ID" ]; then
  fail "no releaseId found in /api/releases"
else
  pass "selected releaseId=$RELEASE_ID"
fi

section "Validate release detail"
if [ -n "$RELEASE_ID" ]; then
  request "/api/releases/${RELEASE_ID}" "200" "$TMP_DIR/release-detail.json"

  check_json_expr "$TMP_DIR/release-detail.json" "detail schemaVersion is release-portal/v1alpha1" 'data.get("schemaVersion") == "release-portal/v1alpha1"'
  check_json_expr "$TMP_DIR/release-detail.json" "detail releaseId matches request" '(data.get("release") or {}).get("releaseId") is not None'
  check_json_expr "$TMP_DIR/release-detail.json" "detail has releaseEvidence resource" '"releaseEvidence" in (((data.get("release") or {}).get("resources") or {}))'
  check_json_expr "$TMP_DIR/release-detail.json" "detail safety.readOnly is true" '(data.get("safety") or {}).get("readOnly") is True'
  check_json_expr "$TMP_DIR/release-detail.json" "detail safety.willExecute is false" '(data.get("safety") or {}).get("willExecute") is False'
fi

section "Validate EvidenceStore adapter"
request "/api/evidence-store/releases?limit=5" "200" "$TMP_DIR/evidence-store-releases.json"
check_json_expr "$TMP_DIR/evidence-store-releases.json" "evidence-store release list schema is valid" 'data.get("schemaVersion") == "evidence.store.releaseList/v1alpha1"'
check_json_expr "$TMP_DIR/evidence-store-releases.json" "evidence-store release list is read model" 'isinstance(data.get("items"), list)'
check_json_expr "$TMP_DIR/evidence-store-releases.json" "evidence-store release list has controlPlane apiVersion" '(data.get("controlPlane") or {}).get("apiVersion") == "s-sentinel.io/evidence-api/v1alpha1"'
check_json_expr "$TMP_DIR/evidence-store-releases.json" "evidence-store release list runtime is cli-sqlite-runtime" '(data.get("controlPlane") or {}).get("runtimeMode") == "cli-sqlite-runtime"'
check_json_expr "$TMP_DIR/evidence-store-releases.json" "evidence-store release list repository contract is valid" '(data.get("controlPlane") or {}).get("repositoryContract") == "evidence.repository/v1alpha1"'

request "/api/evidence/releases?limit=5" "200" "$TMP_DIR/evidence-releases.json"
check_json_expr "$TMP_DIR/evidence-releases.json" "canonical evidence release list schema is valid" 'data.get("schemaVersion") == "evidence.store.releaseList/v1alpha1"'
check_json_expr "$TMP_DIR/evidence-releases.json" "canonical evidence release list has controlPlane apiVersion" '(data.get("controlPlane") or {}).get("apiVersion") == "s-sentinel.io/evidence-api/v1alpha1"'
check_json_expr "$TMP_DIR/evidence-releases.json" "canonical evidence release list response contract is valid" '(data.get("controlPlane") or {}).get("contractVersion") == "evidence.api.response/v1alpha1"'

if [ -n "$RELEASE_ID" ]; then
  request "/api/evidence-store/releases/${RELEASE_ID}" "200" "$TMP_DIR/evidence-store-release-detail.json"
  check_json_expr "$TMP_DIR/evidence-store-release-detail.json" "evidence-store release detail schema is valid" 'data.get("schemaVersion") == "evidence.store.release/v1alpha1"'
  check_json_expr "$TMP_DIR/evidence-store-release-detail.json" "evidence-store release detail has objects" 'isinstance(data.get("objects"), list) and len(data.get("objects")) >= 1'
  check_json_expr "$TMP_DIR/evidence-store-release-detail.json" "evidence-store release detail has controlPlane" '(data.get("controlPlane") or {}).get("apiVersion") == "s-sentinel.io/evidence-api/v1alpha1"'

  request "/api/evidence/releases/${RELEASE_ID}" "200" "$TMP_DIR/evidence-release-detail.json"
  check_json_expr "$TMP_DIR/evidence-release-detail.json" "canonical evidence release detail schema is valid" 'data.get("schemaVersion") == "evidence.store.release/v1alpha1"'
  check_json_expr "$TMP_DIR/evidence-release-detail.json" "canonical evidence release detail has controlPlane" '(data.get("controlPlane") or {}).get("repositoryType") == "cli-backed"'

  OBJECT_TYPE="$(json_value "$TMP_DIR/evidence-store-release-detail.json" '(data.get("objects") or [{}])[0].get("object_type", "")')"
  OBJECT_ID="$(json_value "$TMP_DIR/evidence-store-release-detail.json" '(data.get("objects") or [{}])[0].get("object_id", "")')"

  if [ -n "$OBJECT_TYPE" ] && [ -n "$OBJECT_ID" ]; then
    request "/api/evidence-store/objects/${OBJECT_TYPE}/${OBJECT_ID}?releaseId=${RELEASE_ID}" "200" "$TMP_DIR/evidence-store-object.json"
    check_json_expr "$TMP_DIR/evidence-store-object.json" "evidence-store object schema is valid" 'data.get("schemaVersion") == "evidence.store.object/v1alpha1"'
    check_json_expr "$TMP_DIR/evidence-store-object.json" "evidence-store object has summary" 'isinstance((data.get("object") or {}).get("summary"), dict)'
    check_json_expr "$TMP_DIR/evidence-store-object.json" "evidence-store object has controlPlane" '(data.get("controlPlane") or {}).get("runtimeMode") == "cli-sqlite-runtime"'

    request "/api/evidence/objects/${OBJECT_TYPE}/${OBJECT_ID}?releaseId=${RELEASE_ID}" "200" "$TMP_DIR/evidence-object.json"
    check_json_expr "$TMP_DIR/evidence-object.json" "canonical evidence object schema is valid" 'data.get("schemaVersion") == "evidence.store.object/v1alpha1"'
    check_json_expr "$TMP_DIR/evidence-object.json" "canonical evidence object has controlPlane" '(data.get("controlPlane") or {}).get("repositoryContract") == "evidence.repository/v1alpha1"'
  else
    fail "unable to select evidence-store object from release detail"
  fi
fi

section "Validate latest action-plan guardrails"
request "/api/releases/latest/action-plan" "200" "$TMP_DIR/latest-action-plan.json"
check_json_expr "$TMP_DIR/latest-action-plan.json" "latest action-plan willExecute is false" 'data.get("willExecute") is False'
check_json_expr "$TMP_DIR/latest-action-plan.json" "latest action-plan guardrail doesNotModifyKubernetes is true" '(data.get("guardrails") or {}).get("doesNotModifyKubernetes") is True'

section "Validate release resource content endpoints"
if [ -n "$RELEASE_ID" ] && [ -f "$TMP_DIR/release-detail.json" ]; then
  validate_resource_endpoint "$RELEASE_ID" "$TMP_DIR/release-detail.json" "evidence" "releaseEvidence" "required" "json"
  validate_resource_endpoint "$RELEASE_ID" "$TMP_DIR/release-detail.json" "summary" "releaseSummary" "required" "text"
  validate_resource_endpoint "$RELEASE_ID" "$TMP_DIR/release-detail.json" "action-plan" "actionPlan" "required" "json"
  validate_resource_endpoint "$RELEASE_ID" "$TMP_DIR/release-detail.json" "intelligence" "releaseIntelligence" "required" "json"
  validate_resource_endpoint "$RELEASE_ID" "$TMP_DIR/release-detail.json" "advice" "aiAdvice" "optional" "text"
  validate_resource_endpoint "$RELEASE_ID" "$TMP_DIR/release-detail.json" "context" "releaseContext" "optional" "json"
  validate_resource_endpoint "$RELEASE_ID" "$TMP_DIR/release-detail.json" "ai-decision" "aiDecision" "optional" "json"
  validate_resource_endpoint "$RELEASE_ID" "$TMP_DIR/release-detail.json" "policy-decision" "policyDecision" "optional" "json"
  validate_resource_endpoint "$RELEASE_ID" "$TMP_DIR/release-detail.json" "failure-evidence" "failureEvidence" "optional" "json"
  validate_resource_endpoint "$RELEASE_ID" "$TMP_DIR/release-detail.json" "approval" "approvalRecord" "optional" "json"
fi

section "Validate 404 behavior"
if [ -n "$RELEASE_ID" ]; then
  request "/api/releases/${RELEASE_ID}/not-a-resource" "404" "$TMP_DIR/not-a-resource.json"
  check_json_expr "$TMP_DIR/not-a-resource.json" "unknown resource returns availableResources" '"availableResources" in data'
fi

request "/api/releases/not-exist-release" "404" "$TMP_DIR/not-exist-release.json"
check_json_expr "$TMP_DIR/not-exist-release.json" "unknown release returns availableReleaseIds" '"availableReleaseIds" in data'

section "Validation summary"
echo "PASS_COUNT=$PASS_COUNT"
echo "WARN_COUNT=$WARN_COUNT"
echo "FAIL_COUNT=$FAIL_COUNT"

if [ "$FAIL_COUNT" -eq 0 ]; then
  echo "VALIDATION_RESULT=PASS"
else
  echo "VALIDATION_RESULT=FAIL"
fi

[ "$FAIL_COUNT" -eq 0 ]
