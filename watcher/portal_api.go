package main

import (
	"encoding/json"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

type portalAPI struct {
	cfg       Config
	reportDir string
}

type portalResourceDef struct {
	Name         string   `json:"name"`
	Endpoint     string   `json:"endpoint,omitempty"`
	Candidates   []string `json:"candidates"`
	FallbackGlob string   `json:"fallbackGlob,omitempty"`
	ContentType  string   `json:"contentType"`
	Description  string   `json:"description"`
}

type portalResourceStatus struct {
	Name        string   `json:"name"`
	Endpoint    string   `json:"endpoint,omitempty"`
	Exists      bool     `json:"exists"`
	File        string   `json:"file,omitempty"`
	BaseName    string   `json:"baseName,omitempty"`
	SizeBytes   int64    `json:"sizeBytes,omitempty"`
	ModifiedAt  string   `json:"modifiedAt,omitempty"`
	ContentType string   `json:"contentType"`
	Description string   `json:"description"`
	Candidates  []string `json:"candidates,omitempty"`
}

type portalLatestResponse struct {
	SchemaVersion string                          `json:"schemaVersion"`
	GeneratedAt   string                          `json:"generatedAt"`
	Mode          string                          `json:"mode"`
	ReportDir     string                          `json:"reportDir"`
	Resources     map[string]portalResourceStatus `json:"resources"`
	Endpoints     []string                        `json:"endpoints"`
	Safety        map[string]interface{}          `json:"safety"`
}

type portalReleaseListItem struct {
	File       string `json:"file"`
	BaseName   string `json:"baseName"`
	Kind       string `json:"kind"`
	SizeBytes  int64  `json:"sizeBytes"`
	ModifiedAt string `json:"modifiedAt"`
}

type portalReleaseListResponse struct {
	SchemaVersion string                  `json:"schemaVersion"`
	GeneratedAt   string                  `json:"generatedAt"`
	ReportDir     string                  `json:"reportDir"`
	Count         int                     `json:"count"`
	Items         []portalReleaseListItem `json:"items"`
}

func registerPortalAPIHandlers(mux *http.ServeMux, cfg Config) {
	api := &portalAPI{
		cfg:       cfg,
		reportDir: filepath.Join(cfg.RepoDir, "docs", "release-reports"),
	}

	mux.HandleFunc("/api/releases", api.handleReleaseList)
	mux.HandleFunc("/api/releases/latest", api.handleLatestIndex)
	mux.HandleFunc("/api/releases/latest/evidence", api.handleLatestResource("releaseEvidence"))
	mux.HandleFunc("/api/releases/latest/summary", api.handleLatestResource("releaseSummary"))
	mux.HandleFunc("/api/releases/latest/action-plan", api.handleLatestResource("actionPlan"))
	mux.HandleFunc("/api/releases/latest/intelligence", api.handleLatestResource("releaseIntelligence"))
	mux.HandleFunc("/api/releases/latest/approval", api.handleLatestResource("approvalRecord"))
	mux.HandleFunc("/api/releases/latest/failure-evidence", api.handleLatestResource("failureEvidence"))
	mux.HandleFunc("/api/releases/latest/advice", api.handleLatestResource("aiAdvice"))
	mux.HandleFunc("/api/releases/latest/memory", api.handleLatestResource("releaseMemory"))
}

func portalResourceDefs() []portalResourceDef {
	return []portalResourceDef{
		{
			Name:         "releaseEvidence",
			Endpoint:     "/api/releases/latest/evidence",
			Candidates:   []string{"release-evidence-latest.json"},
			FallbackGlob: "release-evidence-*.json",
			ContentType:  "application/json; charset=utf-8",
			Description:  "Latest release evidence index.",
		},
		{
			Name:         "releaseSummary",
			Endpoint:     "/api/releases/latest/summary",
			Candidates:   []string{"release-summary-latest.md"},
			FallbackGlob: "release-summary-*.md",
			ContentType:  "text/markdown; charset=utf-8",
			Description:  "Latest human-readable release summary.",
		},
		{
			Name:         "actionPlan",
			Endpoint:     "/api/releases/latest/action-plan",
			Candidates:   []string{"action-plan-latest.json"},
			FallbackGlob: "action-plan-*.json",
			ContentType:  "application/json; charset=utf-8",
			Description:  "Latest dry-run action plan.",
		},
		{
			Name:         "releaseIntelligence",
			Endpoint:     "/api/releases/latest/intelligence",
			Candidates:   []string{"release-intelligence-latest.json"},
			FallbackGlob: "release-intelligence-*.json",
			ContentType:  "application/json; charset=utf-8",
			Description:  "Latest release intelligence result.",
		},
		{
			Name:         "approvalRecord",
			Endpoint:     "/api/releases/latest/approval",
			Candidates:   []string{"approval-record-latest.json"},
			FallbackGlob: "approval-record-*.json",
			ContentType:  "application/json; charset=utf-8",
			Description:  "Latest human approval record.",
		},
		{
			Name:         "failureEvidence",
			Endpoint:     "/api/releases/latest/failure-evidence",
			Candidates:   []string{"failure-evidence-latest.json"},
			FallbackGlob: "failure-evidence-*.json",
			ContentType:  "application/json; charset=utf-8",
			Description:  "Latest failure evidence.",
		},
		{
			Name:         "aiAdvice",
			Endpoint:     "/api/releases/latest/advice",
			Candidates:   []string{"ai-advice-latest.md"},
			FallbackGlob: "ai-advice-*.md",
			ContentType:  "text/markdown; charset=utf-8",
			Description:  "Latest AI advice report.",
		},
		{
			Name:         "releaseMemory",
			Endpoint:     "/api/releases/latest/memory",
			Candidates:   []string{"release-memory-latest.json"},
			FallbackGlob: "release-memory-*.json",
			ContentType:  "application/json; charset=utf-8",
			Description:  "Latest release memory summary.",
		},
		{
			Name:        "changeContext",
			Candidates:  []string{"change-context-latest.json"},
			ContentType: "application/json; charset=utf-8",
			Description: "Latest change context.",
		},
		{
			Name:        "changeRiskDecision",
			Candidates:  []string{"change-risk-decision-latest.json"},
			ContentType: "application/json; charset=utf-8",
			Description: "Latest change risk decision.",
		},
		{
			Name:        "releaseEvents",
			Candidates:  []string{"release-events.jsonl"},
			ContentType: "application/x-ndjson; charset=utf-8",
			Description: "Release event archive.",
		},
	}
}

func (api *portalAPI) handleLatestIndex(w http.ResponseWriter, r *http.Request) {
	if !api.requireGET(w, r) {
		return
	}

	resources := map[string]portalResourceStatus{}
	endpoints := []string{
		"/api/releases",
		"/api/releases/latest",
	}

	for _, def := range portalResourceDefs() {
		status := api.resourceStatus(def)
		resources[def.Name] = status
		if def.Endpoint != "" {
			endpoints = append(endpoints, def.Endpoint)
		}
	}

	writePortalJSON(w, http.StatusOK, portalLatestResponse{
		SchemaVersion: "release-portal/v1alpha1",
		GeneratedAt:   time.Now().Format(time.RFC3339),
		Mode:          "read_only",
		ReportDir:     api.reportDir,
		Resources:     resources,
		Endpoints:     endpoints,
		Safety: map[string]interface{}{
			"readOnly":          true,
			"willExecute":       false,
			"supportsRollback":  false,
			"supportsPromote":   false,
			"supportsPatch":     false,
			"supportsDelete":    false,
			"requiresHumanGate": true,
		},
	})
}

func (api *portalAPI) handleReleaseList(w http.ResponseWriter, r *http.Request) {
	if !api.requireGET(w, r) {
		return
	}

	items := []portalReleaseListItem{}

	patterns := []string{
		"release-evidence-*.json",
		"release-summary-*.md",
		"action-plan-*.json",
		"release-intelligence-*.json",
		"approval-record-*.json",
		"failure-evidence-*.json",
	}

	for _, pattern := range patterns {
		matches, _ := filepath.Glob(filepath.Join(api.reportDir, pattern))
		for _, path := range matches {
			base := filepath.Base(path)
			if strings.Contains(base, "-latest.") {
				continue
			}

			info, err := os.Stat(path)
			if err != nil || info.IsDir() {
				continue
			}

			items = append(items, portalReleaseListItem{
				File:       path,
				BaseName:   base,
				Kind:       kindFromReportFile(base),
				SizeBytes:  info.Size(),
				ModifiedAt: info.ModTime().Format(time.RFC3339),
			})
		}
	}

	sort.Slice(items, func(i, j int) bool {
		return items[i].BaseName > items[j].BaseName
	})

	if len(items) > 50 {
		items = items[:50]
	}

	writePortalJSON(w, http.StatusOK, portalReleaseListResponse{
		SchemaVersion: "release-portal/v1alpha1",
		GeneratedAt:   time.Now().Format(time.RFC3339),
		ReportDir:     api.reportDir,
		Count:         len(items),
		Items:         items,
	})
}

func (api *portalAPI) handleLatestResource(name string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if !api.requireGET(w, r) {
			return
		}

		def, ok := findPortalResourceDef(name)
		if !ok {
			writePortalJSON(w, http.StatusNotFound, map[string]interface{}{
				"error": "unknown resource",
				"name":  name,
			})
			return
		}

		status := api.resourceStatus(def)
		if !status.Exists {
			writePortalJSON(w, http.StatusNotFound, map[string]interface{}{
				"error":        "resource not found",
				"name":         def.Name,
				"reportDir":    api.reportDir,
				"candidates":   def.Candidates,
				"fallbackGlob": def.FallbackGlob,
			})
			return
		}

		data, err := os.ReadFile(status.File)
		if err != nil {
			writePortalJSON(w, http.StatusInternalServerError, map[string]interface{}{
				"error": err.Error(),
				"file":  status.File,
			})
			return
		}

		w.Header().Set("Content-Type", def.ContentType)
		w.Header().Set("X-Release-Portal-File", status.BaseName)
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write(data)
	}
}

func (api *portalAPI) resourceStatus(def portalResourceDef) portalResourceStatus {
	path, info, ok := api.findResourceFile(def)

	status := portalResourceStatus{
		Name:        def.Name,
		Endpoint:    def.Endpoint,
		Exists:      ok,
		ContentType: def.ContentType,
		Description: def.Description,
		Candidates:  def.Candidates,
	}

	if ok {
		status.File = path
		status.BaseName = filepath.Base(path)
		status.SizeBytes = info.Size()
		status.ModifiedAt = info.ModTime().Format(time.RFC3339)
	}

	return status
}

func (api *portalAPI) findResourceFile(def portalResourceDef) (string, os.FileInfo, bool) {
	for _, candidate := range def.Candidates {
		path := filepath.Join(api.reportDir, candidate)
		info, err := os.Stat(path)
		if err == nil && !info.IsDir() {
			return path, info, true
		}
	}

	if def.FallbackGlob == "" {
		return "", nil, false
	}

	matches, err := filepath.Glob(filepath.Join(api.reportDir, def.FallbackGlob))
	if err != nil {
		return "", nil, false
	}

	type candidateFile struct {
		path string
		info os.FileInfo
	}

	candidates := []candidateFile{}
	for _, path := range matches {
		base := filepath.Base(path)
		if strings.Contains(base, "-latest.") {
			continue
		}

		info, err := os.Stat(path)
		if err != nil || info.IsDir() {
			continue
		}

		candidates = append(candidates, candidateFile{path: path, info: info})
	}

	if len(candidates) == 0 {
		return "", nil, false
	}

	sort.Slice(candidates, func(i, j int) bool {
		return candidates[i].info.ModTime().After(candidates[j].info.ModTime())
	})

	return candidates[0].path, candidates[0].info, true
}

func (api *portalAPI) requireGET(w http.ResponseWriter, r *http.Request) bool {
	if r.Method == http.MethodGet {
		return true
	}

	w.Header().Set("Allow", http.MethodGet)
	writePortalJSON(w, http.StatusMethodNotAllowed, map[string]interface{}{
		"error":  "method not allowed",
		"method": r.Method,
	})
	return false
}

func findPortalResourceDef(name string) (portalResourceDef, bool) {
	for _, def := range portalResourceDefs() {
		if def.Name == name {
			return def, true
		}
	}

	return portalResourceDef{}, false
}

func writePortalJSON(w http.ResponseWriter, statusCode int, value interface{}) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(statusCode)

	encoder := json.NewEncoder(w)
	encoder.SetIndent("", "  ")
	_ = encoder.Encode(value)
}

func kindFromReportFile(base string) string {
	switch {
	case strings.HasPrefix(base, "release-evidence-"):
		return "releaseEvidence"
	case strings.HasPrefix(base, "release-summary-"):
		return "releaseSummary"
	case strings.HasPrefix(base, "action-plan-"):
		return "actionPlan"
	case strings.HasPrefix(base, "release-intelligence-"):
		return "releaseIntelligence"
	case strings.HasPrefix(base, "approval-record-"):
		return "approvalRecord"
	case strings.HasPrefix(base, "failure-evidence-"):
		return "failureEvidence"
	default:
		return "unknown"
	}
}
