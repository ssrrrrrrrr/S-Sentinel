package main

import (
	"fmt"
	"net/http"
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
		RepositoryType:              "native-sqlite-disabled",
		Mode:                        "native-sqlite-repository-disabled",
		RuntimeMode:                 runtimeDescriptor.Mode,
		Backend:                     "sqlite",
		Adapter:                     "go-native-placeholder",
		Storage:                     runtimeDescriptor.Storage,
		QueryModel:                  "native-sqlite-disabled",
		ContractVersion:             "evidence.repository/v1alpha1",
		ReadOnly:                    true,
		WillExecute:                 false,
		SupportsListReleases:        false,
		SupportsGetRelease:          false,
		SupportsGetObject:           false,
		SupportsListArtifacts:       false,
		SupportsSearch:              false,
		SupportsVerificationSummary: false,
		SupportsGraph:               false,
		SupportsNativeSQLite:        false,
		SupportsRemoteAPI:           false,
		Description:                 "Native SQLite repository foundation. Disabled until a Go SQLite driver and query implementation are added.",
	}
}

func (repo *NativeSQLiteEvidenceRepository) ListReleases(r *http.Request, query EvidenceReleaseListQuery) (*EvidenceRepositoryResponse, error) {
	return nil, repo.unsupported("list releases")
}

func (repo *NativeSQLiteEvidenceRepository) GetRelease(r *http.Request, query EvidenceReleaseQuery) (*EvidenceRepositoryResponse, error) {
	return nil, repo.unsupported("get release")
}

func (repo *NativeSQLiteEvidenceRepository) GetObject(r *http.Request, query EvidenceObjectQuery) (*EvidenceRepositoryResponse, error) {
	return nil, repo.unsupported("get object")
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

func (repo *NativeSQLiteEvidenceRepository) unsupported(operation string) error {
	return &EvidenceRepositoryError{
		StatusCode: http.StatusNotImplemented,
		Message:    "native sqlite evidence repository is not implemented",
		Err: fmt.Errorf(
			"%s requires a Go SQLite driver and native query implementation; current safe default remains cli-backed repository",
			operation,
		),
	}
}
