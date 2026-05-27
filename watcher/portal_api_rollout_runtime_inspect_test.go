package main

import "testing"

func TestRolloutRuntimeInspectPortalResourceMapping(t *testing.T) {
	const kind = "rolloutRuntimeInspect"
	const segment = "rollout-runtime-inspect"
	const prefix = "rollout-runtime-inspect"

	def, ok := findPortalResourceDef(kind)
	if !ok {
		t.Fatalf("resource def not found: %s", kind)
	}

	if got, want := def.Endpoint, "/api/releases/latest/"+segment; got != want {
		t.Fatalf("endpoint = %q, want %q", got, want)
	}
	if got, want := def.ContentType, "application/json; charset=utf-8"; got != want {
		t.Fatalf("content type = %q, want %q", got, want)
	}
	if len(def.Candidates) != 1 || def.Candidates[0] != prefix+"-latest.json" {
		t.Fatalf("candidates = %#v, want [%s-latest.json]", def.Candidates, prefix)
	}
	if got, want := def.FallbackGlob, prefix+"-*.json"; got != want {
		t.Fatalf("fallback glob = %q, want %q", got, want)
	}

	gotKind, contentType, ok := portalResourceKindFromPathSegment(segment)
	if !ok {
		t.Fatalf("path segment not recognized: %s", segment)
	}
	if gotKind != kind {
		t.Fatalf("path segment kind = %q, want %q", gotKind, kind)
	}
	if contentType != "application/json; charset=utf-8" {
		t.Fatalf("path segment content type = %q", contentType)
	}

	fileName := prefix + "-20260527-010101.json"
	if got := kindFromReportFile(fileName); got != kind {
		t.Fatalf("kindFromReportFile(%q) = %q, want %q", fileName, got, kind)
	}
	if got := releaseIDFromReportFile(fileName); got != "20260527-010101" {
		t.Fatalf("releaseIDFromReportFile(%q) = %q, want 20260527-010101", fileName, got)
	}

	latestName := prefix + "-latest.json"
	if got := releaseIDFromReportFile(latestName); got != "" {
		t.Fatalf("releaseIDFromReportFile(%q) = %q, want empty latest release id", latestName, got)
	}
}
