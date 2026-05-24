package main

import (
	"database/sql"
	"encoding/json"
	"net/http"
	"strings"
	"testing"

	_ "modernc.org/sqlite"
)

func TestPortalEvidenceAPIPolicyRuntimeObjectsNativeSQLite(t *testing.T) {
	dbFile := createNativeSQLiteTestDB(t)
	insertStage44PolicyRuntimeObjects(t, dbFile)

	t.Setenv("S_SENTINEL_EVIDENCE_STORE_DB", dbFile)
	t.Setenv("S_SENTINEL_EVIDENCE_REPOSITORY_MODE", "native-sqlite")

	api := &portalAPI{
		cfg:       Config{RepoDir: t.TempDir()},
		reportDir: t.TempDir(),
	}

	releaseID := "20260101-000000"

	runtimeBody, _ := callPortalEvidenceStoreHandlerWithRecorder(
		t,
		api.handleEvidenceStoreObjectDetail,
		http.MethodGet,
		"/api/evidence/objects/policyRuntimeResult/prr-"+releaseID+"?releaseId="+releaseID+"&includeRaw=true",
		http.StatusOK,
	)

	assertPortalSchema(t, runtimeBody, "evidence.store.object/v1alpha1")
	requireEvidenceAPIControlPlaneContract(t, runtimeBody, "native-sqlite", "native-sqlite-repository", false)
	requireStage44ObjectSummaryString(t, runtimeBody, "policyRuntimeResult", "prr-"+releaseID, "policyDecision", "ALLOW")
	requireStage44ObjectSummaryString(t, runtimeBody, "policyRuntimeResult", "prr-"+releaseID, "finalAction", "NOOP")
	requireStage44ObjectSummaryString(t, runtimeBody, "policyRuntimeResult", "prr-"+releaseID, "runtimeStatus", "evaluated")
	requireStage44ObjectSummaryBool(t, runtimeBody, "allowed", true)
	requireStage44ObjectSummaryRule(t, runtimeBody, "opa_evidence_store_allowed")

	decisionBody, _ := callPortalEvidenceStoreHandlerWithRecorder(
		t,
		api.handleEvidenceStoreObjectDetail,
		http.MethodGet,
		"/api/evidence/objects/policyDecision/pd-"+releaseID+"?releaseId="+releaseID+"&includeRaw=true",
		http.StatusOK,
	)

	assertPortalSchema(t, decisionBody, "evidence.store.object/v1alpha1")
	requireEvidenceAPIControlPlaneContract(t, decisionBody, "native-sqlite", "native-sqlite-repository", false)
	requireStage44ObjectSummaryString(t, decisionBody, "policyDecision", "pd-"+releaseID, "policyDecision", "ALLOW")
	requireStage44ObjectSummaryString(t, decisionBody, "policyDecision", "pd-"+releaseID, "finalAction", "NOOP")
	requireStage44ObjectSummaryBool(t, decisionBody, "allowed", true)
	requireStage44ObjectSummaryRule(t, decisionBody, "opa_evidence_store_allowed")

	searchBody, _ := callPortalEvidenceStoreHandlerWithRecorder(
		t,
		api.handleEvidenceSearch,
		http.MethodGet,
		"/api/evidence/search?q=opa_evidence_store_allowed&objectType=policyDecision&releaseId="+releaseID+"&limit=10",
		http.StatusOK,
	)

	assertPortalSchema(t, searchBody, "evidence.store.search/v1alpha1")
	requireEvidenceAPIControlPlaneContract(t, searchBody, "native-sqlite", "native-sqlite-repository", false)
	assertPortalNumberAtLeast(t, searchBody, "count", 1)
	requireStage44ResponseContains(t, searchBody, "policyDecision")
	requireStage44ResponseContains(t, searchBody, "opa_evidence_store_allowed")

	graphBody, _ := callPortalEvidenceStoreHandlerWithRecorder(
		t,
		api.handleEvidenceGraph,
		http.MethodGet,
		"/api/evidence/graph?releaseId="+releaseID,
		http.StatusOK,
	)

	assertPortalSchema(t, graphBody, "evidence.store.graph/v1alpha1")
	requireEvidenceAPIControlPlaneContract(t, graphBody, "native-sqlite", "native-sqlite-repository", false)
	assertPortalNumberAtLeast(t, graphBody, "nodeCount", 4)
	assertPortalNumberAtLeast(t, graphBody, "edgeCount", 3)
	requireStage44ResponseContains(t, graphBody, "policyRuntimeResult")
	requireStage44ResponseContains(t, graphBody, "policyDecision")
}

func insertStage44PolicyRuntimeObjects(t *testing.T, dbFile string) {
	t.Helper()

	db, err := sql.Open("sqlite", dbFile)
	if err != nil {
		t.Fatalf("open sqlite test db: %v", err)
	}
	defer db.Close()

	releaseID := "20260101-000000"
	rule := []interface{}{"opa_evidence_store_allowed"}

	decisionSummary := map[string]interface{}{
		"objectType":              "policyDecision",
		"schemaVersion":           "release.policy.evaluator/v1alpha1",
		"policyDecision":          "ALLOW",
		"finalAction":             "NOOP",
		"allowed":                 true,
		"requiresHumanApproval":   false,
		"requestedAction":         "NOOP",
		"matchedRules":            rule,
		"deniedReasons":           []interface{}{},
		"approvalRequiredReasons": []interface{}{},
		"willExecute":             false,
	}

	decisionRaw := map[string]interface{}{
		"schemaVersion":         "release.policy.evaluator/v1alpha1",
		"policyDecisionId":      "pd-" + releaseID,
		"releaseId":             releaseID,
		"service":               "demo-app",
		"env":                   "dev",
		"policyDecision":        "ALLOW",
		"requestedAction":       "NOOP",
		"allowed":               true,
		"finalAction":           "NOOP",
		"executionMode":         "advisory_only",
		"requiresHumanApproval": false,
		"matchedRules":          rule,
		"reason":                "fake opa evidence store integration allowed PASS/NOOP release",
	}

	runtimeSummary := map[string]interface{}{
		"objectType":                     "policyRuntimeResult",
		"schemaVersion":                  "policy.runtime.result/v1alpha1",
		"policyDecision":                 "ALLOW",
		"finalAction":                    "NOOP",
		"allowed":                        true,
		"requiresHumanApproval":          false,
		"requestedAction":                "NOOP",
		"matchedRules":                   rule,
		"runtimeStatus":                  "evaluated",
		"runtimePreviewOnly":             false,
		"runtimeExternalCommandExecuted": true,
		"willExecute":                    false,
	}

	runtimeRaw := map[string]interface{}{
		"schemaVersion": "policy.runtime.result/v1alpha1",
		"runtime": map[string]interface{}{
			"name":                    "opa",
			"status":                  "evaluated",
			"mode":                    "external_command",
			"externalCommandExecuted": true,
		},
		"policyDecision": decisionRaw,
		"summary":        runtimeSummary,
	}

	insertStage44EvidenceObject(t, db, "policyRuntimeResult", "prr-"+releaseID, releaseID, "policy.runtime.result/v1alpha1", runtimeSummary, runtimeRaw)
	insertStage44EvidenceObject(t, db, "policyDecision", "pd-"+releaseID, releaseID, "release.policy.evaluator/v1alpha1", decisionSummary, decisionRaw)
}

func insertStage44EvidenceObject(
	t *testing.T,
	db *sql.DB,
	objectType string,
	objectID string,
	releaseID string,
	schemaVersion string,
	summary map[string]interface{},
	raw map[string]interface{},
) {
	t.Helper()

	summaryJSON, err := json.Marshal(summary)
	if err != nil {
		t.Fatalf("marshal summary: %v", err)
	}

	rawJSON, err := json.Marshal(raw)
	if err != nil {
		t.Fatalf("marshal raw: %v", err)
	}

	_, err = db.Exec(`
INSERT OR REPLACE INTO evidence_objects (
  object_pk, object_type, object_id, release_id, schema_version,
  source_path, source_mtime, content_sha256, generated_at, imported_at,
  summary_json, raw_json
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
`,
		objectType+":"+releaseID+":"+objectID,
		objectType,
		objectID,
		releaseID,
		schemaVersion,
		"/tmp/"+objectID+".json",
		"2026-01-01T00:00:04Z",
		"sha256-"+objectID,
		"2026-01-01T00:00:04Z",
		"2026-01-01T00:00:05Z",
		string(summaryJSON),
		string(rawJSON),
	)
	if err != nil {
		t.Fatalf("insert evidence object %s/%s: %v", objectType, objectID, err)
	}
}

func requireStage44ObjectSummaryString(
	t *testing.T,
	body map[string]interface{},
	expectedObjectType string,
	expectedObjectID string,
	key string,
	expected string,
) {
	t.Helper()

	summary := requireStage44ObjectSummary(t, body, expectedObjectType, expectedObjectID)
	got, ok := summary[key].(string)
	if !ok || got != expected {
		t.Fatalf("expected object.summary.%s=%s, got %#v", key, expected, summary[key])
	}
}

func requireStage44ObjectSummaryBool(t *testing.T, body map[string]interface{}, key string, expected bool) {
	t.Helper()

	summary := requireStage44ObjectSummary(t, body, "", "")
	got, ok := summary[key].(bool)
	if !ok || got != expected {
		t.Fatalf("expected object.summary.%s=%v, got %#v", key, expected, summary[key])
	}
}

func requireStage44ObjectSummaryRule(t *testing.T, body map[string]interface{}, expectedRule string) {
	t.Helper()

	summary := requireStage44ObjectSummary(t, body, "", "")
	rules, ok := summary["matchedRules"].([]interface{})
	if !ok {
		t.Fatalf("expected object.summary.matchedRules array, got %#v", summary["matchedRules"])
	}

	for _, item := range rules {
		if item == expectedRule {
			return
		}
	}

	t.Fatalf("expected matchedRules to contain %s, got %#v", expectedRule, rules)
}

func requireStage44ObjectSummary(
	t *testing.T,
	body map[string]interface{},
	expectedObjectType string,
	expectedObjectID string,
) map[string]interface{} {
	t.Helper()

	object := requireEvidenceAPIMap(t, body, "object")

	if expectedObjectType != "" && object["object_type"] != expectedObjectType {
		t.Fatalf("expected object_type=%s, got %#v", expectedObjectType, object["object_type"])
	}

	if expectedObjectID != "" && object["object_id"] != expectedObjectID {
		t.Fatalf("expected object_id=%s, got %#v", expectedObjectID, object["object_id"])
	}

	return requireEvidenceAPIMap(t, object, "summary")
}

func requireStage44ResponseContains(t *testing.T, body map[string]interface{}, expected string) {
	t.Helper()

	data, err := json.Marshal(body)
	if err != nil {
		t.Fatalf("marshal response: %v", err)
	}

	if !strings.Contains(string(data), expected) {
		t.Fatalf("expected response to contain %q, got %s", expected, string(data))
	}
}
