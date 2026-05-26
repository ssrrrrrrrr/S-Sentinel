package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestGitOpsRealPREvidenceStoreAndPortalLatestResource(t *testing.T) {
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

	releaseID := "20260526-230000"
	createID := "gprcreate-" + releaseID
	cleanupID := "gprcleanup-" + releaseID

	releaseEvidence := `{
  "schemaVersion": "release.evidence.bundle/v1alpha1",
  "generatedBy": "portal_api_gitops_real_pr_e2e_test.go",
  "releaseId": "` + releaseID + `",
  "releaseResult": "STOP_PROMOTION",
  "policyDecision": "REQUIRE_HUMAN_APPROVAL",
  "service": "demo-app",
  "namespace": "slo-rollout",
  "env": "dev",
  "artifacts": {
    "gitopsRealPRCreate": "gitops-real-pr-create-` + releaseID + `.json",
    "gitopsRealPRCleanup": "gitops-real-pr-cleanup-` + releaseID + `.json"
  }
}`

	createReceipt := `{
  "schemaVersion": "gitops.real.pr.create/v1alpha1",
  "gitopsRealPRCreateId": "` + createID + `",
  "release": {
    "releaseId": "` + releaseID + `",
    "service": "demo-app",
    "namespace": "slo-rollout",
    "env": "dev"
  },
  "pullRequest": {
    "createStatus": "PULL_REQUEST_CREATED",
    "repo": "ssrrrrrrrr/S-Sentinel",
    "number": 7,
    "state": "OPEN",
    "url": "https://github.com/ssrrrrrrrr/S-Sentinel/pull/7",
    "headRefName": "ssentinel/e2e-real-pr",
    "baseRefName": "main",
    "mergeStateStatus": "CLEAN"
  },
  "guardrails": {
    "didCreatePullRequest": true,
    "doesNotMergePullRequest": true,
    "doesNotModifyKubernetes": true
  }
}`

	cleanupReceipt := `{
  "schemaVersion": "gitops.real.pr.cleanup/v1alpha1",
  "gitopsRealPRCleanupId": "` + cleanupID + `",
  "release": {
    "releaseId": "` + releaseID + `",
    "service": "demo-app",
    "namespace": "slo-rollout",
    "env": "dev"
  },
  "cleanupStatus": "CLEANED_UP",
  "pullRequest": {
    "number": 7,
    "state": "CLOSED",
    "url": "https://github.com/ssrrrrrrrr/S-Sentinel/pull/7",
    "headRefName": "ssentinel/e2e-real-pr",
    "baseRefName": "main"
  },
  "remoteBranchExists": false,
  "guardrails": {
    "didClosePullRequest": true,
    "didDeleteRemoteBranch": true,
    "doesNotMergePullRequest": true,
    "doesNotModifyKubernetes": true
  }
}`

	writeB4TestFile(t, filepath.Join(reportDir, "release-evidence-"+releaseID+".json"), releaseEvidence)
	writeB4TestFile(t, filepath.Join(reportDir, "gitops-real-pr-create-"+releaseID+".json"), createReceipt)
	writeB4TestFile(t, filepath.Join(reportDir, "gitops-real-pr-create-latest.json"), createReceipt)
	writeB4TestFile(t, filepath.Join(reportDir, "gitops-real-pr-cleanup-"+releaseID+".json"), cleanupReceipt)

	api := &portalAPI{
		cfg: Config{
			RepoDir: tempRepo,
		},
		reportDir: reportDir,
	}

	latestCreate := callB4PortalJSON(t, api.handleLatestResource("gitopsRealPRCreate"), http.MethodGet, "/api/releases/latest/gitops-real-pr-create", http.StatusOK)
	requireB4String(t, latestCreate, "gitopsRealPRCreateId", createID)
	requireB4NestedString(t, latestCreate, "pullRequest", "createStatus", "PULL_REQUEST_CREATED")

	refresh := callB4PortalJSON(t, api.handleEvidenceStoreRefresh, http.MethodPost, "/api/evidence-store/refresh", http.StatusOK)
	requireB4String(t, refresh, "schemaVersion", "evidence.store.refresh/v1alpha1")

	createObject := callB4PortalJSON(t, api.handleEvidenceStoreObjectDetail, http.MethodGet, "/api/evidence/objects/gitopsRealPRCreate/"+createID+"?releaseId="+releaseID+"&includeRaw=true", http.StatusOK)
	requireB4String(t, createObject, "schemaVersion", "evidence.store.object/v1alpha1")
	requireB4JSONContains(t, createObject, "gitopsRealPRCreate")
	requireB4JSONContains(t, createObject, "PULL_REQUEST_CREATED")

	cleanupObject := callB4PortalJSON(t, api.handleEvidenceStoreObjectDetail, http.MethodGet, "/api/evidence/objects/gitopsRealPRCleanup/"+cleanupID+"?releaseId="+releaseID+"&includeRaw=true", http.StatusOK)
	requireB4String(t, cleanupObject, "schemaVersion", "evidence.store.object/v1alpha1")
	requireB4JSONContains(t, cleanupObject, "gitopsRealPRCleanup")
	requireB4JSONContains(t, cleanupObject, "CLEANED_UP")

	releaseDetail := callB4PortalJSON(t, api.handleEvidenceStoreReleaseDetail, http.MethodGet, "/api/evidence/releases/"+releaseID+"?includeRaw=true", http.StatusOK)
	requireB4String(t, releaseDetail, "schemaVersion", "evidence.store.release/v1alpha1")
	requireB4JSONContains(t, releaseDetail, "gitopsRealPRCreate")
	requireB4JSONContains(t, releaseDetail, "gitopsRealPRCleanup")
	requireB4JSONContains(t, releaseDetail, createID)
	requireB4JSONContains(t, releaseDetail, cleanupID)
}

func writeB4TestFile(t *testing.T, path string, content string) {
	t.Helper()

	if err := os.WriteFile(path, []byte(content), 0644); err != nil {
		t.Fatalf("write %s: %v", path, err)
	}
}

func callB4PortalJSON(t *testing.T, handler http.HandlerFunc, method string, target string, wantStatus int) map[string]interface{} {
	t.Helper()

	req := httptest.NewRequest(method, target, nil)
	rec := httptest.NewRecorder()
	handler(rec, req)

	if rec.Code != wantStatus {
		t.Fatalf("%s %s status = %d, want %d, body: %s", method, target, rec.Code, wantStatus, rec.Body.String())
	}

	var body map[string]interface{}
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode json body for %s %s: %v\nbody: %s", method, target, err, rec.Body.String())
	}

	return body
}

func requireB4String(t *testing.T, body map[string]interface{}, key string, want string) {
	t.Helper()

	got, _ := body[key].(string)
	if got != want {
		t.Fatalf("%s = %q, want %q", key, got, want)
	}
}

func requireB4NestedString(t *testing.T, body map[string]interface{}, parent string, key string, want string) {
	t.Helper()

	parentValue, ok := body[parent].(map[string]interface{})
	if !ok {
		t.Fatalf("%s is not an object: %#v", parent, body[parent])
	}

	got, _ := parentValue[key].(string)
	if got != want {
		t.Fatalf("%s.%s = %q, want %q", parent, key, got, want)
	}
}

func requireB4JSONContains(t *testing.T, body map[string]interface{}, needle string) {
	t.Helper()

	data, err := json.Marshal(body)
	if err != nil {
		t.Fatalf("marshal json body: %v", err)
	}

	if !strings.Contains(string(data), needle) {
		t.Fatalf("json body does not contain %q: %s", needle, string(data))
	}
}
