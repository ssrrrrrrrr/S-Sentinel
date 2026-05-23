package main

import (
	"database/sql"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestPortalEvidenceAPIResponseControlPlaneContractNativeSQLite(t *testing.T) {
	dbFile := createNativeSQLiteTestDB(t)

	t.Setenv("S_SENTINEL_EVIDENCE_STORE_DB", dbFile)
	t.Setenv("S_SENTINEL_EVIDENCE_REPOSITORY_MODE", "native-sqlite")

	api := &portalAPI{
		cfg: Config{
			RepoDir: t.TempDir(),
		},
		reportDir: t.TempDir(),
	}

	releaseID := "20260101-000000"

	cases := []struct {
		name          string
		handler       http.HandlerFunc
		target        string
		schemaVersion string
	}{
		{
			name:          "release-list",
			handler:       api.handleEvidenceStoreReleaseList,
			target:        "/api/evidence/releases?limit=10",
			schemaVersion: "evidence.store.releaseList/v1alpha1",
		},
		{
			name:          "release-detail",
			handler:       api.handleEvidenceStoreReleaseDetail,
			target:        "/api/evidence/releases/" + releaseID + "?includeRaw=true",
			schemaVersion: "evidence.store.release/v1alpha1",
		},
		{
			name:          "object-detail",
			handler:       api.handleEvidenceStoreObjectDetail,
			target:        "/api/evidence/objects/releaseEvidence/re-" + releaseID + "?releaseId=" + releaseID + "&includeRaw=true",
			schemaVersion: "evidence.store.object/v1alpha1",
		},
		{
			name:          "artifact-list",
			handler:       api.handleEvidenceArtifactList,
			target:        "/api/evidence/artifacts?releaseId=" + releaseID,
			schemaVersion: "evidence.store.artifactList/v1alpha1",
		},
		{
			name:          "search",
			handler:       api.handleEvidenceSearch,
			target:        "/api/evidence/search?q=demo-app&limit=10",
			schemaVersion: "evidence.store.search/v1alpha1",
		},
		{
			name:          "verification-summary",
			handler:       api.handleEvidenceVerificationSummary,
			target:        "/api/evidence/verification-summary?releaseId=" + releaseID,
			schemaVersion: "evidence.store.verificationSummary/v1alpha1",
		},
		{
			name:          "graph",
			handler:       api.handleEvidenceGraph,
			target:        "/api/evidence/graph?releaseId=" + releaseID,
			schemaVersion: "evidence.store.graph/v1alpha1",
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			body, rec := callPortalEvidenceStoreHandlerWithRecorder(
				t,
				tc.handler,
				http.MethodGet,
				tc.target,
				http.StatusOK,
			)

			assertPortalSchema(t, body, tc.schemaVersion)
			requireEvidenceAPIControlPlaneContract(t, body, "native-sqlite", "native-sqlite-repository", false)
			requireEvidenceAPIResponseHeaders(t, rec, "native-sqlite", "native-sqlite-repository")
		})
	}
}

func TestPortalEvidenceAPIErrorControlPlaneContractForNativeSchemaMismatch(t *testing.T) {
	dbFile := createNativeSQLiteTestDB(t)

	db, err := sql.Open("sqlite", dbFile)
	if err != nil {
		t.Fatalf("open sqlite test db: %v", err)
	}
	if _, err := db.Exec("PRAGMA user_version = 2"); err != nil {
		_ = db.Close()
		t.Fatalf("corrupt sqlite user_version: %v", err)
	}
	if err := db.Close(); err != nil {
		t.Fatalf("close sqlite test db: %v", err)
	}

	t.Setenv("S_SENTINEL_EVIDENCE_STORE_DB", dbFile)
	t.Setenv("S_SENTINEL_EVIDENCE_REPOSITORY_MODE", "native-sqlite")

	api := &portalAPI{
		cfg: Config{
			RepoDir: t.TempDir(),
		},
		reportDir: t.TempDir(),
	}

	body, _ := callPortalEvidenceStoreHandlerWithRecorder(
		t,
		api.handleEvidenceStoreReleaseList,
		http.MethodGet,
		"/api/evidence/releases?limit=10",
		http.StatusConflict,
	)

	assertPortalSchema(t, body, "evidence.store.adapter.error/v1alpha1")
	requireEvidenceAPIControlPlaneContract(t, body, "native-sqlite", "native-sqlite-repository", false)

	message, _ := body["error"].(string)
	if !strings.Contains(message, "incompatible EvidenceStore schema") {
		t.Fatalf("expected incompatible schema error, got %#v", body["error"])
	}

	controlPlane := requireEvidenceAPIMap(t, body, "controlPlane")
	requireEvidenceAPIString(t, controlPlane, "operation", "query-error")
}

func requireEvidenceAPIResponseHeaders(
	t *testing.T,
	rec *httptest.ResponseRecorder,
	expectedRepositoryType string,
	expectedRepositoryMode string,
) {
	t.Helper()

	if got := rec.Header().Get("X-S-Sentinel-Evidence-Runtime-Mode"); got != "cli-sqlite-runtime" {
		t.Fatalf("expected runtime mode header cli-sqlite-runtime, got %q", got)
	}

	if got := rec.Header().Get("X-S-Sentinel-Evidence-Repository-Type"); got != expectedRepositoryType {
		t.Fatalf("expected repository type header %s, got %q", expectedRepositoryType, got)
	}

	if got := rec.Header().Get("X-S-Sentinel-Evidence-Repository-Mode"); got != expectedRepositoryMode {
		t.Fatalf("expected repository mode header %s, got %q", expectedRepositoryMode, got)
	}

	if got := rec.Header().Get("X-S-Sentinel-Evidence-Repository-Contract"); got != "evidence.repository/v1alpha1" {
		t.Fatalf("expected repository contract header evidence.repository/v1alpha1, got %q", got)
	}

	if got := rec.Header().Get("X-S-Sentinel-Evidence-DB"); got == "" {
		t.Fatal("expected evidence db header to be set")
	}
}

func requireEvidenceAPIControlPlaneContract(
	t *testing.T,
	body map[string]interface{},
	expectedRepositoryType string,
	expectedRepositoryMode string,
	expectedMutatesLocalEvidenceIndex bool,
) {
	t.Helper()

	controlPlane := requireEvidenceAPIMap(t, body, "controlPlane")

	requireEvidenceAPIString(t, controlPlane, "schemaVersion", "evidence.api.controlPlane/v1alpha1")
	requireEvidenceAPIString(t, controlPlane, "apiVersion", "s-sentinel.io/evidence-api/v1alpha1")
	requireEvidenceAPIString(t, controlPlane, "contractVersion", "evidence.api.response/v1alpha1")
	requireEvidenceAPIString(t, controlPlane, "generatedBy", "s-sentinel-evidence-api")
	requireEvidenceAPIString(t, controlPlane, "runtimeMode", "cli-sqlite-runtime")
	requireEvidenceAPIString(t, controlPlane, "repositoryType", expectedRepositoryType)
	requireEvidenceAPIString(t, controlPlane, "repositoryMode", expectedRepositoryMode)
	requireEvidenceAPIString(t, controlPlane, "repositoryContract", "evidence.repository/v1alpha1")

	requireEvidenceAPIBool(t, controlPlane, "readOnly", true)
	requireEvidenceAPIBool(t, controlPlane, "willExecute", false)
	requireEvidenceAPIBool(t, controlPlane, "doesNotModifyCluster", true)
	requireEvidenceAPIBool(t, controlPlane, "doesNotModifyGitOps", true)
	requireEvidenceAPIBool(t, controlPlane, "doesNotTriggerRollout", true)
	requireEvidenceAPIBool(t, controlPlane, "mutatesLocalEvidenceIndex", expectedMutatesLocalEvidenceIndex)

	service := requireEvidenceAPIMap(t, controlPlane, "service")
	requireEvidenceAPIString(t, service, "schemaVersion", "evidence.service/v1alpha1")
	requireEvidenceAPIString(t, service, "contractVersion", "evidence.api.service/v1alpha1")
	requireEvidenceAPIBool(t, service, "readOnly", true)
	requireEvidenceAPIBool(t, service, "willExecute", false)

	runtime := requireEvidenceAPIMap(t, controlPlane, "runtime")
	requireEvidenceAPIString(t, runtime, "contractVersion", "evidence.runtime/v1alpha1")
	requireEvidenceAPIString(t, runtime, "mode", "cli-sqlite-runtime")

	repository := requireEvidenceAPIMap(t, controlPlane, "repository")
	requireEvidenceAPIString(t, repository, "contractVersion", "evidence.repository/v1alpha1")
	requireEvidenceAPIString(t, repository, "repositoryType", expectedRepositoryType)
	requireEvidenceAPIString(t, repository, "mode", expectedRepositoryMode)
	requireEvidenceAPIBool(t, repository, "readOnly", true)
	requireEvidenceAPIBool(t, repository, "willExecute", false)

	capabilities := requireEvidenceAPIMap(t, controlPlane, "capabilities")
	requireEvidenceAPIBool(t, capabilities, "readOnly", true)
	requireEvidenceAPIBool(t, capabilities, "willExecute", false)
	requireEvidenceAPIBool(t, capabilities, "nativeSQLiteRepository", expectedRepositoryType == "native-sqlite")

	schemaContract := requireEvidenceAPIMap(t, controlPlane, "schemaContract")
	requireEvidenceAPIString(t, schemaContract, "schemaVersion", "evidence.store.schemaContract/v1alpha1")
	requireEvidenceAPIString(t, schemaContract, "storeSchemaVersion", "evidence.store.sqlite/v1alpha1")
	requireEvidenceAPIString(t, schemaContract, "compatibilityPolicy", "exact-match")
	requireEvidenceAPIString(t, schemaContract, "onMismatch", "reject-native-read-query")
	requireEvidenceAPINumber(t, schemaContract, "currentVersion", 1)
	requireEvidenceAPINumber(t, schemaContract, "sqliteUserVersion", 1)

	mutationSemantics := requireEvidenceAPIMap(t, controlPlane, "mutationSemantics")
	requireEvidenceAPIBool(t, mutationSemantics, "doesNotModifyCluster", true)
	requireEvidenceAPIBool(t, mutationSemantics, "doesNotModifyGitOps", true)
	requireEvidenceAPIBool(t, mutationSemantics, "doesNotTriggerRollout", true)
	requireEvidenceAPIBool(t, mutationSemantics, "mutatesLocalEvidenceIndex", expectedMutatesLocalEvidenceIndex)
}

func requireEvidenceAPIMap(t *testing.T, parent map[string]interface{}, key string) map[string]interface{} {
	t.Helper()

	value, ok := parent[key].(map[string]interface{})
	if !ok {
		t.Fatalf("expected %s to be object, got %#v", key, parent[key])
	}

	return value
}

func requireEvidenceAPIString(t *testing.T, parent map[string]interface{}, key string, expected string) {
	t.Helper()

	got, ok := parent[key].(string)
	if !ok {
		t.Fatalf("expected %s to be string, got %#v", key, parent[key])
	}

	if got != expected {
		t.Fatalf("expected %s=%s, got %s", key, expected, got)
	}
}

func requireEvidenceAPIBool(t *testing.T, parent map[string]interface{}, key string, expected bool) {
	t.Helper()

	got, ok := parent[key].(bool)
	if !ok {
		t.Fatalf("expected %s to be bool, got %#v", key, parent[key])
	}

	if got != expected {
		t.Fatalf("expected %s=%v, got %v", key, expected, got)
	}
}

func requireEvidenceAPINumber(t *testing.T, parent map[string]interface{}, key string, expected float64) {
	t.Helper()

	got, ok := parent[key].(float64)
	if !ok {
		t.Fatalf("expected %s to be number, got %#v", key, parent[key])
	}

	if got != expected {
		t.Fatalf("expected %s=%v, got %v", key, expected, got)
	}
}
