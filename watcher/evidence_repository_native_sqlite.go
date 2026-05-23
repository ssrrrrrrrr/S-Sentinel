package main

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"time"

	_ "github.com/mattn/go-sqlite3"
)

type NativeSQLiteEvidenceRepository struct {
	runtime EvidenceRuntime
}

func NewNativeSQLiteEvidenceRepository(runtime EvidenceRuntime) *NativeSQLiteEvidenceRepository {
	return &NativeSQLiteEvidenceRepository{
		runtime: runtime,
	}
}

func (repo *NativeSQLiteEvidenceRepository) Descriptor() EvidenceRepositoryDescriptor {
	runtimeDescriptor := repo.runtime.Descriptor()

	return EvidenceRepositoryDescriptor{
		RepositoryID:                "native-sqlite-evidence-repository",
		RepositoryType:              "native-sqlite",
		Mode:                        "native-sqlite-repository",
		RuntimeMode:                 runtimeDescriptor.Mode,
		Backend:                     "sqlite",
		Adapter:                     "go-sqlite3",
		Storage:                     runtimeDescriptor.Storage,
		QueryModel:                  "native-sql-readonly",
		ContractVersion:             "evidence.repository/v1alpha1",
		ReadOnly:                    true,
		WillExecute:                 false,
		SupportsListReleases:        true,
		SupportsGetRelease:          false,
		SupportsGetObject:           true,
		SupportsListArtifacts:       false,
		SupportsSearch:              false,
		SupportsVerificationSummary: false,
		SupportsGraph:               false,
		SupportsNativeSQLite:        true,
		SupportsRemoteAPI:           false,
		Description:                 "Native SQLite repository backed by Go database/sql and github.com/mattn/go-sqlite3. Currently implements ListReleases and GetObject.",
	}
}

func (repo *NativeSQLiteEvidenceRepository) ListReleases(r *http.Request, query EvidenceReleaseListQuery) (*EvidenceRepositoryResponse, error) {
	dbFile, db, err := repo.openReadOnlyDB()
	if err != nil {
		return nil, err
	}
	defer db.Close()

	limit := parseEvidenceLimit(query.Limit, 50)

	where := []string{"1 = 1"}
	args := []interface{}{}

	if service := strings.TrimSpace(query.Service); service != "" {
		where = append(where, "r.service = ?")
		args = append(args, service)
	}
	if env := strings.TrimSpace(query.Env); env != "" {
		where = append(where, "r.env = ?")
		args = append(args, env)
	}
	if releaseResult := strings.TrimSpace(query.ReleaseResult); releaseResult != "" {
		where = append(where, "r.release_result = ?")
		args = append(args, releaseResult)
	}

	args = append(args, limit)

	rows, err := db.QueryContext(
		r.Context(),
		fmt.Sprintf(`
SELECT
  r.release_id,
  r.service,
  r.namespace,
  r.env,
  r.version,
  r.commit_sha,
  r.image,
  r.image_digest,
  r.release_result,
  r.policy_decision,
  r.final_action,
  r.risk_level,
  r.risk_score,
  r.requires_human_approval,
  r.generated_at,
  r.first_seen_at,
  r.last_seen_at,
  COUNT(o.object_pk) AS object_count,
  MAX(o.imported_at) AS latest_object_imported_at
FROM releases r
LEFT JOIN evidence_objects o ON o.release_id = r.release_id
WHERE %s
GROUP BY r.release_id
ORDER BY COALESCE(r.generated_at, r.last_seen_at, r.first_seen_at) DESC
LIMIT ?
`, strings.Join(where, " AND ")),
		args...,
	)
	if err != nil {
		return nil, repo.queryError("list releases", err)
	}
	defer rows.Close()

	items := []map[string]interface{}{}

	for rows.Next() {
		row := nativeReleaseRow{}
		if err := rows.Scan(
			&row.ReleaseID,
			&row.Service,
			&row.Namespace,
			&row.Env,
			&row.Version,
			&row.CommitSHA,
			&row.Image,
			&row.ImageDigest,
			&row.ReleaseResult,
			&row.PolicyDecision,
			&row.FinalAction,
			&row.RiskLevel,
			&row.RiskScore,
			&row.RequiresHumanApproval,
			&row.GeneratedAt,
			&row.FirstSeenAt,
			&row.LastSeenAt,
			&row.ObjectCount,
			&row.LatestObjectImportedAt,
		); err != nil {
			return nil, repo.queryError("scan releases", err)
		}

		objects, objectTypes, err := repo.releaseObjects(r, db, row.ReleaseID)
		if err != nil {
			return nil, err
		}

		item := row.toMap()
		item["object_count"] = row.ObjectCount
		item["latest_object_imported_at"] = sqlNullableString(row.LatestObjectImportedAt)
		item["object_types"] = objectTypes
		item["objects"] = objects

		items = append(items, item)
	}

	if err := rows.Err(); err != nil {
		return nil, repo.queryError("iterate releases", err)
	}

	body := map[string]interface{}{
		"schemaVersion": "evidence.store.releaseList/v1alpha1",
		"generatedAt":   time.Now().Format(time.RFC3339),
		"count":         len(items),
		"limit":         limit,
		"filters": map[string]interface{}{
			"service":       emptyStringAsNil(query.Service),
			"env":           emptyStringAsNil(query.Env),
			"releaseResult": emptyStringAsNil(query.ReleaseResult),
		},
		"items": items,
		"db":    dbFile,
	}

	return repo.response(body, dbFile)
}

func (repo *NativeSQLiteEvidenceRepository) GetRelease(r *http.Request, query EvidenceReleaseQuery) (*EvidenceRepositoryResponse, error) {
	return nil, repo.unsupported("get release")
}

func (repo *NativeSQLiteEvidenceRepository) GetObject(r *http.Request, query EvidenceObjectQuery) (*EvidenceRepositoryResponse, error) {
	dbFile, db, err := repo.openReadOnlyDB()
	if err != nil {
		return nil, err
	}
	defer db.Close()

	where := []string{"o.object_type = ?", "o.object_id = ?"}
	args := []interface{}{
		strings.TrimSpace(query.ObjectType),
		strings.TrimSpace(query.ObjectID),
	}

	if releaseID := strings.TrimSpace(query.ReleaseID); releaseID != "" {
		where = append(where, "o.release_id = ?")
		args = append(args, releaseID)
	}

	row := nativeObjectRow{}
	err = db.QueryRowContext(
		r.Context(),
		fmt.Sprintf(`
SELECT
  r.release_id,
  r.service,
  r.namespace,
  r.env,
  r.version,
  r.commit_sha,
  r.image,
  r.image_digest,
  r.release_result,
  r.policy_decision,
  r.final_action,
  r.risk_level,
  r.risk_score,
  r.requires_human_approval,
  r.generated_at,
  r.first_seen_at,
  r.last_seen_at,
  o.object_type,
  o.object_id,
  o.release_id,
  o.schema_version,
  o.source_path,
  o.source_mtime,
  o.content_sha256,
  o.generated_at,
  o.imported_at,
  o.summary_json,
  o.raw_json
FROM evidence_objects o
JOIN releases r ON r.release_id = o.release_id
WHERE %s
ORDER BY o.imported_at DESC
LIMIT 1
`, strings.Join(where, " AND ")),
		args...,
	).Scan(
		&row.Release.ReleaseID,
		&row.Release.Service,
		&row.Release.Namespace,
		&row.Release.Env,
		&row.Release.Version,
		&row.Release.CommitSHA,
		&row.Release.Image,
		&row.Release.ImageDigest,
		&row.Release.ReleaseResult,
		&row.Release.PolicyDecision,
		&row.Release.FinalAction,
		&row.Release.RiskLevel,
		&row.Release.RiskScore,
		&row.Release.RequiresHumanApproval,
		&row.Release.GeneratedAt,
		&row.Release.FirstSeenAt,
		&row.Release.LastSeenAt,
		&row.ObjectType,
		&row.ObjectID,
		&row.ObjectReleaseID,
		&row.SchemaVersion,
		&row.SourcePath,
		&row.SourceMTime,
		&row.ContentSHA256,
		&row.GeneratedAt,
		&row.ImportedAt,
		&row.SummaryJSON,
		&row.RawJSON,
	)

	if err != nil {
		if err == sql.ErrNoRows {
			return nil, &EvidenceRepositoryError{
				StatusCode: http.StatusNotFound,
				Message:    "evidence object not found",
				Err:        err,
			}
		}
		return nil, repo.queryError("get object", err)
	}

	object := map[string]interface{}{
		"object_type":    row.ObjectType,
		"object_id":      row.ObjectID,
		"release_id":     row.ObjectReleaseID,
		"schema_version": sqlNullableString(row.SchemaVersion),
		"source_path":    row.SourcePath,
		"source_mtime":   sqlNullableString(row.SourceMTime),
		"content_sha256": row.ContentSHA256,
		"generated_at":   sqlNullableString(row.GeneratedAt),
		"imported_at":    row.ImportedAt,
		"summary":        decodeSQLiteJSONMap(row.SummaryJSON),
	}

	if query.IncludeRaw {
		object["raw"] = decodeSQLiteJSONMap(row.RawJSON)
	}

	body := map[string]interface{}{
		"schemaVersion": "evidence.store.object/v1alpha1",
		"generatedAt":   time.Now().Format(time.RFC3339),
		"release":       row.Release.toMap(),
		"object":        object,
		"db":            dbFile,
	}

	return repo.response(body, dbFile)
}

func (repo *NativeSQLiteEvidenceRepository) ListArtifacts(r *http.Request, query EvidenceArtifactListQuery) (*EvidenceRepositoryResponse, error) {
	return nil, repo.unsupported("list artifacts")
}

func (repo *NativeSQLiteEvidenceRepository) SearchObjects(r *http.Request, query EvidenceSearchQuery) (*EvidenceRepositoryResponse, error) {
	return nil, repo.unsupported("search objects")
}

func (repo *NativeSQLiteEvidenceRepository) GetVerificationSummary(r *http.Request, query EvidenceVerificationSummaryQuery) (*EvidenceRepositoryResponse, error) {
	return nil, repo.unsupported("get verification summary")
}

func (repo *NativeSQLiteEvidenceRepository) GetGraph(r *http.Request, query EvidenceGraphQuery) (*EvidenceRepositoryResponse, error) {
	return nil, repo.unsupported("get graph")
}

func (repo *NativeSQLiteEvidenceRepository) openReadOnlyDB() (string, *sql.DB, error) {
	dbFile, err := repo.runtime.EnsureDBReady()
	if err != nil {
		return "", nil, &EvidenceRepositoryError{
			StatusCode: http.StatusConflict,
			Message:    "evidence store db is not ready",
			Err:        err,
		}
	}

	db, err := sql.Open("sqlite3", "file:"+dbFile+"?mode=ro&cache=shared")
	if err != nil {
		return "", nil, repo.queryError("open sqlite database", err)
	}

	return dbFile, db, nil
}

func (repo *NativeSQLiteEvidenceRepository) releaseObjects(
	r *http.Request,
	db *sql.DB,
	releaseID string,
) ([]map[string]interface{}, []string, error) {
	rows, err := db.QueryContext(
		r.Context(),
		`
SELECT object_type, object_id
FROM evidence_objects
WHERE release_id = ?
ORDER BY imported_at ASC, object_type ASC, object_id ASC
`,
		releaseID,
	)
	if err != nil {
		return nil, nil, repo.queryError("list release objects", err)
	}
	defer rows.Close()

	objects := []map[string]interface{}{}
	objectTypes := []string{}
	seenTypes := map[string]bool{}

	for rows.Next() {
		var objectType string
		var objectID string

		if err := rows.Scan(&objectType, &objectID); err != nil {
			return nil, nil, repo.queryError("scan release objects", err)
		}

		objects = append(objects, map[string]interface{}{
			"objectType": objectType,
			"objectId":   objectID,
		})

		if !seenTypes[objectType] {
			seenTypes[objectType] = true
			objectTypes = append(objectTypes, objectType)
		}
	}

	if err := rows.Err(); err != nil {
		return nil, nil, repo.queryError("iterate release objects", err)
	}

	return objects, objectTypes, nil
}

func (repo *NativeSQLiteEvidenceRepository) response(body map[string]interface{}, dbFile string) (*EvidenceRepositoryResponse, error) {
	data, err := json.MarshalIndent(body, "", "  ")
	if err != nil {
		return nil, repo.queryError("encode native sqlite response", err)
	}

	runtimeDescriptor := repo.runtime.Descriptor()
	repositoryDescriptor := repo.Descriptor()

	return &EvidenceRepositoryResponse{
		Body:       data,
		DBFile:     dbFile,
		Mode:       runtimeDescriptor.Mode,
		Runtime:    runtimeDescriptor,
		Repository: repositoryDescriptor,
	}, nil
}

func (repo *NativeSQLiteEvidenceRepository) queryError(operation string, err error) *EvidenceRepositoryError {
	return &EvidenceRepositoryError{
		StatusCode: http.StatusInternalServerError,
		Message:    "native sqlite evidence repository query failed",
		Err:        fmt.Errorf("%s: %w", operation, err),
	}
}

func (repo *NativeSQLiteEvidenceRepository) unsupported(operation string) error {
	return &EvidenceRepositoryError{
		StatusCode: http.StatusNotImplemented,
		Message:    "native sqlite evidence repository operation is not implemented",
		Err: fmt.Errorf(
			"%s is not implemented in native sqlite repository yet; current safe fallback remains cli-backed repository",
			operation,
		),
	}
}

type nativeReleaseRow struct {
	ReleaseID             string
	Service               sql.NullString
	Namespace             sql.NullString
	Env                   sql.NullString
	Version               sql.NullString
	CommitSHA             sql.NullString
	Image                 sql.NullString
	ImageDigest           sql.NullString
	ReleaseResult         sql.NullString
	PolicyDecision        sql.NullString
	FinalAction           sql.NullString
	RiskLevel             sql.NullString
	RiskScore             sql.NullFloat64
	RequiresHumanApproval sql.NullInt64
	GeneratedAt           sql.NullString
	FirstSeenAt           string
	LastSeenAt            string

	ObjectCount            int
	LatestObjectImportedAt sql.NullString
}

func (row nativeReleaseRow) toMap() map[string]interface{} {
	return map[string]interface{}{
		"release_id":              row.ReleaseID,
		"service":                 sqlNullableString(row.Service),
		"namespace":               sqlNullableString(row.Namespace),
		"env":                     sqlNullableString(row.Env),
		"version":                 sqlNullableString(row.Version),
		"commit_sha":              sqlNullableString(row.CommitSHA),
		"image":                   sqlNullableString(row.Image),
		"image_digest":            sqlNullableString(row.ImageDigest),
		"release_result":          sqlNullableString(row.ReleaseResult),
		"policy_decision":         sqlNullableString(row.PolicyDecision),
		"final_action":            sqlNullableString(row.FinalAction),
		"risk_level":              sqlNullableString(row.RiskLevel),
		"risk_score":              sqlNullableFloat(row.RiskScore),
		"requires_human_approval": sqlNullableBool(row.RequiresHumanApproval),
		"generated_at":            sqlNullableString(row.GeneratedAt),
		"first_seen_at":           row.FirstSeenAt,
		"last_seen_at":            row.LastSeenAt,
	}
}

type nativeObjectRow struct {
	Release nativeReleaseRow

	ObjectType      string
	ObjectID        string
	ObjectReleaseID string
	SchemaVersion   sql.NullString
	SourcePath      string
	SourceMTime     sql.NullString
	ContentSHA256   string
	GeneratedAt     sql.NullString
	ImportedAt      string
	SummaryJSON     string
	RawJSON         string
}

func parseEvidenceLimit(raw string, defaultValue int) int {
	limit, err := strconv.Atoi(strings.TrimSpace(raw))
	if err != nil || limit <= 0 {
		return defaultValue
	}
	if limit > 500 {
		return 500
	}
	return limit
}

func sqlNullableString(value sql.NullString) interface{} {
	if value.Valid {
		return value.String
	}
	return nil
}

func sqlNullableFloat(value sql.NullFloat64) interface{} {
	if value.Valid {
		return value.Float64
	}
	return nil
}

func sqlNullableBool(value sql.NullInt64) interface{} {
	if value.Valid {
		return value.Int64 != 0
	}
	return nil
}

func emptyStringAsNil(value string) interface{} {
	trimmed := strings.TrimSpace(value)
	if trimmed == "" {
		return nil
	}
	return trimmed
}

func decodeSQLiteJSONMap(raw string) map[string]interface{} {
	body := map[string]interface{}{}
	if err := json.Unmarshal([]byte(raw), &body); err != nil {
		return map[string]interface{}{
			"decodeError": err.Error(),
		}
	}
	return body
}
