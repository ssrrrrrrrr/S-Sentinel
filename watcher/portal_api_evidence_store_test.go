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

	signedReleaseGate := `{
  "schemaVersion": "signed.release.gate/v1alpha1",
  "signedReleaseGateId": "srg-20260101-000000",
  "release": {
    "releaseId": "20260101-000000",
    "service": "demo-app",
    "namespace": "slo-rollout",
    "env": "dev"
  },
  "verification": {
    "schemaVersion": "signed.release.gate.verification/v1alpha1",
    "mode": "input_derived",
    "tool": "cosign",
    "toolBinary": "cosign",
    "toolAvailable": false,
    "results": {
      "signatureVerified": false,
      "sbomPresent": true,
      "provenancePresent": true,
      "slsaLevelPresent": "unknown"
    },
    "guardrails": {
      "canRunExternalVerification": false,
      "doesNotRunExternalCommands": true
    }
  }
}`

	if err := os.WriteFile(
		filepath.Join(reportDir, "signed-release-gate-"+releaseID+".json"),
		[]byte(signedReleaseGate),
		0644,
	); err != nil {
		t.Fatalf("write signed release gate: %v", err)
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
	assertPortalStringNotEmpty(t, statusBeforeRefreshBody, "pythonRuntime")
	assertPortalBool(t, statusBeforeRefreshBody, "doesNotModifyCluster", true)
	assertPortalBool(t, statusBeforeRefreshBody, "doesNotModifyGitOps", true)
	assertPortalBool(t, statusBeforeRefreshBody, "doesNotTriggerRollout", true)
	assertPortalBool(t, statusBeforeRefreshBody, "mutatesLocalEvidenceIndex", false)
	assertPortalNestedString(t, statusBeforeRefreshBody, "runtime", "mode", "cli-sqlite-runtime")
	assertPortalNestedString(t, statusBeforeRefreshBody, "runtime", "contractVersion", "evidence.runtime/v1alpha1")
	assertPortalNestedString(t, statusBeforeRefreshBody, "repository", "repositoryType", "cli-backed")
	assertPortalNestedString(t, statusBeforeRefreshBody, "repository", "mode", "cli-repository")
	assertPortalNestedString(t, statusBeforeRefreshBody, "repository", "contractVersion", "evidence.repository/v1alpha1")
	assertPortalNestedString(t, statusBeforeRefreshBody, "service", "contractVersion", "evidence.api.service/v1alpha1")
	assertPortalNestedBool(t, statusBeforeRefreshBody, "capabilities", "search", true)

	errorBeforeRefreshBody := callPortalEvidenceStoreHandlerWithExpectedStatus(
		t,
		api.handleEvidenceStoreReleaseList,
		http.MethodGet,
		"/api/evidence/releases?limit=10",
		http.StatusConflict,
	)
	assertPortalSchema(t, errorBeforeRefreshBody, "evidence.store.adapter.error/v1alpha1")
	assertPortalNestedString(t, errorBeforeRefreshBody, "controlPlane", "apiVersion", "s-sentinel.io/evidence-api/v1alpha1")
	assertPortalNestedString(t, errorBeforeRefreshBody, "controlPlane", "operation", "query-error")
	assertPortalNestedBool(t, errorBeforeRefreshBody, "controlPlane", "doesNotModifyCluster", true)
	assertPortalNestedBool(t, errorBeforeRefreshBody, "controlPlane", "doesNotModifyGitOps", true)
	assertPortalNestedBool(t, errorBeforeRefreshBody, "controlPlane", "doesNotTriggerRollout", true)
	assertPortalNestedBool(t, errorBeforeRefreshBody, "controlPlane", "mutatesLocalEvidenceIndex", false)

	initialRefreshBody := callPortalEvidenceStoreHandlerWithMethod(
		t,
		api.handleEvidenceStoreRefresh,
		http.MethodPost,
		"/api/evidence-store/refresh",
	)
	assertPortalSchema(t, initialRefreshBody, "evidence.store.refresh/v1alpha1")
	assertPortalLatestReleaseID(t, initialRefreshBody, releaseID)
	assertPortalBool(t, initialRefreshBody, "doesNotModifyCluster", true)
	assertPortalBool(t, initialRefreshBody, "doesNotModifyGitOps", true)
	assertPortalBool(t, initialRefreshBody, "doesNotTriggerRollout", true)
	assertPortalBool(t, initialRefreshBody, "mutatesLocalEvidenceIndex", true)
	assertPortalNestedString(t, initialRefreshBody, "controlPlane", "operation", "refresh")
	assertPortalNestedBool(t, initialRefreshBody, "controlPlane", "mutatesLocalEvidenceIndex", true)

	listBody := callPortalEvidenceStoreHandler(
		t,
		api.handleEvidenceStoreReleaseList,
		"/api/evidence-store/releases?limit=10",
	)
	assertPortalSchema(t, listBody, "evidence.store.releaseList/v1alpha1")
	assertPortalNestedString(t, listBody, "controlPlane", "apiVersion", "s-sentinel.io/evidence-api/v1alpha1")
	assertPortalNestedString(t, listBody, "controlPlane", "contractVersion", "evidence.api.response/v1alpha1")
	assertPortalNestedString(t, listBody, "controlPlane", "repositoryType", "cli-backed")
	assertPortalNestedString(t, listBody, "controlPlane", "runtimeMode", "cli-sqlite-runtime")

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

	canonicalListBody := callPortalEvidenceStoreHandler(
		t,
		api.handleEvidenceStoreReleaseList,
		"/api/evidence/releases?limit=10",
	)
	assertPortalSchema(t, canonicalListBody, "evidence.store.releaseList/v1alpha1")

	canonicalDetailBody := callPortalEvidenceStoreHandler(
		t,
		api.handleEvidenceStoreReleaseDetail,
		"/api/evidence/releases/"+releaseID,
	)
	assertPortalSchema(t, canonicalDetailBody, "evidence.store.release/v1alpha1")
	assertPortalNestedString(t, canonicalDetailBody, "controlPlane", "apiVersion", "s-sentinel.io/evidence-api/v1alpha1")

	canonicalObjectBody := callPortalEvidenceStoreHandler(
		t,
		api.handleEvidenceStoreObjectDetail,
		"/api/evidence/objects/releaseEvidence/re-"+releaseID+"?releaseId="+releaseID,
	)
	assertPortalSchema(t, canonicalObjectBody, "evidence.store.object/v1alpha1")

	artifactListBody := callPortalEvidenceStoreHandler(
		t,
		api.handleEvidenceArtifactList,
		"/api/evidence/artifacts?releaseId="+releaseID,
	)
	assertPortalSchema(t, artifactListBody, "evidence.store.artifactList/v1alpha1")

	searchBody := callPortalEvidenceStoreHandler(
		t,
		api.handleEvidenceSearch,
		"/api/evidence/search?q=demo-app&limit=10",
	)
	assertPortalSchema(t, searchBody, "evidence.store.search/v1alpha1")
	assertPortalNestedBool(t, searchBody, "filters", "includeRaw", false)
	assertPortalNestedString(t, searchBody, "controlPlane", "repositoryContract", "evidence.repository/v1alpha1")

	verificationSummaryBody := callPortalEvidenceStoreHandler(
		t,
		api.handleEvidenceVerificationSummary,
		"/api/evidence/verification-summary?releaseId="+releaseID,
	)
	assertPortalSchema(t, verificationSummaryBody, "evidence.store.verificationSummary/v1alpha1")
	assertPortalLatestVerificationMode(t, verificationSummaryBody, "input_derived")
	assertPortalNestedString(t, verificationSummaryBody, "latest", "verificationStatus", "input_derived")

	graphBody := callPortalEvidenceStoreHandler(
		t,
		api.handleEvidenceGraph,
		"/api/evidence/graph?releaseId="+releaseID,
	)
	assertPortalSchema(t, graphBody, "evidence.store.graph/v1alpha1")
	assertPortalNumberAtLeast(t, graphBody, "nodeCount", 3)
	assertPortalNumberAtLeast(t, graphBody, "edgeCount", 2)

	statusBody := callPortalEvidenceStoreHandler(
		t,
		api.handleEvidenceStoreStatus,
		"/api/evidence-store/status",
	)
	assertPortalSchema(t, statusBody, "evidence.store.status/v1alpha1")
	assertPortalStringNotEmpty(t, statusBody, "pythonRuntime")
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
	assertPortalBool(t, refreshBody, "doesNotModifyCluster", true)
	assertPortalBool(t, refreshBody, "doesNotModifyGitOps", true)
	assertPortalBool(t, refreshBody, "doesNotTriggerRollout", true)
	assertPortalBool(t, refreshBody, "mutatesLocalEvidenceIndex", true)
	assertPortalNestedString(t, refreshBody, "controlPlane", "operation", "refresh")
	assertPortalLatestReleaseID(t, refreshBody, releaseID)

	statusAfterRefreshBody := callPortalEvidenceStoreHandler(
		t,
		api.handleEvidenceStoreStatus,
		"/api/evidence-store/status",
	)
	assertPortalSchema(t, statusAfterRefreshBody, "evidence.store.status/v1alpha1")
	assertPortalBool(t, statusAfterRefreshBody, "ready", true)
	assertPortalLatestReleaseID(t, statusAfterRefreshBody, releaseID)
	assertPortalNestedNumber(t, statusAfterRefreshBody, "lastImportResult", "releaseCount", 1)
	assertPortalNestedNumber(t, statusAfterRefreshBody, "lastImportResult", "importedObjects", 2)
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

func callPortalEvidenceStoreHandlerWithExpectedStatus(
	t *testing.T,
	handler http.HandlerFunc,
	method string,
	target string,
	expectedStatus int,
) map[string]interface{} {
	t.Helper()

	req := httptest.NewRequest(method, target, nil)
	rec := httptest.NewRecorder()

	handler(rec, req)

	if rec.Code != expectedStatus {
		t.Fatalf("expected HTTP %d for %s %s, got %d: %s", expectedStatus, method, target, rec.Code, rec.Body.String())
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

func assertPortalNestedNumber(t *testing.T, body map[string]interface{}, objectKey string, valueKey string, expected float64) {
	t.Helper()

	object, ok := body[objectKey].(map[string]interface{})
	if !ok {
		t.Fatalf("expected %s object, got body=%v", objectKey, body)
	}

	got, ok := object[valueKey].(float64)
	if !ok {
		t.Fatalf("expected %s.%s to be a number, got object=%v", objectKey, valueKey, object)
	}

	if got != expected {
		t.Fatalf("expected %s.%s=%v, got=%v object=%v", objectKey, valueKey, expected, got, object)
	}
}

func assertPortalNumberAtLeast(t *testing.T, body map[string]interface{}, key string, minimum float64) {
	t.Helper()

	got, ok := body[key].(float64)
	if !ok {
		t.Fatalf("expected %s to be a number, got body=%v", key, body)
	}

	if got < minimum {
		t.Fatalf("expected %s >= %v, got=%v body=%v", key, minimum, got, body)
	}
}

func assertPortalLatestVerificationMode(t *testing.T, body map[string]interface{}, expected string) {
	t.Helper()

	latest, ok := body["latest"].(map[string]interface{})
	if !ok {
		t.Fatalf("expected latest verification summary object, got body=%v", body)
	}

	got, _ := latest["verificationMode"].(string)
	if got != expected {
		t.Fatalf("expected latest.verificationMode=%s, got=%s body=%v", expected, got, body)
	}
}

func assertPortalNestedBool(t *testing.T, body map[string]interface{}, objectKey string, valueKey string, expected bool) {
	t.Helper()

	object, ok := body[objectKey].(map[string]interface{})
	if !ok {
		t.Fatalf("expected %s object, got body=%v", objectKey, body)
	}

	got, ok := object[valueKey].(bool)
	if !ok {
		t.Fatalf("expected %s.%s to be a bool, got object=%v", objectKey, valueKey, object)
	}

	if got != expected {
		t.Fatalf("expected %s.%s=%v, got=%v object=%v", objectKey, valueKey, expected, got, object)
	}
}

func TestEvidenceStorePythonRuntimeEnvOverride(t *testing.T) {
	t.Setenv("S_SENTINEL_PYTHON_BIN", "custom-python")

	api := &portalAPI{}

	got := api.evidenceService().PythonBin()
	if got != "custom-python" {
		t.Fatalf("expected python runtime override custom-python, got %s", got)
	}
}

func assertPortalStringNotEmpty(t *testing.T, body map[string]interface{}, key string) {
	t.Helper()

	got, ok := body[key].(string)
	if !ok {
		t.Fatalf("expected %s to be a string, got body=%v", key, body)
	}

	if got == "" {
		t.Fatalf("expected %s to be non-empty, got body=%v", key, body)
	}
}

func assertPortalNestedString(
	t *testing.T,
	body map[string]interface{},
	parent string,
	child string,
	expected string,
) {
	t.Helper()

	nested, ok := body[parent].(map[string]interface{})
	if !ok {
		t.Fatalf("expected %s to be an object, got %#v", parent, body[parent])
	}

	got, ok := nested[child].(string)
	if !ok {
		t.Fatalf("expected %s.%s to be a string, got %#v", parent, child, nested[child])
	}

	if got != expected {
		t.Fatalf("expected %s.%s=%s, got %s", parent, child, expected, got)
	}
}
