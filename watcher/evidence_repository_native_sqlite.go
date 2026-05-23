package main

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"time"

	_ "modernc.org/sqlite"
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
		Adapter:                     "modernc-sqlite",
		Storage:                     runtimeDescriptor.Storage,
		QueryModel:                  "native-sql-readonly",
		ContractVersion:             "evidence.repository/v1alpha1",
		ReadOnly:                    true,
		WillExecute:                 false,
		SupportsListReleases:        true,
		SupportsGetRelease:          true,
		SupportsGetObject:           true,
		SupportsListArtifacts:       true,
		SupportsSearch:              true,
		SupportsVerificationSummary: true,
		SupportsGraph:               true,
		SupportsNativeSQLite:        true,
		SupportsRemoteAPI:           false,
		Description:                 "Native SQLite repository backed by Go database/sql and modernc.org/sqlite.",
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

		objects, objectTypes, err := repo.releaseObjectRefs(r, db, row.ReleaseID)
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
	dbFile, db, err := repo.openReadOnlyDB()
	if err != nil {
		return nil, err
	}
	defer db.Close()

	releaseID := strings.TrimSpace(query.ReleaseID)
	if releaseID == "" {
		return nil, repo.badRequest("releaseId is required")
	}

	release, err := repo.releaseByID(r, db, releaseID)
	if err != nil {
		return nil, err
	}

	objects, err := repo.objectsForRelease(r, db, releaseID, query.IncludeRaw)
	if err != nil {
		return nil, err
	}

	artifacts, err := repo.artifactsForRelease(r, db, releaseID, "", 500)
	if err != nil {
		return nil, err
	}

	body := map[string]interface{}{
		"schemaVersion": "evidence.store.release/v1alpha1",
		"generatedAt":   time.Now().Format(time.RFC3339),
		"release":       release.toMap(),
		"objectCount":   len(objects),
		"objects":       objects,
		"artifactCount": len(artifacts),
		"artifacts":     artifacts,
		"db":            dbFile,
	}

	return repo.response(body, dbFile)
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
	dbFile, db, err := repo.openReadOnlyDB()
	if err != nil {
		return nil, err
	}
	defer db.Close()

	limit := parseEvidenceLimit(query.Limit, 50)
	items, err := repo.artifactsForRelease(r, db, query.ReleaseID, query.ArtifactKind, limit)
	if err != nil {
		return nil, err
	}

	body := map[string]interface{}{
		"schemaVersion": "evidence.store.artifactList/v1alpha1",
		"generatedAt":   time.Now().Format(time.RFC3339),
		"count":         len(items),
		"limit":         limit,
		"filters": map[string]interface{}{
			"releaseId":    emptyStringAsNil(query.ReleaseID),
			"artifactKind": emptyStringAsNil(query.ArtifactKind),
		},
		"items": items,
		"db":    dbFile,
	}

	return repo.response(body, dbFile)
}

func (repo *NativeSQLiteEvidenceRepository) SearchObjects(r *http.Request, query EvidenceSearchQuery) (*EvidenceRepositoryResponse, error) {
	dbFile, db, err := repo.openReadOnlyDB()
	if err != nil {
		return nil, err
	}
	defer db.Close()

	limit := parseEvidenceLimit(query.Limit, 50)
	searchText := strings.TrimSpace(query.Query)

	where := []string{"1 = 1"}
	args := []interface{}{}

	if searchText != "" {
		like := "%" + strings.ToLower(searchText) + "%"
		where = append(where, `(
LOWER(o.object_type) LIKE ?
OR LOWER(o.object_id) LIKE ?
OR LOWER(o.release_id) LIKE ?
OR LOWER(o.schema_version) LIKE ?
OR LOWER(o.source_path) LIKE ?
OR LOWER(o.summary_json) LIKE ?
OR LOWER(o.raw_json) LIKE ?
OR LOWER(COALESCE(r.service, '')) LIKE ?
OR LOWER(COALESCE(r.namespace, '')) LIKE ?
OR LOWER(COALESCE(r.env, '')) LIKE ?
)`)
		for i := 0; i < 10; i++ {
			args = append(args, like)
		}
	}

	if objectType := strings.TrimSpace(query.ObjectType); objectType != "" {
		where = append(where, "o.object_type = ?")
		args = append(args, objectType)
	}

	if releaseID := strings.TrimSpace(query.ReleaseID); releaseID != "" {
		where = append(where, "o.release_id = ?")
		args = append(args, releaseID)
	}

	args = append(args, limit)

	rows, err := db.QueryContext(
		r.Context(),
		fmt.Sprintf(`
SELECT
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
ORDER BY o.imported_at DESC, o.object_type ASC, o.object_id ASC
LIMIT ?
`, strings.Join(where, " AND ")),
		args...,
	)
	if err != nil {
		return nil, repo.queryError("search objects", err)
	}
	defer rows.Close()

	items := []map[string]interface{}{}

	for rows.Next() {
		object, err := scanNativeEvidenceObject(rows, query.IncludeRaw)
		if err != nil {
			return nil, repo.queryError("scan search object", err)
		}
		items = append(items, object)
	}

	if err := rows.Err(); err != nil {
		return nil, repo.queryError("iterate search objects", err)
	}

	body := map[string]interface{}{
		"schemaVersion": "evidence.store.search/v1alpha1",
		"generatedAt":   time.Now().Format(time.RFC3339),
		"count":         len(items),
		"limit":         limit,
		"filters": map[string]interface{}{
			"query":      searchText,
			"objectType": emptyStringAsNil(query.ObjectType),
			"releaseId":  emptyStringAsNil(query.ReleaseID),
			"includeRaw": query.IncludeRaw,
		},
		"items": items,
		"db":    dbFile,
	}

	return repo.response(body, dbFile)
}

func (repo *NativeSQLiteEvidenceRepository) GetVerificationSummary(r *http.Request, query EvidenceVerificationSummaryQuery) (*EvidenceRepositoryResponse, error) {
	dbFile, db, err := repo.openReadOnlyDB()
	if err != nil {
		return nil, err
	}
	defer db.Close()

	limit := parseEvidenceLimit(query.Limit, 50)
	body, err := repo.verificationSummaryBody(r, db, query.ReleaseID, limit)
	if err != nil {
		return nil, err
	}
	body["db"] = dbFile

	return repo.response(body, dbFile)
}

func (repo *NativeSQLiteEvidenceRepository) GetGraph(r *http.Request, query EvidenceGraphQuery) (*EvidenceRepositoryResponse, error) {
	dbFile, db, err := repo.openReadOnlyDB()
	if err != nil {
		return nil, err
	}
	defer db.Close()

	releaseID := strings.TrimSpace(query.ReleaseID)
	if releaseID == "" {
		return nil, repo.badRequest("releaseId is required")
	}

	release, err := repo.releaseByID(r, db, releaseID)
	if err != nil {
		return nil, err
	}

	objects, err := repo.objectsForRelease(r, db, releaseID, false)
	if err != nil {
		return nil, err
	}

	artifacts, err := repo.artifactsForRelease(r, db, releaseID, "", 500)
	if err != nil {
		return nil, err
	}

	verificationSummary, err := repo.verificationSummaryBody(r, db, releaseID, 50)
	if err != nil {
		return nil, err
	}

	nodes := []map[string]interface{}{
		{
			"id":        "release:" + releaseID,
			"type":      "release",
			"label":     releaseID,
			"releaseId": releaseID,
			"data":      release.toMap(),
		},
	}
	edges := []map[string]interface{}{}

	for _, object := range objects {
		objectType, _ := object["object_type"].(string)
		objectID, _ := object["object_id"].(string)
		nodeID := "object:" + objectType + ":" + objectID

		nodes = append(nodes, map[string]interface{}{
			"id":            nodeID,
			"type":          "evidenceObject",
			"label":         objectType,
			"releaseId":     releaseID,
			"objectType":    objectType,
			"objectId":      objectID,
			"schemaVersion": object["schema_version"],
			"data":          object,
		})

		edges = append(edges, map[string]interface{}{
			"from": "release:" + releaseID,
			"to":   nodeID,
			"type": "containsEvidenceObject",
		})
	}

	for _, artifact := range artifacts {
		artifactKind, _ := artifact["artifact_kind"].(string)
		path, _ := artifact["path"].(string)
		nodeID := "artifact:" + artifactKind + ":" + path

		nodes = append(nodes, map[string]interface{}{
			"id":           nodeID,
			"type":         "artifact",
			"label":        artifactKind,
			"releaseId":    releaseID,
			"artifactKind": artifactKind,
			"path":         path,
			"data":         artifact,
		})

		edges = append(edges, map[string]interface{}{
			"from": "release:" + releaseID,
			"to":   nodeID,
			"type": "hasArtifact",
		})
	}

	if items, ok := verificationSummary["items"].([]map[string]interface{}); ok {
		for _, item := range items {
			objectType, _ := item["objectType"].(string)
			objectID, _ := item["objectId"].(string)
			mode := fmt.Sprint(item["verificationMode"])
			nodeID := "verification:" + releaseID + ":" + objectType + ":" + objectID

			nodes = append(nodes, map[string]interface{}{
				"id":         nodeID,
				"type":       "verificationSummary",
				"label":      mode,
				"releaseId":  releaseID,
				"objectType": objectType,
				"objectId":   objectID,
				"data":       item,
			})

			if objectType != "" && objectID != "" {
				edges = append(edges, map[string]interface{}{
					"from": "object:" + objectType + ":" + objectID,
					"to":   nodeID,
					"type": "hasVerificationSummary",
				})
			}

			edges = append(edges, map[string]interface{}{
				"from": "release:" + releaseID,
				"to":   nodeID,
				"type": "hasVerificationSummary",
			})
		}
	}

	body := map[string]interface{}{
		"schemaVersion":       "evidence.store.graph/v1alpha1",
		"generatedAt":         time.Now().Format(time.RFC3339),
		"releaseId":           releaseID,
		"release":             release.toMap(),
		"objectCount":         len(objects),
		"artifactCount":       len(artifacts),
		"verificationSummary": verificationSummary,
		"nodeCount":           len(nodes),
		"edgeCount":           len(edges),
		"nodes":               nodes,
		"edges":               edges,
		"db":                  dbFile,
	}

	return repo.response(body, dbFile)
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

	db, err := sql.Open("sqlite", "file:"+dbFile+"?mode=ro&cache=shared")
	if err != nil {
		return "", nil, repo.queryError("open sqlite database", err)
	}

	return dbFile, db, nil
}

func (repo *NativeSQLiteEvidenceRepository) releaseByID(r *http.Request, db *sql.DB, releaseID string) (nativeReleaseRow, error) {
	row := nativeReleaseRow{}
	err := db.QueryRowContext(
		r.Context(),
		`
SELECT
  release_id,
  service,
  namespace,
  env,
  version,
  commit_sha,
  image,
  image_digest,
  release_result,
  policy_decision,
  final_action,
  risk_level,
  risk_score,
  requires_human_approval,
  generated_at,
  first_seen_at,
  last_seen_at
FROM releases
WHERE release_id = ?
LIMIT 1
`,
		releaseID,
	).Scan(
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
	)

	if err != nil {
		if err == sql.ErrNoRows {
			return row, &EvidenceRepositoryError{
				StatusCode: http.StatusNotFound,
				Message:    "release not found",
				Err:        err,
			}
		}
		return row, repo.queryError("get release", err)
	}

	return row, nil
}

func (repo *NativeSQLiteEvidenceRepository) releaseObjectRefs(
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

func (repo *NativeSQLiteEvidenceRepository) objectsForRelease(
	r *http.Request,
	db *sql.DB,
	releaseID string,
	includeRaw bool,
) ([]map[string]interface{}, error) {
	rows, err := db.QueryContext(
		r.Context(),
		`
SELECT
  object_type,
  object_id,
  release_id,
  schema_version,
  source_path,
  source_mtime,
  content_sha256,
  generated_at,
  imported_at,
  summary_json,
  raw_json
FROM evidence_objects
WHERE release_id = ?
ORDER BY imported_at ASC, object_type ASC, object_id ASC
`,
		releaseID,
	)
	if err != nil {
		return nil, repo.queryError("list release object details", err)
	}
	defer rows.Close()

	objects := []map[string]interface{}{}

	for rows.Next() {
		object, err := scanNativeEvidenceObject(rows, includeRaw)
		if err != nil {
			return nil, repo.queryError("scan release object detail", err)
		}
		objects = append(objects, object)
	}

	if err := rows.Err(); err != nil {
		return nil, repo.queryError("iterate release object details", err)
	}

	return objects, nil
}

func (repo *NativeSQLiteEvidenceRepository) artifactsForRelease(
	r *http.Request,
	db *sql.DB,
	releaseID string,
	artifactKind string,
	limit int,
) ([]map[string]interface{}, error) {
	where := []string{"1 = 1"}
	args := []interface{}{}

	if releaseID = strings.TrimSpace(releaseID); releaseID != "" {
		where = append(where, "release_id = ?")
		args = append(args, releaseID)
	}

	if artifactKind = strings.TrimSpace(artifactKind); artifactKind != "" {
		where = append(where, "artifact_kind = ?")
		args = append(args, artifactKind)
	}

	args = append(args, limit)

	rows, err := db.QueryContext(
		r.Context(),
		fmt.Sprintf(`
SELECT
  release_id,
  artifact_kind,
  path,
  exists_flag,
  content_type,
  size_bytes,
  modified_at,
  source_object_pk
FROM release_artifacts
WHERE %s
ORDER BY release_id DESC, artifact_kind ASC, path ASC
LIMIT ?
`, strings.Join(where, " AND ")),
		args...,
	)
	if err != nil {
		return nil, repo.queryError("list artifacts", err)
	}
	defer rows.Close()

	items := []map[string]interface{}{}

	for rows.Next() {
		var releaseID string
		var kind string
		var path string
		var existsFlag sql.NullInt64
		var contentType sql.NullString
		var sizeBytes sql.NullInt64
		var modifiedAt sql.NullString
		var sourceObjectPK sql.NullString

		if err := rows.Scan(
			&releaseID,
			&kind,
			&path,
			&existsFlag,
			&contentType,
			&sizeBytes,
			&modifiedAt,
			&sourceObjectPK,
		); err != nil {
			return nil, repo.queryError("scan artifacts", err)
		}

		items = append(items, map[string]interface{}{
			"release_id":       releaseID,
			"artifact_kind":    kind,
			"path":             path,
			"exists_flag":      sqlNullableBool(existsFlag),
			"content_type":     sqlNullableString(contentType),
			"size_bytes":       sqlNullableInt(sizeBytes),
			"modified_at":      sqlNullableString(modifiedAt),
			"source_object_pk": sqlNullableString(sourceObjectPK),
		})
	}

	if err := rows.Err(); err != nil {
		return nil, repo.queryError("iterate artifacts", err)
	}

	return items, nil
}

func (repo *NativeSQLiteEvidenceRepository) verificationSummaryBody(
	r *http.Request,
	db *sql.DB,
	releaseID string,
	limit int,
) (map[string]interface{}, error) {
	where := []string{"object_type = ?"}
	args := []interface{}{"signedReleaseGate"}

	if releaseID = strings.TrimSpace(releaseID); releaseID != "" {
		where = append(where, "release_id = ?")
		args = append(args, releaseID)
	}

	args = append(args, limit)

	rows, err := db.QueryContext(
		r.Context(),
		fmt.Sprintf(`
SELECT
  object_type,
  object_id,
  release_id,
  imported_at,
  summary_json
FROM evidence_objects
WHERE %s
ORDER BY imported_at DESC
LIMIT ?
`, strings.Join(where, " AND ")),
		args...,
	)
	if err != nil {
		return nil, repo.queryError("verification summary", err)
	}
	defer rows.Close()

	items := []map[string]interface{}{}

	for rows.Next() {
		var objectType string
		var objectID string
		var objectReleaseID string
		var importedAt string
		var summaryJSON string

		if err := rows.Scan(&objectType, &objectID, &objectReleaseID, &importedAt, &summaryJSON); err != nil {
			return nil, repo.queryError("scan verification summary", err)
		}

		summary := decodeSQLiteJSONMap(summaryJSON)
		verification := mapValue(summary, "verification")

		item := map[string]interface{}{
			"releaseId":                         objectReleaseID,
			"objectType":                        objectType,
			"objectId":                          objectID,
			"importedAt":                        importedAt,
			"verification":                      verification,
			"verificationMode":                  firstNonNil(summary["verificationMode"], verification["mode"]),
			"verificationTool":                  firstNonNil(summary["verificationTool"], verification["tool"]),
			"verificationToolAvailable":         firstNonNil(summary["verificationToolAvailable"], verification["toolAvailable"]),
			"signatureVerified":                 firstNonNil(summary["signatureVerified"], verification["signatureVerified"]),
			"sbomPresent":                       firstNonNil(summary["sbomPresent"], verification["sbomPresent"]),
			"provenancePresent":                 firstNonNil(summary["provenancePresent"], verification["provenancePresent"]),
			"externalVerificationRequested":     summary["externalVerificationRequested"],
			"externalVerificationAllowed":       summary["externalVerificationAllowed"],
			"externalVerificationExecuted":      summary["externalVerificationExecuted"],
			"externalVerificationSucceeded":     summary["externalVerificationSucceeded"],
			"externalVerificationSkippedReason": summary["externalVerificationSkippedReason"],
			"canRunExternalVerification":        firstNonNil(summary["canRunExternalVerification"], verification["canRunExternalVerification"]),
			"doesNotRunExternalCommands":        firstNonNil(summary["doesNotRunExternalCommands"], verification["doesNotRunExternalCommands"]),
		}

		items = append(items, item)
	}

	if err := rows.Err(); err != nil {
		return nil, repo.queryError("iterate verification summary", err)
	}

	var latest interface{}
	if len(items) > 0 {
		latest = items[0]
	}

	return map[string]interface{}{
		"schemaVersion": "evidence.store.verificationSummary/v1alpha1",
		"generatedAt":   time.Now().Format(time.RFC3339),
		"count":         len(items),
		"limit":         limit,
		"filters": map[string]interface{}{
			"releaseId": emptyStringAsNil(releaseID),
		},
		"latest": latest,
		"items":  items,
	}, nil
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

func (repo *NativeSQLiteEvidenceRepository) badRequest(message string) *EvidenceRepositoryError {
	return &EvidenceRepositoryError{
		StatusCode: http.StatusBadRequest,
		Message:    message,
	}
}

func (repo *NativeSQLiteEvidenceRepository) queryError(operation string, err error) *EvidenceRepositoryError {
	return &EvidenceRepositoryError{
		StatusCode: http.StatusInternalServerError,
		Message:    "native sqlite evidence repository query failed",
		Err:        fmt.Errorf("%s: %w", operation, err),
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

type nativeEvidenceObjectRow struct {
	ObjectType    string
	ObjectID      string
	ReleaseID     string
	SchemaVersion sql.NullString
	SourcePath    string
	SourceMTime   sql.NullString
	ContentSHA256 string
	GeneratedAt   sql.NullString
	ImportedAt    string
	SummaryJSON   string
	RawJSON       string
}

func scanNativeEvidenceObject(rows *sql.Rows, includeRaw bool) (map[string]interface{}, error) {
	row := nativeEvidenceObjectRow{}

	if err := rows.Scan(
		&row.ObjectType,
		&row.ObjectID,
		&row.ReleaseID,
		&row.SchemaVersion,
		&row.SourcePath,
		&row.SourceMTime,
		&row.ContentSHA256,
		&row.GeneratedAt,
		&row.ImportedAt,
		&row.SummaryJSON,
		&row.RawJSON,
	); err != nil {
		return nil, err
	}

	object := map[string]interface{}{
		"object_type":    row.ObjectType,
		"object_id":      row.ObjectID,
		"release_id":     row.ReleaseID,
		"schema_version": sqlNullableString(row.SchemaVersion),
		"source_path":    row.SourcePath,
		"source_mtime":   sqlNullableString(row.SourceMTime),
		"content_sha256": row.ContentSHA256,
		"generated_at":   sqlNullableString(row.GeneratedAt),
		"imported_at":    row.ImportedAt,
		"summary":        decodeSQLiteJSONMap(row.SummaryJSON),
	}

	if includeRaw {
		object["raw"] = decodeSQLiteJSONMap(row.RawJSON)
	}

	return object, nil
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

func sqlNullableInt(value sql.NullInt64) interface{} {
	if value.Valid {
		return value.Int64
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

func mapValue(body map[string]interface{}, key string) map[string]interface{} {
	value, _ := body[key].(map[string]interface{})
	if value == nil {
		return map[string]interface{}{}
	}
	return value
}

func firstNonNil(values ...interface{}) interface{} {
	for _, value := range values {
		if value != nil {
			return value
		}
	}
	return nil
}
