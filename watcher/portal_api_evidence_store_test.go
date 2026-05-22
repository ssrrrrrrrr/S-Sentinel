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

	statusBeforeRefreshBody := callPortalEvidenceStoreHandler(
		t,
		api.handleEvidenceStoreStatus,
		"/api/evidence-store/status",
	)
	assertPortalSchema(t, statusBeforeRefreshBody, "evidence.store.status/v1alpha1")
	assertPortalBool(t, statusBeforeRefreshBody, "ready", false)

	initialRefreshBody := callPortalEvidenceStoreHandlerWithMethod(
		t,
		api.handleEvidenceStoreRefresh,
		http.MethodPost,
		"/api/evidence-store/refresh",
	)
	assertPortalSchema(t, initialRefreshBody, "evidence.store.refresh/v1alpha1")
	assertPortalLatestReleaseID(t, initialRefreshBody, releaseID)

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

	statusBody := callPortalEvidenceStoreHandler(
		t,
		api.handleEvidenceStoreStatus,
		"/api/evidence-store/status",
	)
	assertPortalSchema(t, statusBody, "evidence.store.status/v1alpha1")
	assertPortalBool(t, statusBody, "readOnly", true)
	assertPortalBool(t, statusBody, "willExecute", false)

	refreshBody := callPortalEvidenceStoreHandlerWithMethod(
		t,
		api.handleEvidenceStoreRefresh,
		http.MethodPost,
		"/api/evidence-store/refresh",
	)
	assertPortalSchema(t, refreshBody, "evidence.store.refresh/v1alpha1")
	assertPortalBool(t, refreshBody, "readOnly", true)
	assertPortalBool(t, refreshBody, "willExecute", false)
	assertPortalLatestReleaseID(t, refreshBody, releaseID)

	statusAfterRefreshBody := callPortalEvidenceStoreHandler(
		t,
		api.handleEvidenceStoreStatus,
		"/api/evidence-store/status",
	)
	assertPortalSchema(t, statusAfterRefreshBody, "evidence.store.status/v1alpha1")
	assertPortalBool(t, statusAfterRefreshBody, "ready", true)
	assertPortalLatestReleaseID(t, statusAfterRefreshBody, releaseID)
}

func callPortalEvidenceStoreHandler(
	t *testing.T,
	handler http.HandlerFunc,
	target string,
) map[string]interface{} {
	t.Helper()

	return callPortalEvidenceStoreHandlerWithMethod(t, handler, http.MethodGet, target)
}

func callPortalEvidenceStoreHandlerWithMethod(
	t *testing.T,
	handler http.HandlerFunc,
	method string,
	target string,
) map[string]interface{} {
	t.Helper()

	req := httptest.NewRequest(method, target, nil)
	rec := httptest.NewRecorder()

	handler(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected HTTP 200 for %s %s, got %d: %s", method, target, rec.Code, rec.Body.String())
	}

	var body map[string]interface{}
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode response for %s %s: %v: %s", method, target, err, rec.Body.String())
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

func assertPortalBool(t *testing.T, body map[string]interface{}, key string, expected bool) {
	t.Helper()

	got, ok := body[key].(bool)
	if !ok {
		t.Fatalf("expected %s to be a bool, got body=%v", key, body)
	}

	if got != expected {
		t.Fatalf("expected %s=%v, got=%v body=%v", key, expected, got, body)
	}
}

func assertPortalLatestReleaseID(t *testing.T, body map[string]interface{}, expected string) {
	t.Helper()

	latest, ok := body["latestRelease"].(map[string]interface{})
	if !ok {
		t.Fatalf("expected latestRelease object, got body=%v", body)
	}

	got, _ := latest["release_id"].(string)
	if got != expected {
		t.Fatalf("expected latestRelease.release_id=%s, got=%s body=%v", expected, got, body)
	}
}
