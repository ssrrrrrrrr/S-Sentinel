package main

import (
	"net/http"
	"os"
	"path/filepath"
	"testing"
)

func TestRolloutRuntimeInspectEvidenceStoreAndPortalLatestResource(t *testing.T) {
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

	releaseID := "20260527-010101"
	inspectID := "rti-" + releaseID

	releaseEvidence := `{
  "schemaVersion": "release.evidence/v1alpha1",
  "generatedBy": "portal_api_rollout_runtime_inspect_e2e_test.go",
  "releaseId": "` + releaseID + `",
  "releaseResult": "STOP_PROMOTION",
  "policyDecision": "REQUIRE_HUMAN_APPROVAL",
  "service": "demo-app",
  "namespace": "slo-rollout",
  "env": "dev",
  "artifacts": {
    "rolloutRuntimeInspect": "rollout-runtime-inspect-` + releaseID + `.json"
  }
}`

	inspect := `{
  "schemaVersion": "runtime.rollout.inspect/v1alpha1",
  "rolloutRuntimeInspectId": "` + inspectID + `",
  "generatedBy": "portal_api_rollout_runtime_inspect_e2e_test.go",
  "mode": "fixture_rollout_runtime_inspect",
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
  "rollout": {
    "name": "demo-app",
    "namespace": "slo-rollout",
    "phase": "Progressing",
    "strategy": "Canary",
    "currentStepIndex": 2,
    "replicas": 3,
    "updatedReplicas": 1,
    "readyReplicas": 3,
    "availableReplicas": 3,
    "paused": false,
    "degraded": false
  },
  "analysis": {
    "analysisRunName": "demo-app-analysis-` + releaseID + `",
    "status": "Running",
    "successful": 0,
    "failed": 0,
    "inconclusive": 0
  },
  "pods": {
    "selector": "app=demo-app",
    "podCount": 3,
    "readyPodCount": 3,
    "runningPodCount": 3
  },
  "guardrails": {
    "readOnly": true,
    "dryRunOnly": true,
    "willExecute": false,
    "doesNotPause": true,
    "doesNotResume": true,
    "doesNotPromote": true,
    "doesNotAbort": true,
    "doesNotRollback": true,
    "doesNotModifyKubernetes": true
  }
}`

	writeB4TestFile(t, filepath.Join(reportDir, "release-evidence-"+releaseID+".json"), releaseEvidence)
	writeB4TestFile(t, filepath.Join(reportDir, "rollout-runtime-inspect-"+releaseID+".json"), inspect)
	writeB4TestFile(t, filepath.Join(reportDir, "rollout-runtime-inspect-latest.json"), inspect)

	api := &portalAPI{
		cfg: Config{
			RepoDir: tempRepo,
		},
		reportDir: reportDir,
	}

	latestInspect := callB4PortalJSON(t, api.handleLatestResource("rolloutRuntimeInspect"), http.MethodGet, "/api/releases/latest/rollout-runtime-inspect", http.StatusOK)
	requireB4String(t, latestInspect, "rolloutRuntimeInspectId", inspectID)
	requireB4NestedString(t, latestInspect, "rollout", "phase", "Progressing")
	requireB4NestedString(t, latestInspect, "analysis", "status", "Running")

	refresh := callB4PortalJSON(t, api.handleEvidenceStoreRefresh, http.MethodPost, "/api/evidence-store/refresh", http.StatusOK)
	requireB4String(t, refresh, "schemaVersion", "evidence.store.refresh/v1alpha1")

	inspectObject := callB4PortalJSON(t, api.handleEvidenceStoreObjectDetail, http.MethodGet, "/api/evidence/objects/rolloutRuntimeInspect/"+inspectID+"?releaseId="+releaseID+"&includeRaw=true", http.StatusOK)
	requireB4String(t, inspectObject, "schemaVersion", "evidence.store.object/v1alpha1")
	requireB4JSONContains(t, inspectObject, "rolloutRuntimeInspect")
	requireB4JSONContains(t, inspectObject, "Progressing")
	requireB4JSONContains(t, inspectObject, "doesNotModifyKubernetes")

	releaseDetail := callB4PortalJSON(t, api.handleEvidenceStoreReleaseDetail, http.MethodGet, "/api/evidence/releases/"+releaseID+"?includeRaw=true", http.StatusOK)
	requireB4String(t, releaseDetail, "schemaVersion", "evidence.store.release/v1alpha1")
	requireB4JSONContains(t, releaseDetail, "rolloutRuntimeInspect")
	requireB4JSONContains(t, releaseDetail, inspectID)
}
