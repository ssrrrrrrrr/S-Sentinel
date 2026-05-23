package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"time"
)

const (
	expectedEvidenceStoreSchemaID            = "evidence.store.sqlite/v1alpha1"
	expectedEvidenceStoreSchemaVersion       = 1
	expectedEvidenceStoreSQLiteUserVersion   = 1
	evidenceStoreSchemaHealthSchemaVersion   = "evidence.store.schemaHealth/v1alpha1"
	evidenceStoreSchemaContractSchemaVersion = "evidence.store.schemaContract/v1alpha1"
)

func (svc *EvidenceService) schemaContract() map[string]interface{} {
	return map[string]interface{}{
		"schemaVersion":             evidenceStoreSchemaContractSchemaVersion,
		"storeSchemaVersion":        expectedEvidenceStoreSchemaID,
		"currentVersion":            expectedEvidenceStoreSchemaVersion,
		"sqliteUserVersion":         expectedEvidenceStoreSQLiteUserVersion,
		"migrationTable":            "evidence_schema_migrations",
		"migrationVersionSource":    "evidence_schema_migrations.version",
		"sqliteUserVersionSource":   "PRAGMA user_version",
		"compatibilityPolicy":       "exact-match",
		"onMismatch":                "reject-native-read-query",
		"readOnly":                  true,
		"willExecute":               false,
		"doesNotModifyCluster":      true,
		"doesNotModifyGitOps":       true,
		"doesNotTriggerRollout":     true,
		"mutatesLocalEvidenceIndex": false,
	}
}

func (svc *EvidenceService) schemaHealth(ctx context.Context) map[string]interface{} {
	health := map[string]interface{}{
		"schemaVersion":         evidenceStoreSchemaHealthSchemaVersion,
		"generatedAt":           time.Now().Format(time.RFC3339),
		"contract":              svc.schemaContract(),
		"ready":                 false,
		"compatible":            false,
		"checkedBy":             "s-sentinel-evidence-api",
		"checkMode":             "runtime-schema-command",
		"readOnly":              true,
		"willExecute":           false,
		"doesNotModifyCluster":  true,
		"doesNotModifyGitOps":   true,
		"doesNotTriggerRollout": true,
		"mutationSemantics": map[string]interface{}{
			"doesNotModifyCluster":      true,
			"doesNotModifyGitOps":       true,
			"doesNotTriggerRollout":     true,
			"mutatesLocalEvidenceIndex": false,
		},
	}

	raw, err := svc.runtime.Run(ctx, "schema")
	if err != nil {
		health["reason"] = "schema command failed"
		health["error"] = err.Error()
		return health
	}

	var schema map[string]interface{}
	if err := json.Unmarshal(raw, &schema); err != nil {
		health["reason"] = "schema command returned invalid json"
		health["error"] = err.Error()
		return health
	}

	storeSchemaVersion := strings.TrimSpace(fmt.Sprint(schema["storeSchemaVersion"]))
	currentVersion, currentOK := evidenceStoreInt(schema["currentVersion"])
	sqliteUserVersion, sqliteOK := evidenceStoreInt(schema["sqliteUserVersion"])

	issues := []string{}
	if storeSchemaVersion != expectedEvidenceStoreSchemaID {
		issues = append(issues, "storeSchemaVersion mismatch")
	}
	if !currentOK || currentVersion != expectedEvidenceStoreSchemaVersion {
		issues = append(issues, "currentVersion mismatch")
	}
	if !sqliteOK || sqliteUserVersion != expectedEvidenceStoreSQLiteUserVersion {
		issues = append(issues, "sqliteUserVersion mismatch")
	}

	compatible := len(issues) == 0

	health["storeSchemaVersion"] = storeSchemaVersion
	health["currentVersion"] = currentVersion
	health["sqliteUserVersion"] = sqliteUserVersion
	health["currentVersionReadable"] = currentOK
	health["sqliteUserVersionReadable"] = sqliteOK
	health["compatible"] = compatible
	health["ready"] = compatible
	health["issues"] = issues
	health["schema"] = schema

	return health
}

func evidenceStoreInt(value interface{}) (int, bool) {
	switch typed := value.(type) {
	case int:
		return typed, true
	case int64:
		return int(typed), true
	case float64:
		return int(typed), true
	case json.Number:
		parsed, err := typed.Int64()
		if err != nil {
			return 0, false
		}
		return int(parsed), true
	case string:
		parsed, err := strconv.Atoi(strings.TrimSpace(typed))
		if err != nil {
			return 0, false
		}
		return parsed, true
	default:
		return 0, false
	}
}

func (repo *NativeSQLiteEvidenceRepository) verifySchemaCompatible(db *sql.DB) error {
	var sqliteUserVersion int
	if err := db.QueryRow("PRAGMA user_version").Scan(&sqliteUserVersion); err != nil {
		return &EvidenceRepositoryError{
			StatusCode: http.StatusConflict,
			Message:    "failed to read EvidenceStore sqlite user_version",
			Err:        err,
		}
	}

	var migrationSchemaVersion string
	var migrationVersion int
	if err := db.QueryRow(`
SELECT schema_version, version
FROM evidence_schema_migrations
ORDER BY version DESC, migration_id DESC
LIMIT 1
`).Scan(&migrationSchemaVersion, &migrationVersion); err != nil {
		return &EvidenceRepositoryError{
			StatusCode: http.StatusConflict,
			Message:    "failed to read EvidenceStore schema migration state",
			Err:        err,
		}
	}

	if migrationSchemaVersion != expectedEvidenceStoreSchemaID ||
		migrationVersion != expectedEvidenceStoreSchemaVersion ||
		sqliteUserVersion != expectedEvidenceStoreSQLiteUserVersion {
		return &EvidenceRepositoryError{
			StatusCode: http.StatusConflict,
			Message: fmt.Sprintf(
				"incompatible EvidenceStore schema: expected storeSchemaVersion=%s currentVersion=%d sqliteUserVersion=%d, got storeSchemaVersion=%s currentVersion=%d sqliteUserVersion=%d",
				expectedEvidenceStoreSchemaID,
				expectedEvidenceStoreSchemaVersion,
				expectedEvidenceStoreSQLiteUserVersion,
				migrationSchemaVersion,
				migrationVersion,
				sqliteUserVersion,
			),
		}
	}

	return nil
}
