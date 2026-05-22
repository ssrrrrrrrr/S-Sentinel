package main

import (
	"net/http"
	"strings"
)

type EvidenceRepository interface {
	ListReleases(r *http.Request, query EvidenceReleaseListQuery) (*EvidenceRepositoryResponse, error)
	GetRelease(r *http.Request, query EvidenceReleaseQuery) (*EvidenceRepositoryResponse, error)
	GetObject(r *http.Request, query EvidenceObjectQuery) (*EvidenceRepositoryResponse, error)
	ListArtifacts(r *http.Request, query EvidenceArtifactListQuery) (*EvidenceRepositoryResponse, error)
	SearchObjects(r *http.Request, query EvidenceSearchQuery) (*EvidenceRepositoryResponse, error)
	GetVerificationSummary(r *http.Request, query EvidenceVerificationSummaryQuery) (*EvidenceRepositoryResponse, error)
}

type EvidenceReleaseListQuery struct {
	Limit         string
	Service       string
	Env           string
	ReleaseResult string
}

type EvidenceReleaseQuery struct {
	ReleaseID  string
	IncludeRaw bool
}

type EvidenceObjectQuery struct {
	ObjectType string
	ObjectID   string
	ReleaseID  string
	IncludeRaw bool
}

type EvidenceArtifactListQuery struct {
	Limit        string
	ReleaseID    string
	ArtifactKind string
}

type EvidenceSearchQuery struct {
	Query      string
	Limit      string
	ObjectType string
	ReleaseID  string
	IncludeRaw bool
}

type EvidenceVerificationSummaryQuery struct {
	ReleaseID string
	Limit     string
}

type EvidenceRepositoryResponse struct {
	Body   []byte
	DBFile string
	Mode   string
}

type EvidenceRepositoryError struct {
	StatusCode int
	Message    string
	Err        error
}

func (err *EvidenceRepositoryError) Error() string {
	if err == nil {
		return ""
	}

	if err.Err == nil {
		return err.Message
	}

	return err.Message + ": " + err.Err.Error()
}

func (err *EvidenceRepositoryError) Unwrap() error {
	if err == nil {
		return nil
	}

	return err.Err
}

type CLIEvidenceRepository struct {
	api *portalAPI
}

func (api *portalAPI) evidenceRepository() EvidenceRepository {
	return &CLIEvidenceRepository{
		api: api,
	}
}

func (repo *CLIEvidenceRepository) ListReleases(r *http.Request, query EvidenceReleaseListQuery) (*EvidenceRepositoryResponse, error) {
	limit := strings.TrimSpace(query.Limit)
	if limit == "" {
		limit = "50"
	}

	args := []string{
		"list-releases",
		"--limit", limit,
	}

	if service := strings.TrimSpace(query.Service); service != "" {
		args = append(args, "--service", service)
	}

	if env := strings.TrimSpace(query.Env); env != "" {
		args = append(args, "--env", env)
	}

	if releaseResult := strings.TrimSpace(query.ReleaseResult); releaseResult != "" {
		args = append(args, "--release-result", releaseResult)
	}

	return repo.query(r, args...)
}

func (repo *CLIEvidenceRepository) GetRelease(r *http.Request, query EvidenceReleaseQuery) (*EvidenceRepositoryResponse, error) {
	args := []string{
		"query-release",
		"--release-id", strings.TrimSpace(query.ReleaseID),
	}

	if query.IncludeRaw {
		args = append(args, "--include-raw")
	}

	return repo.query(r, args...)
}

func (repo *CLIEvidenceRepository) GetObject(r *http.Request, query EvidenceObjectQuery) (*EvidenceRepositoryResponse, error) {
	args := []string{
		"get-object",
		"--object-type", strings.TrimSpace(query.ObjectType),
		"--object-id", strings.TrimSpace(query.ObjectID),
	}

	if releaseID := strings.TrimSpace(query.ReleaseID); releaseID != "" {
		args = append(args, "--release-id", releaseID)
	}

	if query.IncludeRaw {
		args = append(args, "--include-raw")
	}

	return repo.query(r, args...)
}

func (repo *CLIEvidenceRepository) ListArtifacts(r *http.Request, query EvidenceArtifactListQuery) (*EvidenceRepositoryResponse, error) {
	limit := strings.TrimSpace(query.Limit)
	if limit == "" {
		limit = "50"
	}

	args := []string{
		"list-artifacts",
		"--limit", limit,
	}

	if releaseID := strings.TrimSpace(query.ReleaseID); releaseID != "" {
		args = append(args, "--release-id", releaseID)
	}

	if artifactKind := strings.TrimSpace(query.ArtifactKind); artifactKind != "" {
		args = append(args, "--artifact-kind", artifactKind)
	}

	return repo.query(r, args...)
}

func (repo *CLIEvidenceRepository) SearchObjects(r *http.Request, query EvidenceSearchQuery) (*EvidenceRepositoryResponse, error) {
	limit := strings.TrimSpace(query.Limit)
	if limit == "" {
		limit = "50"
	}

	args := []string{
		"search-objects",
		"--query", strings.TrimSpace(query.Query),
		"--limit", limit,
	}

	if objectType := strings.TrimSpace(query.ObjectType); objectType != "" {
		args = append(args, "--object-type", objectType)
	}

	if releaseID := strings.TrimSpace(query.ReleaseID); releaseID != "" {
		args = append(args, "--release-id", releaseID)
	}

	if query.IncludeRaw {
		args = append(args, "--include-raw")
	}

	return repo.query(r, args...)
}

func (repo *CLIEvidenceRepository) GetVerificationSummary(r *http.Request, query EvidenceVerificationSummaryQuery) (*EvidenceRepositoryResponse, error) {
	limit := strings.TrimSpace(query.Limit)
	if limit == "" {
		limit = "50"
	}

	args := []string{
		"verification-summary",
		"--limit", limit,
	}

	if releaseID := strings.TrimSpace(query.ReleaseID); releaseID != "" {
		args = append(args, "--release-id", releaseID)
	}

	return repo.query(r, args...)
}

func (repo *CLIEvidenceRepository) query(r *http.Request, args ...string) (*EvidenceRepositoryResponse, error) {
	dbFile, err := repo.api.ensureEvidenceStoreDBReady()
	if err != nil {
		return nil, &EvidenceRepositoryError{
			StatusCode: http.StatusConflict,
			Message:    "evidence store db is not ready",
			Err:        err,
		}
	}

	if len(args) == 0 {
		return nil, &EvidenceRepositoryError{
			StatusCode: http.StatusInternalServerError,
			Message:    "empty evidence store command",
		}
	}

	commandArgs := append([]string{args[0], "--db", dbFile}, args[1:]...)

	output, err := repo.api.runEvidenceStoreCommand(r, commandArgs...)
	if err != nil {
		return nil, &EvidenceRepositoryError{
			StatusCode: http.StatusInternalServerError,
			Message:    "failed to query evidence store",
			Err:        err,
		}
	}

	return &EvidenceRepositoryResponse{
		Body:   output,
		DBFile: dbFile,
		Mode:   "sqlite-adapter",
	}, nil
}
