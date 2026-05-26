package main

import "testing"

func TestGitOpsRealPRPortalResourceMappings(t *testing.T) {
	tests := []struct {
		kind    string
		segment string
		prefix  string
	}{
		{"gitopsRealPRPlan", "gitops-real-pr-plan", "gitops-real-pr-plan"},
		{"gitopsRealPRWorkspace", "gitops-real-pr-workspace", "gitops-real-pr-workspace"},
		{"gitopsRealPRMaterialization", "gitops-real-pr-materialization", "gitops-real-pr-materialization"},
		{"gitopsRealPRFileMaterialization", "gitops-real-pr-file-materialization", "gitops-real-pr-file-materialization"},
		{"gitopsRealPRLocalCommit", "gitops-real-pr-local-commit", "gitops-real-pr-local-commit"},
		{"gitopsRealPRPushPreflight", "gitops-real-pr-push-preflight", "gitops-real-pr-push-preflight"},
		{"gitopsRealPRBranchPush", "gitops-real-pr-branch-push", "gitops-real-pr-branch-push"},
		{"gitopsRealPRCreatePreflight", "gitops-real-pr-create-preflight", "gitops-real-pr-create-preflight"},
		{"gitopsRealPRCreate", "gitops-real-pr-create", "gitops-real-pr-create"},
		{"gitopsRealPRCleanup", "gitops-real-pr-cleanup", "gitops-real-pr-cleanup"},
	}

	for _, tt := range tests {
		t.Run(tt.kind, func(t *testing.T) {
			def, ok := findPortalResourceDef(tt.kind)
			if !ok {
				t.Fatalf("resource def not found: %s", tt.kind)
			}

			if got, want := def.Endpoint, "/api/releases/latest/"+tt.segment; got != want {
				t.Fatalf("endpoint = %q, want %q", got, want)
			}
			if got, want := def.ContentType, "application/json; charset=utf-8"; got != want {
				t.Fatalf("content type = %q, want %q", got, want)
			}
			if len(def.Candidates) != 1 || def.Candidates[0] != tt.prefix+"-latest.json" {
				t.Fatalf("candidates = %#v, want [%s-latest.json]", def.Candidates, tt.prefix)
			}
			if got, want := def.FallbackGlob, tt.prefix+"-*.json"; got != want {
				t.Fatalf("fallback glob = %q, want %q", got, want)
			}

			kind, contentType, ok := portalResourceKindFromPathSegment(tt.segment)
			if !ok {
				t.Fatalf("path segment not recognized: %s", tt.segment)
			}
			if kind != tt.kind {
				t.Fatalf("path segment kind = %q, want %q", kind, tt.kind)
			}
			if contentType != "application/json; charset=utf-8" {
				t.Fatalf("path segment content type = %q", contentType)
			}

			fileName := tt.prefix + "-20260526-230000.json"
			if got := kindFromReportFile(fileName); got != tt.kind {
				t.Fatalf("kindFromReportFile(%q) = %q, want %q", fileName, got, tt.kind)
			}
			if got := releaseIDFromReportFile(fileName); got != "20260526-230000" {
				t.Fatalf("releaseIDFromReportFile(%q) = %q, want 20260526-230000", fileName, got)
			}

			latestName := tt.prefix + "-latest.json"
			if got := releaseIDFromReportFile(latestName); got != "" {
				t.Fatalf("releaseIDFromReportFile(%q) = %q, want empty latest release id", latestName, got)
			}
		})
	}
}
