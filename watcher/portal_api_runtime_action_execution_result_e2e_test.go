package main

import (
	"net/http"
	"os"
	"path/filepath"
	"testing"
)

func TestRuntimeActionExecutionResultEvidenceStoreAndPortalLatestResource(t *testing.T) {
	root, err := filepath.Abs("..")
	if err != nil {
		t.Fatalf("resolve repo root: %v", err)
	}

	tempRepo := t.TempDir()
	tempDB := filepath.Join(t.TempDir(), "evidence-store.db")
	t.Setenv("S_SENTINEL_EVIDENCE_STORE_DB", tempDB)

	scriptSource := filepath.Join(root, "scripts", "evidence-store.py")
	scriptData, err := os.ReadFile(scriptSource)
	if err != nil {
		t.Fatalf("read evidence-store.py: %v", err)
	}

	scriptDir := filepath.Join(tempRepo, "scripts")
	if err := os.MkdirAll(scriptDir, 0755); err != nil {
		t.Fatalf("create script dir: %v", err)
	}
	if err := os.WriteFile(filepath.Join(scriptDir, "evidence-store.py"), scriptData, 0755); err != nil {
		t.Fatalf("write evidence-store.py: %v", err)
	}

	reportDir := filepath.Join(tempRepo, "docs", "release-reports")
	if err := os.MkdirAll(reportDir, 0755); err != nil {
		t.Fatalf("create report dir: %v", err)
	}

	releaseID := "20260527-050505"
	resultID := "raer-" + releaseID
	preflightID := "rap-" + releaseID
	requestID := "rarq-" + releaseID
	recommendationID := "rar-" + releaseID

	releaseEvidence := `{
  "schemaVersion": "release.evidence/v1alpha1",
  "generatedBy": "portal_api_runtime_action_execution_result_e2e_test.go",
  "releaseId": "` + releaseID + `",
  "releaseResult": "STOP_PROMOTION",
  "policyDecision": "REQUIRE_HUMAN_APPROVAL",
  "service": "demo-app",
  "namespace": "slo-rollout",
  "env": "dev",
  "artifacts": {
    "runtimeActionExecutionResult": "runtime-action-execution-result-` + releaseID + `.json"
  }
}`

	result := `{
  "schemaVersion": "runtime.action.execution.result/v1alpha1",
  "runtimeActionExecutionResultId": "` + resultID + `",
  "generatedBy": "portal_api_runtime_action_execution_result_e2e_test.go",
  "generatedAt": "2026-05-27T05:05:05Z",
  "mode": "controlled_runtime_action_result",
  "sourceRuntimeActionPreflightId": "` + preflightID + `",
  "sourceRuntimeActionRequestId": "` + requestID + `",
  "release": {
    "releaseId": "` + releaseID + `",
    "service": "demo-app",
    "namespace": "slo-rollout",
    "env": "dev",
    "policyDecision": "REQUIRE_HUMAN_APPROVAL",
    "finalAction": "STOP_PROMOTION"
  },
  "target": {
    "cluster": "local-dev",
    "namespace": "slo-rollout",
    "rolloutName": "demo-app",
    "service": "demo-app",
    "env": "dev"
  },
  "action": {
    "requestedAction": "PAUSE_ROLLOUT",
    "actionStatus": "EXECUTION_SUCCEEDED",
    "commandMode": "kubectl_patch_rollout_spec_paused",
    "commandWillExecute": true,
    "commandExitCode": 0
  },
  "executor": {
    "executorName": "runtime-pause-executor",
    "adapter": "runtime-pause"
  },
  "writeGate": {
    "preflightStatus": "PREFLIGHT_PASSED",
    "eligibilityStatus": "ELIGIBLE_FOR_CONTROLLED_EXECUTOR",
    "finalExecuteEnabled": true,
    "writeAllowed": true
  },
  "beforeSnapshot": {
    "rolloutPhase": "Degraded",
    "analysisStatus": "Failed"
  },
  "result": {
    "requestedAction": "PAUSE_ROLLOUT",
    "actionStatus": "EXECUTION_SUCCEEDED",
    "executionStatus": "SUCCEEDED",
    "didPause": true,
    "attemptedKubernetesMutation": true,
    "mutatedKubernetes": true,
    "mutatedGitOps": false
  },
  "receipt": {
    "didModifyKubernetes": true,
    "didModifyGitOps": false
  },
  "evidenceRefs": {
    "runtimeActionPreflight": "runtime-action-preflight-` + releaseID + `.json",
    "runtimeActionRequest": "runtime-action-request-` + releaseID + `.json",
    "runtimeActionRecommendation": "runtime-action-recommendation-` + releaseID + `.json",
    "rolloutRuntimeInspect": "rollout-runtime-inspect-` + releaseID + `.json",
    "sourceRuntimeActionPreflightId": "` + preflightID + `",
    "sourceRuntimeActionRequestId": "` + requestID + `",
    "sourceRuntimeActionRecommendationId": "` + recommendationID + `",
    "sourceRolloutRuntimeInspectId": "rti-` + releaseID + `"
  },
  "guardrails": {
    "willExecute": true,
    "doesNotModifyGitOps": true
  }
}`

	writeB4TestFile(t, filepath.Join(reportDir, "release-evidence-"+releaseID+".json"), releaseEvidence)
	writeB4TestFile(t, filepath.Join(reportDir, "runtime-action-execution-result-"+releaseID+".json"), result)
	writeB4TestFile(t, filepath.Join(reportDir, "runtime-action-execution-result-latest.json"), result)

	api := &portalAPI{
		cfg: Config{
			RepoDir: tempRepo,
		},
		reportDir: reportDir,
	}

	latestResult := callB4PortalJSON(t, api.handleLatestResource("runtimeActionExecutionResult"), http.MethodGet, "/api/releases/latest/runtime-action-execution-result", http.StatusOK)
	requireB4String(t, latestResult, "runtimeActionExecutionResultId", resultID)
	requireB4NestedString(t, latestResult, "action", "requestedAction", "PAUSE_ROLLOUT")
	requireB4NestedString(t, latestResult, "action", "actionStatus", "EXECUTION_SUCCEEDED")
	requireB4NestedString(t, latestResult, "result", "executionStatus", "SUCCEEDED")

	refresh := callB4PortalJSON(t, api.handleEvidenceStoreRefresh, http.MethodPost, "/api/evidence-store/refresh", http.StatusOK)
	requireB4String(t, refresh, "schemaVersion", "evidence.store.refresh/v1alpha1")

	resultObject := callB4PortalJSON(t, api.handleEvidenceStoreObjectDetail, http.MethodGet, "/api/evidence/objects/runtimeActionExecutionResult/"+resultID+"?releaseId="+releaseID+"&includeRaw=true", http.StatusOK)
	requireB4String(t, resultObject, "schemaVersion", "evidence.store.object/v1alpha1")
	requireB4JSONContains(t, resultObject, "runtimeActionExecutionResult")
	requireB4JSONContains(t, resultObject, "PAUSE_ROLLOUT")
	requireB4JSONContains(t, resultObject, "EXECUTION_SUCCEEDED")
	requireB4JSONContains(t, resultObject, "kubectl_patch_rollout_spec_paused")
	requireB4JSONContains(t, resultObject, "mutatedKubernetes")

	releaseDetail := callB4PortalJSON(t, api.handleEvidenceStoreReleaseDetail, http.MethodGet, "/api/evidence/releases/"+releaseID+"?includeRaw=true", http.StatusOK)
	requireB4String(t, releaseDetail, "schemaVersion", "evidence.store.release/v1alpha1")
	requireB4JSONContains(t, releaseDetail, "runtimeActionExecutionResult")
	requireB4JSONContains(t, releaseDetail, resultID)
}
