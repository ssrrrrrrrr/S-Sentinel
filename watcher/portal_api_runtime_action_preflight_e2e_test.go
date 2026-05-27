package main

import (
	"net/http"
	"os"
	"path/filepath"
	"testing"
)

func TestRuntimeActionPreflightEvidenceStoreAndPortalLatestResource(t *testing.T) {
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

	releaseID := "20260527-040404"
	preflightID := "rap-" + releaseID
	requestID := "rarq-" + releaseID
	recommendationID := "rar-" + releaseID

	releaseEvidence := `{
  "schemaVersion": "release.evidence/v1alpha1",
  "generatedBy": "portal_api_runtime_action_preflight_e2e_test.go",
  "releaseId": "` + releaseID + `",
  "releaseResult": "STOP_PROMOTION",
  "policyDecision": "REQUIRE_HUMAN_APPROVAL",
  "service": "demo-app",
  "namespace": "slo-rollout",
  "env": "dev",
  "artifacts": {
    "runtimeActionPreflight": "runtime-action-preflight-` + releaseID + `.json"
  }
}`

	preflight := `{
  "schemaVersion": "runtime.action.preflight/v1alpha1",
  "runtimeActionPreflightId": "` + preflightID + `",
  "generatedBy": "portal_api_runtime_action_preflight_e2e_test.go",
  "generatedAt": "2026-05-27T04:04:04Z",
  "mode": "read_only_runtime_action_preflight",
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
  "request": {
    "runtimeActionRequestId": "` + requestID + `",
    "requestedAction": "PAUSE_ROLLOUT",
    "requestStatus": "PENDING_APPROVAL",
    "lifecycleStage": "WAITING_APPROVAL",
    "riskLevel": "high",
    "confidence": "high",
    "approvalRequired": true,
    "approved": false,
    "allowedToRequest": true,
    "readyToExecute": false,
    "willExecute": false
  },
  "preflight": {
    "preflightStatus": "WAITING_APPROVAL",
    "eligibilityStatus": "NOT_ELIGIBLE",
    "checks": [],
    "blockingReasons": [],
    "approvalReasons": ["human_approval_required"],
    "warningReasons": [],
    "eligibleForExecution": false,
    "readyToExecute": false,
    "willExecute": false,
    "summary": "Runtime action preflight status is WAITING_APPROVAL for PAUSE_ROLLOUT."
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
  "evidenceRefs": {
    "runtimeActionRequest": "runtime-action-request-` + releaseID + `.json",
    "sourceRuntimeActionRequestId": "` + requestID + `",
    "runtimeActionRecommendation": "runtime-action-recommendation-` + releaseID + `.json",
    "sourceRuntimeActionRecommendationId": "` + recommendationID + `",
    "rolloutRuntimeInspect": "rollout-runtime-inspect-` + releaseID + `.json",
    "sourceRolloutRuntimeInspectId": "rti-` + releaseID + `"
  },
  "guardrails": {
    "preflightOnly": true,
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
	writeB4TestFile(t, filepath.Join(reportDir, "runtime-action-preflight-"+releaseID+".json"), preflight)
	writeB4TestFile(t, filepath.Join(reportDir, "runtime-action-preflight-latest.json"), preflight)

	api := &portalAPI{
		cfg: Config{
			RepoDir: tempRepo,
		},
		reportDir: reportDir,
	}

	latestPreflight := callB4PortalJSON(t, api.handleLatestResource("runtimeActionPreflight"), http.MethodGet, "/api/releases/latest/runtime-action-preflight", http.StatusOK)
	requireB4String(t, latestPreflight, "runtimeActionPreflightId", preflightID)
	requireB4NestedString(t, latestPreflight, "request", "requestedAction", "PAUSE_ROLLOUT")
	requireB4NestedString(t, latestPreflight, "preflight", "preflightStatus", "WAITING_APPROVAL")
	requireB4NestedString(t, latestPreflight, "preflight", "eligibilityStatus", "NOT_ELIGIBLE")

	refresh := callB4PortalJSON(t, api.handleEvidenceStoreRefresh, http.MethodPost, "/api/evidence-store/refresh", http.StatusOK)
	requireB4String(t, refresh, "schemaVersion", "evidence.store.refresh/v1alpha1")

	preflightObject := callB4PortalJSON(t, api.handleEvidenceStoreObjectDetail, http.MethodGet, "/api/evidence/objects/runtimeActionPreflight/"+preflightID+"?releaseId="+releaseID+"&includeRaw=true", http.StatusOK)
	requireB4String(t, preflightObject, "schemaVersion", "evidence.store.object/v1alpha1")
	requireB4JSONContains(t, preflightObject, "runtimeActionPreflight")
	requireB4JSONContains(t, preflightObject, "PAUSE_ROLLOUT")
	requireB4JSONContains(t, preflightObject, "WAITING_APPROVAL")
	requireB4JSONContains(t, preflightObject, "NOT_ELIGIBLE")
	requireB4JSONContains(t, preflightObject, "doesNotModifyKubernetes")

	releaseDetail := callB4PortalJSON(t, api.handleEvidenceStoreReleaseDetail, http.MethodGet, "/api/evidence/releases/"+releaseID+"?includeRaw=true", http.StatusOK)
	requireB4String(t, releaseDetail, "schemaVersion", "evidence.store.release/v1alpha1")
	requireB4JSONContains(t, releaseDetail, "runtimeActionPreflight")
	requireB4JSONContains(t, releaseDetail, preflightID)
}
