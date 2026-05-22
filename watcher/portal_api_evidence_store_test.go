package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
)

func TestPortalEvidenceStoreAdapter(t *testing.T) {
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

	scriptTarget := filepath.Join(scriptDir, "evidence-store.py")
	if err := os.WriteFile(scriptTarget, scriptData, 0755); err != nil {
		t.Fatalf("write evidence-store.py: %v", err)
	}

	reportDir := filepath.Join(tempRepo, "docs", "release-reports")
	if err := os.MkdirAll(reportDir, 0755); err != nil {
		t.Fatalf("create report dir: %v", err)
	}

	releaseID := "20260101-000000"
	releaseEvidence := `{
  "schemaVersion": "release.evidence.bundle/v1alpha1",
  "generatedBy": "portal_api_evidence_store_test.go",
  "releaseResult": "PASS",
  "policyDecision": "ALLOW",
  "finalAction": "NOOP",
  "executionMode": "advisory_only",
  "requiresHumanApproval": false,
  "safeToRetry": true,
  "service": "demo-app",
  "namespace": "slo-rollout",
  "env": "dev",
  "summary": {
    "riskLevel": "low",
    "riskScore": 0
  },
  "artifacts": {}
}`

	if err := os.WriteFile(
		filepath.Join(reportDir, "release-evidence-"+releaseID+".json"),
		[]byte(releaseEvidence),
		0644,
	); err != nil {
		t.Fatalf("write release evidence: %v", err)
	}

	api := &portalAPI{
		cfg: Config{
			RepoDir: tempRepo,
		},
		reportDir: reportDir,
	}

	listBody := callPortalEvidenceStoreHandler(
		t,
		api.handleEvidenceStoreReleaseList,
		"/api/evidence-store/releases?limit=10",
	)
	assertPortalSchema(t, listBody, "evidence.store.releaseList/v1alpha1")

	detailBody := callPortalEvidenceStoreHandler(
		t,
		api.handleEvidenceStoreReleaseDetail,
		"/api/evidence-store/releases/"+releaseID,
	)
	assertPortalSchema(t, detailBody, "evidence.store.release/v1alpha1")

	objectBody := callPortalEvidenceStoreHandler(
		t,
		api.handleEvidenceStoreObjectDetail,
		"/api/evidence-store/objects/releaseEvidence/re-"+releaseID+"?releaseId="+releaseID,
	)
	assertPortalSchema(t, objectBody, "evidence.store.object/v1alpha1")
}

func callPortalEvidenceStoreHandler(
	t *testing.T,
	handler http.HandlerFunc,
	target string,
) map[string]interface{} {
	t.Helper()

	req := httptest.NewRequest(http.MethodGet, target, nil)
	rec := httptest.NewRecorder()

	handler(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected HTTP 200 for %s, got %d: %s", target, rec.Code, rec.Body.String())
	}

	var body map[string]interface{}
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode response for %s: %v: %s", target, err, rec.Body.String())
	}

	return body
}

func assertPortalSchema(t *testing.T, body map[string]interface{}, expected string) {
	t.Helper()

	got, _ := body["schemaVersion"].(string)
	if got != expected {
		t.Fatalf("expected schemaVersion=%s, got=%s body=%v", expected, got, body)
	}
}
