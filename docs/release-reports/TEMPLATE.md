# Release Report Template

## 1) Release Meta
- release_id:
- image_tag:
- app_version:
- namespace:
- rollout_name:
- commit_sha:
- triggered_by:
- triggered_at:

## 2) Canary Progress
- step_20_status:
- step_50_status:
- step_100_status:
- analysisrun_name:
- analysisrun_phase:

## 3) SLO Inputs
- slo_error_rate_threshold_percent:
- slo_p95_seconds_threshold:
- slo_min_request_count:

## 4) Observed Metrics
- request_count_1m:
- error_rate_percent:
- p95_latency_seconds:

## 5) Decision
- result: PASS | FAIL
- reason:
- rollback_action:
- promotion_action:

## 6) AI Advisor
- summary:
- possible_root_causes:
- recommended_actions:
- confidence:
