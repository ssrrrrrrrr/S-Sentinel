package main

import (
	"net/http"
	"os"
	"path/filepath"
	"testing"
)

func TestRuntimeActionRequestEvidenceStoreAndPortalLatestResource(t *testing.T) {
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

	releaseID := "20260527-030303"
	requestID := "rarq-" + releaseID
	recommendationID := "rar-" + releaseID

	releaseEvidence := `{
  "schemaVersion": "release.evidence/v1alpha1",
  "generatedBy": "portal_api_runtime_action_request_e2e_test.go",
  "releaseId": "` + releaseID + `",
  "releaseResult": "STOP_PROMOTION",
  "policyDecision": "REQUIRE_HUMAN_APPROVAL",
  "service": "demo-app",
  "namespace": "slo-rollout",
  "env": "dev",
  "artifacts": {
    "runtimeActionRequest": "runtime-action-request-` + releaseID + `.json"
  }
}`

	request := `{
  "schemaVersion": "runtime.action.request/v1alpha1",
  "runtimeActionRequestId": "` + requestID + `",
  "generatedBy": "portal_api_runtime_action_request_e2e_test.go",
  "generatedAt": "2026-05-27T03:03:03Z",
  "mode": "request_only",
  "sourceRuntimeActionRecommendationId": "` + recommendationID + `",
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
  "request": {
    "requestedBy": "portal-e2e-test",
    "requestedAction": "PAUSE_ROLLOUT",
    "requestStatus": "PENDING_APPROVAL",
    "lifecycleStage": "WAITING_APPROVAL",
    "requestReason": "Runtime evidence indicates rollout risk; recommend preparing a pause request.",
    "riskLevel": "high",
    "confidence": "high",
    "approvalRequired": true,
    "readyToExecute": false,
    "willExecute": false
  },
  "recommendationBinding": {
    "recommendationStatus": "ACTION_RECOMMENDED",
    "recommendedAction": "PAUSE_ROLLOUT",
    "approvalRequired": true,
    "reasons": [
      "rollout_phase_degraded",
      "analysis_not_successful"
    ],
    "allowedToRequest": true,
    "blockingReasons": [],
    "willExecute": false
  },
  "runtimeSnapshot": {
    "rolloutPhase": "Degraded",
    "strategy": "Canary",
    "currentStepIndex": 2,
    "replicas": 3,
    "updatedReplicas": 1,
    "readyReplicas": 1,
    "availableReplicas": 1,
    "paused": false,
    "degraded": true,
    "analysisRunName": "demo-app-analysis-` + releaseID + `",
    "analysisStatus": "Failed"
  },
  "approval": {
    "required": true,
    "status": "NOT_APPROVED",
    "approved": false,
    "approvalDecision": null,
    "readyToExecute": false,
    "willExecuteAfterApproval": false
  },
  "evidenceRefs": {
    "runtimeActionRecommendation": "runtime-action-recommendation-` + releaseID + `.json",
    "sourceRuntimeActionRecommendationId": "` + recommendationID + `",
    "rolloutRuntimeInspect": "rollout-runtime-inspect-` + releaseID + `.json",
    "sourceRolloutRuntimeInspectId": "rti-` + releaseID + `"
  },
  "guardrails": {
    "requestOnly": true,
    "readOnly": true,
    "willExecute": false,
    "doesNotPause": true,
    "doesNotResume": true,
    "doesNotPromote": true,
    "doesNotAbort": true,
    "doesNotRollback": true,
    "doesNotModifyKubernetes": true,
    "doesNotModifyGitOps": true,
    "doesNotCommitOrPush": true
  }
}`

	writeB4TestFile(t, filepath.Join(reportDir, "release-evidence-"+releaseID+".json"), releaseEvidence)
	writeB4TestFile(t, filepath.Join(reportDir, "runtime-action-request-"+releaseID+".json"), request)
	writeB4TestFile(t, filepath.Join(reportDir, "runtime-action-request-latest.json"), request)

	api := &portalAPI{
		cfg: Config{
			RepoDir: tempRepo,
		},
		reportDir: reportDir,
	}

	latestRequest := callB4PortalJSON(t, api.handleLatestResource("runtimeActionRequest"), http.MethodGet, "/api/releases/latest/runtime-action-request", http.StatusOK)
	requireB4String(t, latestRequest, "runtimeActionRequestId", requestID)
	requireB4NestedString(t, latestRequest, "request", "requestedAction", "PAUSE_ROLLOUT")
	requireB4NestedString(t, latestRequest, "request", "requestStatus", "PENDING_APPROVAL")

	refresh := callB4PortalJSON(t, api.handleEvidenceStoreRefresh, http.MethodPost, "/api/evidence-store/refresh", http.StatusOK)
	requireB4String(t, refresh, "schemaVersion", "evidence.store.refresh/v1alpha1")

	requestObject := callB4PortalJSON(t, api.handleEvidenceStoreObjectDetail, http.MethodGet, "/api/evidence/objects/runtimeActionRequest/"+requestID+"?releaseId="+releaseID+"&includeRaw=true", http.StatusOK)
	requireB4String(t, requestObject, "schemaVersion", "evidence.store.object/v1alpha1")
	requireB4JSONContains(t, requestObject, "runtimeActionRequest")
	requireB4JSONContains(t, requestObject, "PAUSE_ROLLOUT")
	requireB4JSONContains(t, requestObject, "PENDING_APPROVAL")
	requireB4JSONContains(t, requestObject, "doesNotModifyKubernetes")

	releaseDetail := callB4PortalJSON(t, api.handleEvidenceStoreReleaseDetail, http.MethodGet, "/api/evidence/releases/"+releaseID+"?includeRaw=true", http.StatusOK)
	requireB4String(t, releaseDetail, "schemaVersion", "evidence.store.release/v1alpha1")
	requireB4JSONContains(t, releaseDetail, "runtimeActionRequest")
	requireB4JSONContains(t, releaseDetail, requestID)
}
