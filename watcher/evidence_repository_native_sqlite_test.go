package main

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestEvidenceRepositoryFactoryDefaultAndNativeSQLitePlaceholder(t *testing.T) {
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

	if nativeDescriptor.RepositoryType != "native-sqlite-disabled" {
		t.Fatalf("expected native repositoryType=native-sqlite-disabled, got %s", nativeDescriptor.RepositoryType)
	}

	if nativeDescriptor.Mode != "native-sqlite-repository-disabled" {
		t.Fatalf("expected native mode=native-sqlite-repository-disabled, got %s", nativeDescriptor.Mode)
	}

	req := httptest.NewRequest(http.MethodGet, "/api/evidence/releases?limit=1", nil)
	_, err := nativeRepo.ListReleases(req, EvidenceReleaseListQuery{Limit: "1"})
	if err == nil {
		t.Fatal("expected native sqlite placeholder to reject query")
	}

	repositoryErr, ok := err.(*EvidenceRepositoryError)
	if !ok {
		t.Fatalf("expected EvidenceRepositoryError, got %T", err)
	}

	if repositoryErr.StatusCode != http.StatusNotImplemented {
		t.Fatalf("expected HTTP 501, got %d", repositoryErr.StatusCode)
	}
}
