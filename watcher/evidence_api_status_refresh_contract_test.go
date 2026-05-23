package main

import (
	"net/http"
	"os"
	"path/filepath"
	"testing"
)

func TestPortalEvidenceStoreStatusRefreshRuntimeContract(t *testing.T) {
	api, releaseID := newEvidenceStatusRefreshContractAPI(t)

	statusBeforeRefresh, _ := callPortalEvidenceStoreHandlerWithRecorder(
		t,
		api.handleEvidenceStoreStatus,
		http.MethodGet,
		"/api/evidence-store/status",
		http.StatusOK,
	)

	assertPortalSchema(t, statusBeforeRefresh, "evidence.store.status/v1alpha1")
	assertPortalBool(t, statusBeforeRefresh, "readOnly", true)
	assertPortalBool(t, statusBeforeRefresh, "willExecute", false)
	assertPortalBool(t, statusBeforeRefresh, "doesNotModifyCluster", true)
	assertPortalBool(t, statusBeforeRefresh, "doesNotModifyGitOps", true)
	assertPortalBool(t, statusBeforeRefresh, "doesNotTriggerRollout", true)
	assertPortalBool(t, statusBeforeRefresh, "mutatesLocalEvidenceIndex", false)
	requireEvidenceAPIControlPlaneContract(t, statusBeforeRefresh, "cli-backed", "cli-repository", false)

	statusSchemaContract := requireEvidenceAPIMap(t, statusBeforeRefresh, "schemaContract")
	requireEvidenceAPIString(t, statusSchemaContract, "schemaVersion", "evidence.store.schemaContract/v1alpha1")
	requireEvidenceAPIString(t, statusSchemaContract, "onMismatch", "reject-native-read-query")

	statusSchemaHealth := requireEvidenceAPIMap(t, statusBeforeRefresh, "schemaHealth")
	requireEvidenceAPIString(t, statusSchemaHealth, "schemaVersion", "evidence.store.schemaHealth/v1alpha1")
	requireEvidenceAPIBool(t, statusSchemaHealth, "readOnly", true)
	requireEvidenceAPIBool(t, statusSchemaHealth, "willExecute", false)
	requireEvidenceAPIBool(t, statusSchemaHealth, "compatible", false)
	requireEvidenceAPIBool(t, statusSchemaHealth, "ready", false)

	methodError, _ := callPortalEvidenceStoreHandlerWithRecorder(
		t,
		api.handleEvidenceStoreRefresh,
		http.MethodGet,
		"/api/evidence-store/refresh",
		http.StatusMethodNotAllowed,
	)
	assertPortalSchema(t, methodError, "evidence.store.refresh.error/v1alpha1")
	assertPortalBool(t, methodError, "readOnly", true)
	assertPortalBool(t, methodError, "willExecute", false)
	assertPortalBool(t, methodError, "doesNotModifyCluster", true)
	assertPortalBool(t, methodError, "doesNotModifyGitOps", true)
	assertPortalBool(t, methodError, "doesNotTriggerRollout", true)
	assertPortalBool(t, methodError, "mutatesLocalEvidenceIndex", false)
	requireEvidenceAPIControlPlaneContract(t, methodError, "cli-backed", "cli-repository", false)
	methodControlPlane := requireEvidenceAPIMap(t, methodError, "controlPlane")
	requireEvidenceAPIString(t, methodControlPlane, "operation", "refresh")

	refreshBody, _ := callPortalEvidenceStoreHandlerWithRecorder(
		t,
		api.handleEvidenceStoreRefresh,
		http.MethodPost,
		"/api/evidence-store/refresh",
		http.StatusOK,
	)

	assertPortalSchema(t, refreshBody, "evidence.store.refresh/v1alpha1")
	assertPortalLatestReleaseID(t, refreshBody, releaseID)
	assertPortalBool(t, refreshBody, "readOnly", true)
	assertPortalBool(t, refreshBody, "willExecute", false)
	assertPortalBool(t, refreshBody, "doesNotModifyCluster", true)
	assertPortalBool(t, refreshBody, "doesNotModifyGitOps", true)
	assertPortalBool(t, refreshBody, "doesNotTriggerRollout", true)
	assertPortalBool(t, refreshBody, "mutatesLocalEvidenceIndex", true)
	requireEvidenceAPIControlPlaneContract(t, refreshBody, "cli-backed", "cli-repository", true)
	refreshControlPlane := requireEvidenceAPIMap(t, refreshBody, "controlPlane")
	requireEvidenceAPIString(t, refreshControlPlane, "operation", "refresh")

	statusAfterRefresh, _ := callPortalEvidenceStoreHandlerWithRecorder(
		t,
		api.handleEvidenceStoreStatus,
		http.MethodGet,
		"/api/evidence-store/status",
		http.StatusOK,
	)

	assertPortalSchema(t, statusAfterRefresh, "evidence.store.status/v1alpha1")
	assertPortalBool(t, statusAfterRefresh, "ready", true)
	assertPortalBool(t, statusAfterRefresh, "schemaCompatible", true)
	assertPortalBool(t, statusAfterRefresh, "schemaReady", true)
	requireEvidenceAPIControlPlaneContract(t, statusAfterRefresh, "cli-backed", "cli-repository", false)

	statusAfterSchemaHealth := requireEvidenceAPIMap(t, statusAfterRefresh, "schemaHealth")
	requireEvidenceAPIString(t, statusAfterSchemaHealth, "schemaVersion", "evidence.store.schemaHealth/v1alpha1")
	requireEvidenceAPIString(t, statusAfterSchemaHealth, "storeSchemaVersion", "evidence.store.sqlite/v1alpha1")
	requireEvidenceAPINumber(t, statusAfterSchemaHealth, "currentVersion", 1)
	requireEvidenceAPINumber(t, statusAfterSchemaHealth, "sqliteUserVersion", 1)
	requireEvidenceAPIBool(t, statusAfterSchemaHealth, "compatible", true)
	requireEvidenceAPIBool(t, statusAfterSchemaHealth, "ready", true)
}

func newEvidenceStatusRefreshContractAPI(t *testing.T) (*portalAPI, string) {
	t.Helper()

	root, err := filepath.Abs("..")
	if err != nil {
		t.Fatalf("resolve repo root: %v", err)
	}

	tempRepo := t.TempDir()
	tempDB := filepath.Join(t.TempDir(), "evidence-store.db")
	t.Setenv("S_SENTINEL_EVIDENCE_STORE_DB", tempDB)
	t.Setenv("S_SENTINEL_EVIDENCE_REPOSITORY_MODE", "")

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

	releaseID := "20260101-000000"

	releaseEvidence := `{
  "schemaVersion": "release.evidence.bundle/v1alpha1",
  "generatedBy": "evidence_api_status_refresh_contract_test.go",
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

	if err := os.WriteFile(filepath.Join(reportDir, "release-evidence-"+releaseID+".json"), []byte(releaseEvidence), 0644); err != nil {
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

	if err := os.WriteFile(filepath.Join(reportDir, "signed-release-gate-"+releaseID+".json"), []byte(signedReleaseGate), 0644); err != nil {
		t.Fatalf("write signed release gate: %v", err)
	}

	api := &portalAPI{
		cfg: Config{
			RepoDir: tempRepo,
		},
		reportDir: reportDir,
	}

	return api, releaseID
}
