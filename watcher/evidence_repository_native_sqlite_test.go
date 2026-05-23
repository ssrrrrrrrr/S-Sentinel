package main

import (
	"database/sql"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"testing"
)

func TestEvidenceRepositoryFactoryDefaultAndNativeSQLite(t *testing.T) {
	t.Setenv("S_SENTINEL_EVIDENCE_REPOSITORY_MODE", "")

	runtime := NewCLIEvidenceRuntime(t.TempDir())
	defaultRepo := NewEvidenceRepositoryForRuntime(runtime)
	defaultDescriptor := defaultRepo.Descriptor()

	if defaultDescriptor.RepositoryType != "cli-backed" {
		t.Fatalf("expected default repositoryType=cli-backed, got %s", defaultDescriptor.RepositoryType)
	}

	t.Setenv("S_SENTINEL_EVIDENCE_REPOSITORY_MODE", "native-sqlite")

	nativeRepo := NewEvidenceRepositoryForRuntime(runtime)
	nativeDescriptor := nativeRepo.Descriptor()

	if nativeDescriptor.RepositoryType != "native-sqlite" {
		t.Fatalf("expected native repositoryType=native-sqlite, got %s", nativeDescriptor.RepositoryType)
	}

	if nativeDescriptor.Mode != "native-sqlite-repository" {
		t.Fatalf("expected native mode=native-sqlite-repository, got %s", nativeDescriptor.Mode)
	}

	if !nativeDescriptor.SupportsNativeSQLite {
		t.Fatal("expected native repository to advertise SupportsNativeSQLite=true")
	}
}

func TestNativeSQLiteEvidenceRepositoryListReleasesAndGetObject(t *testing.T) {
	dbFile := createNativeSQLiteTestDB(t)

	t.Setenv("S_SENTINEL_EVIDENCE_STORE_DB", dbFile)
	t.Setenv("S_SENTINEL_EVIDENCE_REPOSITORY_MODE", "native-sqlite")

	runtime := NewCLIEvidenceRuntime(t.TempDir())
	repo := NewEvidenceRepositoryForRuntime(runtime)

	req := httptest.NewRequest(http.MethodGet, "/api/evidence/releases?limit=10", nil)

	listResponse, err := repo.ListReleases(req, EvidenceReleaseListQuery{Limit: "10"})
	if err != nil {
		t.Fatalf("native list releases failed: %v", err)
	}

	if listResponse.Repository.RepositoryType != "native-sqlite" {
		t.Fatalf("expected native repository response, got %s", listResponse.Repository.RepositoryType)
	}

	listBody := map[string]interface{}{}
	if err := json.Unmarshal(listResponse.Body, &listBody); err != nil {
		t.Fatalf("decode native list response: %v", err)
	}

	assertPortalSchema(t, listBody, "evidence.store.releaseList/v1alpha1")
	assertPortalNumberAtLeast(t, listBody, "count", 1)

	items, ok := listBody["items"].([]interface{})
	if !ok || len(items) != 1 {
		t.Fatalf("expected one release item, got %#v", listBody["items"])
	}

	objectResponse, err := repo.GetObject(req, EvidenceObjectQuery{
		ObjectType: "releaseEvidence",
		ObjectID:   "re-20260101-000000",
		ReleaseID:  "20260101-000000",
		IncludeRaw: true,
	})
	if err != nil {
		t.Fatalf("native get object failed: %v", err)
	}

	objectBody := map[string]interface{}{}
	if err := json.Unmarshal(objectResponse.Body, &objectBody); err != nil {
		t.Fatalf("decode native object response: %v", err)
	}

	assertPortalSchema(t, objectBody, "evidence.store.object/v1alpha1")

	object, ok := objectBody["object"].(map[string]interface{})
	if !ok {
		t.Fatalf("expected object body, got %#v", objectBody["object"])
	}

	summary, ok := object["summary"].(map[string]interface{})
	if !ok {
		t.Fatalf("expected object.summary, got %#v", object["summary"])
	}

	if summary["releaseResult"] != "PASS" {
		t.Fatalf("expected summary.releaseResult=PASS, got %#v", summary["releaseResult"])
	}

	raw, ok := object["raw"].(map[string]interface{})
	if !ok {
		t.Fatalf("expected object.raw, got %#v", object["raw"])
	}

	if raw["schemaVersion"] != "release.evidence.bundle/v1alpha1" {
		t.Fatalf("expected raw schemaVersion, got %#v", raw["schemaVersion"])
	}
}

func TestPortalEvidenceAPINativeSQLiteRepositoryIntegration(t *testing.T) {
	dbFile := createNativeSQLiteTestDB(t)

	t.Setenv("S_SENTINEL_EVIDENCE_STORE_DB", dbFile)
	t.Setenv("S_SENTINEL_EVIDENCE_REPOSITORY_MODE", "native-sqlite")

	api := &portalAPI{
		cfg: Config{
			RepoDir: t.TempDir(),
		},
		reportDir: t.TempDir(),
	}

	listBody, listRecorder := callPortalEvidenceStoreHandlerWithRecorder(
		t,
		api.handleEvidenceStoreReleaseList,
		http.MethodGet,
		"/api/evidence/releases?limit=10",
		http.StatusOK,
	)

	assertPortalSchema(t, listBody, "evidence.store.releaseList/v1alpha1")
	assertPortalNestedString(t, listBody, "controlPlane", "repositoryType", "native-sqlite")
	assertPortalNestedString(t, listBody, "controlPlane", "repositoryMode", "native-sqlite-repository")
	assertPortalNestedString(t, listBody, "controlPlane", "runtimeMode", "cli-sqlite-runtime")

	if got := listRecorder.Header().Get("X-S-Sentinel-Evidence-Repository-Type"); got != "native-sqlite" {
		t.Fatalf("expected native sqlite repository header, got %q", got)
	}

	objectBody, objectRecorder := callPortalEvidenceStoreHandlerWithRecorder(
		t,
		api.handleEvidenceStoreObjectDetail,
		http.MethodGet,
		"/api/evidence/objects/releaseEvidence/re-20260101-000000?releaseId=20260101-000000&includeRaw=true",
		http.StatusOK,
	)

	assertPortalSchema(t, objectBody, "evidence.store.object/v1alpha1")
	assertPortalNestedString(t, objectBody, "controlPlane", "repositoryType", "native-sqlite")
	assertPortalNestedString(t, objectBody, "controlPlane", "repositoryMode", "native-sqlite-repository")

	if got := objectRecorder.Header().Get("X-S-Sentinel-Evidence-Repository-Type"); got != "native-sqlite" {
		t.Fatalf("expected native sqlite repository header for object endpoint, got %q", got)
	}

	detailBody, _ := callPortalEvidenceStoreHandlerWithRecorder(
		t,
		api.handleEvidenceStoreReleaseDetail,
		http.MethodGet,
		"/api/evidence/releases/20260101-000000?includeRaw=true",
		http.StatusOK,
	)
	assertPortalSchema(t, detailBody, "evidence.store.release/v1alpha1")
	assertPortalNestedString(t, detailBody, "controlPlane", "repositoryType", "native-sqlite")
	assertPortalNumberAtLeast(t, detailBody, "objectCount", 2)
	assertPortalNumberAtLeast(t, detailBody, "artifactCount", 1)

	artifactBody, _ := callPortalEvidenceStoreHandlerWithRecorder(
		t,
		api.handleEvidenceArtifactList,
		http.MethodGet,
		"/api/evidence/artifacts?releaseId=20260101-000000",
		http.StatusOK,
	)
	assertPortalSchema(t, artifactBody, "evidence.store.artifactList/v1alpha1")
	assertPortalNestedString(t, artifactBody, "controlPlane", "repositoryType", "native-sqlite")
	assertPortalNumberAtLeast(t, artifactBody, "count", 1)

	searchBody, _ := callPortalEvidenceStoreHandlerWithRecorder(
		t,
		api.handleEvidenceSearch,
		http.MethodGet,
		"/api/evidence/search?q=demo-app&limit=10",
		http.StatusOK,
	)
	assertPortalSchema(t, searchBody, "evidence.store.search/v1alpha1")
	assertPortalNestedString(t, searchBody, "controlPlane", "repositoryType", "native-sqlite")
	assertPortalNumberAtLeast(t, searchBody, "count", 1)

	verificationBody, _ := callPortalEvidenceStoreHandlerWithRecorder(
		t,
		api.handleEvidenceVerificationSummary,
		http.MethodGet,
		"/api/evidence/verification-summary?releaseId=20260101-000000",
		http.StatusOK,
	)
	assertPortalSchema(t, verificationBody, "evidence.store.verificationSummary/v1alpha1")
	assertPortalNestedString(t, verificationBody, "controlPlane", "repositoryType", "native-sqlite")
	assertPortalNumberAtLeast(t, verificationBody, "count", 1)

	graphBody, _ := callPortalEvidenceStoreHandlerWithRecorder(
		t,
		api.handleEvidenceGraph,
		http.MethodGet,
		"/api/evidence/graph?releaseId=20260101-000000",
		http.StatusOK,
	)
	assertPortalSchema(t, graphBody, "evidence.store.graph/v1alpha1")
	assertPortalNestedString(t, graphBody, "controlPlane", "repositoryType", "native-sqlite")
	assertPortalNumberAtLeast(t, graphBody, "nodeCount", 4)
	assertPortalNumberAtLeast(t, graphBody, "edgeCount", 3)
}

func callPortalEvidenceStoreHandlerWithRecorder(
	t *testing.T,
	handler http.HandlerFunc,
	method string,
	target string,
	expectedStatus int,
) (map[string]interface{}, *httptest.ResponseRecorder) {
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

	return body, rec
}

func createNativeSQLiteTestDB(t *testing.T) string {
	t.Helper()

	dbFile := filepath.Join(t.TempDir(), "evidence-store.db")

	db, err := sql.Open("sqlite", dbFile)
	if err != nil {
		t.Fatalf("open sqlite test db: %v", err)
	}
	defer db.Close()

	_, err = db.Exec(`
CREATE TABLE releases (
  release_id TEXT PRIMARY KEY,
  service TEXT,
  namespace TEXT,
  env TEXT,
  version TEXT,
  commit_sha TEXT,
  image TEXT,
  image_digest TEXT,
  release_result TEXT,
  policy_decision TEXT,
  final_action TEXT,
  risk_level TEXT,
  risk_score REAL,
  requires_human_approval INTEGER,
  generated_at TEXT,
  first_seen_at TEXT NOT NULL,
  last_seen_at TEXT NOT NULL
);

CREATE TABLE evidence_objects (
  object_pk TEXT PRIMARY KEY,
  object_type TEXT NOT NULL,
  object_id TEXT NOT NULL,
  release_id TEXT NOT NULL,
  schema_version TEXT,
  source_path TEXT NOT NULL,
  source_mtime TEXT,
  content_sha256 TEXT NOT NULL,
  generated_at TEXT,
  imported_at TEXT NOT NULL,
  summary_json TEXT NOT NULL,
  raw_json TEXT NOT NULL
);

CREATE TABLE release_artifacts (
  release_id TEXT NOT NULL,
  artifact_kind TEXT NOT NULL,
  path TEXT NOT NULL,
  exists_flag INTEGER,
  content_type TEXT,
  size_bytes INTEGER,
  modified_at TEXT,
  source_object_pk TEXT,
  PRIMARY KEY (release_id, artifact_kind, path)
);
`)
	if err != nil {
		t.Fatalf("create sqlite schema: %v", err)
	}

	_, err = db.Exec(
		`
INSERT INTO releases (
  release_id, service, namespace, env, version, commit_sha, image, image_digest,
  release_result, policy_decision, final_action, risk_level, risk_score,
  requires_human_approval, generated_at, first_seen_at, last_seen_at
)
VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
`,
		"20260101-000000",
		"demo-app",
		"slo-rollout",
		"dev",
		nil,
		nil,
		nil,
		nil,
		"PASS",
		"ALLOW",
		"NOOP",
		"low",
		0,
		0,
		"2026-01-01T00:00:00Z",
		"2026-01-01T00:00:00Z",
		"2026-01-01T00:00:00Z",
	)
	if err != nil {
		t.Fatalf("insert release: %v", err)
	}

	insertObject := func(
		objectPK string,
		objectType string,
		objectID string,
		schemaVersion string,
		summaryJSON string,
		rawJSON string,
	) {
		t.Helper()

		_, err = db.Exec(
			`
INSERT INTO evidence_objects (
  object_pk, object_type, object_id, release_id, schema_version,
  source_path, source_mtime, content_sha256, generated_at,
  imported_at, summary_json, raw_json
)
VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
`,
			objectPK,
			objectType,
			objectID,
			"20260101-000000",
			schemaVersion,
			"/tmp/"+objectID+".json",
			"2026-01-01T00:00:00Z",
			"sha256-"+objectID,
			"2026-01-01T00:00:00Z",
			"2026-01-01T00:00:00Z",
			summaryJSON,
			rawJSON,
		)
		if err != nil {
			t.Fatalf("insert evidence object %s: %v", objectID, err)
		}
	}

	insertObject(
		"releaseEvidence:20260101-000000:re-20260101-000000",
		"releaseEvidence",
		"re-20260101-000000",
		"release.evidence.bundle/v1alpha1",
		`{"releaseResult":"PASS","riskLevel":"low","service":"demo-app"}`,
		`{"schemaVersion":"release.evidence.bundle/v1alpha1","releaseResult":"PASS","service":"demo-app"}`,
	)

	insertObject(
		"signedReleaseGate:20260101-000000:srg-20260101-000000",
		"signedReleaseGate",
		"srg-20260101-000000",
		"signed.release.gate/v1alpha1",
		`{"objectType":"signedReleaseGate","verificationMode":"input_derived","verificationToolAvailable":false,"signatureVerified":false,"sbomPresent":true,"provenancePresent":true,"canRunExternalVerification":false,"doesNotRunExternalCommands":true,"verification":{"mode":"input_derived","tool":"cosign","toolAvailable":false,"signatureVerified":false,"sbomPresent":true,"provenancePresent":true,"canRunExternalVerification":false,"doesNotRunExternalCommands":true}}`,
		`{"schemaVersion":"signed.release.gate/v1alpha1","signedReleaseGateId":"srg-20260101-000000"}`,
	)

	_, err = db.Exec(
		`
INSERT INTO release_artifacts (
  release_id, artifact_kind, path, exists_flag, content_type, size_bytes, modified_at, source_object_pk
)
VALUES (?, ?, ?, ?, ?, ?, ?, ?)
`,
		"20260101-000000",
		"releaseEvidence",
		"/tmp/release-evidence-20260101-000000.json",
		1,
		"application/json",
		128,
		"2026-01-01T00:00:00Z",
		"releaseEvidence:20260101-000000:re-20260101-000000",
	)
	if err != nil {
		t.Fatalf("insert release artifact: %v", err)
	}

	return dbFile
}
