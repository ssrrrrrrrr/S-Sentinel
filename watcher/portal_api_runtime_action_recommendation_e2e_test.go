package main

import (
	"net/http"
	"os"
	"path/filepath"
	"testing"
)

func TestRuntimeActionRecommendationEvidenceStoreAndPortalLatestResource(t *testing.T) {
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

	releaseID := "20260527-020202"
	recommendationID := "rar-" + releaseID

	releaseEvidence := `{
  "schemaVersion": "release.evidence/v1alpha1",
  "generatedBy": "portal_api_runtime_action_recommendation_e2e_test.go",
  "releaseId": "` + releaseID + `",
  "releaseResult": "STOP_PROMOTION",
  "policyDecision": "REQUIRE_HUMAN_APPROVAL",
  "service": "demo-app",
  "namespace": "slo-rollout",
  "env": "dev",
  "artifacts": {
    "runtimeActionRecommendation": "runtime-action-recommendation-` + releaseID + `.json"
  }
}`

	recommendation := `{
  "schemaVersion": "runtime.action.recommendation/v1alpha1",
  "runtimeActionRecommendationId": "` + recommendationID + `",
  "generatedBy": "portal_api_runtime_action_recommendation_e2e_test.go",
  "mode": "recommendation_only",
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
  "recommendation": {
    "recommendationStatus": "ACTION_RECOMMENDED",
    "recommendedAction": "PAUSE_ROLLOUT",
    "riskLevel": "high",
    "confidence": "high",
    "approvalRequired": true,
    "reasons": [
      "rollout_phase_degraded",
      "analysis_not_successful"
    ],
    "summary": "Runtime evidence indicates rollout risk; recommend preparing a pause request."
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
    "analysisStatus": "Failed",
    "podCount": 3,
    "readyPodCount": 1,
    "runningPodCount": 3
  },
  "evidenceRefs": {
    "rolloutRuntimeInspect": "rollout-runtime-inspect-` + releaseID + `.json",
    "sourceRolloutRuntimeInspectId": "rti-` + releaseID + `"
  },
  "guardrails": {
    "readOnly": true,
    "recommendationOnly": true,
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
	writeB4TestFile(t, filepath.Join(reportDir, "runtime-action-recommendation-"+releaseID+".json"), recommendation)
	writeB4TestFile(t, filepath.Join(reportDir, "runtime-action-recommendation-latest.json"), recommendation)

	api := &portalAPI{
		cfg: Config{
			RepoDir: tempRepo,
		},
		reportDir: reportDir,
	}

	latestRecommendation := callB4PortalJSON(t, api.handleLatestResource("runtimeActionRecommendation"), http.MethodGet, "/api/releases/latest/runtime-action-recommendation", http.StatusOK)
	requireB4String(t, latestRecommendation, "runtimeActionRecommendationId", recommendationID)
	requireB4NestedString(t, latestRecommendation, "recommendation", "recommendedAction", "PAUSE_ROLLOUT")
	requireB4NestedString(t, latestRecommendation, "recommendation", "recommendationStatus", "ACTION_RECOMMENDED")

	refresh := callB4PortalJSON(t, api.handleEvidenceStoreRefresh, http.MethodPost, "/api/evidence-store/refresh", http.StatusOK)
	requireB4String(t, refresh, "schemaVersion", "evidence.store.refresh/v1alpha1")

	recommendationObject := callB4PortalJSON(t, api.handleEvidenceStoreObjectDetail, http.MethodGet, "/api/evidence/objects/runtimeActionRecommendation/"+recommendationID+"?releaseId="+releaseID+"&includeRaw=true", http.StatusOK)
	requireB4String(t, recommendationObject, "schemaVersion", "evidence.store.object/v1alpha1")
	requireB4JSONContains(t, recommendationObject, "runtimeActionRecommendation")
	requireB4JSONContains(t, recommendationObject, "PAUSE_ROLLOUT")
	requireB4JSONContains(t, recommendationObject, "doesNotModifyKubernetes")

	releaseDetail := callB4PortalJSON(t, api.handleEvidenceStoreReleaseDetail, http.MethodGet, "/api/evidence/releases/"+releaseID+"?includeRaw=true", http.StatusOK)
	requireB4String(t, releaseDetail, "schemaVersion", "evidence.store.release/v1alpha1")
	requireB4JSONContains(t, releaseDetail, "runtimeActionRecommendation")
	requireB4JSONContains(t, releaseDetail, recommendationID)
}
