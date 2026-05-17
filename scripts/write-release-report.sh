#!/bin/bash
set -euo pipefail

OUTPUT_DIR="${OUTPUT_DIR:-docs/release-reports}"
mkdir -p "${OUTPUT_DIR}"

ts="$(date +%Y%m%d-%H%M%S)"
release_id="${RELEASE_ID:-${IMAGE_TAG:-unknown}-${ts}}"
report_file="${OUTPUT_DIR}/${release_id}.md"

cat > "${report_file}" <<REPORT
# Release Report

## 1) Release Meta
- release_id: ${release_id}
- image_tag: ${IMAGE_TAG:-unknown}
- app_version: ${APP_VERSION:-unknown}
- namespace: ${NAMESPACE:-slo-rollout}
- rollout_name: ${ROLLOUT_NAME:-demo-app}
- commit_sha: ${COMMIT_SHA:-$(git rev-parse --short HEAD 2>/dev/null || echo unknown)}
- triggered_by: ${TRIGGERED_BY:-manual}
- triggered_at: ${TRIGGERED_AT:-$(date -Is)}

## 2) Canary Progress
- step_20_status: ${STEP_20_STATUS:-unknown}
- step_50_status: ${STEP_50_STATUS:-unknown}
- step_100_status: ${STEP_100_STATUS:-unknown}
- analysisrun_name: ${ANALYSISRUN_NAME:-unknown}
- analysisrun_phase: ${ANALYSISRUN_PHASE:-unknown}

## 3) SLO Inputs
- slo_error_rate_threshold_percent: ${SLO_ERROR_RATE_THRESHOLD:-5}
- slo_p95_seconds_threshold: ${SLO_P95_SECONDS_THRESHOLD:-0.3}
- slo_min_request_count: ${SLO_MIN_REQUEST_COUNT:-20}

## 4) Observed Metrics
- request_count_1m: ${OBS_REQUEST_COUNT_1M:-unknown}
- error_rate_percent: ${OBS_ERROR_RATE_PERCENT:-unknown}
- p95_latency_seconds: ${OBS_P95_LATENCY_SECONDS:-unknown}

## 5) Decision
- result: ${RELEASE_RESULT:-IN_PROGRESS}
- reason: ${RELEASE_REASON:-Rollout result not provided by caller}
- rollback_action: ${ROLLBACK_ACTION:-none}
- promotion_action: ${PROMOTION_ACTION:-none}

## 6) AI Advisor
- summary: ${AI_SUMMARY:-not available}
- possible_root_causes: ${AI_ROOT_CAUSES:-not available}
- recommended_actions: ${AI_RECOMMENDED_ACTIONS:-not available}
- confidence: ${AI_CONFIDENCE:-not available}
REPORT

echo "Release report generated: ${report_file}"
