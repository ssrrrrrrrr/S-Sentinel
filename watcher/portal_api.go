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

type portalReleaseResource struct {
	Kind         string `json:"kind"`
	File         string `json:"file"`
	BaseName     string `json:"baseName"`
	ReleaseID    string `json:"resourceId"`
	SizeBytes    int64  `json:"sizeBytes"`
	ModifiedAt   string `json:"modifiedAt"`
	ModifiedUnix int64  `json:"-"`
}

type portalReleaseGroup struct {
	ReleaseID     string                           `json:"releaseId"`
	GeneratedAt   string                           `json:"generatedAt,omitempty"`
	ModifiedAt    string                           `json:"modifiedAt,omitempty"`
	ModifiedUnix  int64                            `json:"-"`
	ResourceCount int                              `json:"resourceCount"`
	Summary       map[string]interface{}           `json:"summary,omitempty"`
	Resources     map[string]portalReleaseResource `json:"resources"`
}

type portalReleaseListResponse struct {
	SchemaVersion string               `json:"schemaVersion"`
	GeneratedAt   string               `json:"generatedAt"`
	ReportDir     string               `json:"reportDir"`
	Count         int                  `json:"count"`
	Items         []portalReleaseGroup `json:"items"`
}

type portalReleaseDetailResponse struct {
	SchemaVersion string             `json:"schemaVersion"`
	GeneratedAt   string             `json:"generatedAt"`
	ReportDir     string             `json:"reportDir"`
	Release       portalReleaseGroup `json:"release"`
	Safety        map[string]bool    `json:"safety"`
}

func registerPortalAPIHandlers(mux *http.ServeMux, cfg Config) {
	api := &portalAPI{
		cfg:       cfg,
		reportDir: filepath.Join(cfg.RepoDir, "docs", "release-reports"),
	}

	mux.HandleFunc("/api/releases", api.handleReleaseList)
	mux.HandleFunc("/api/releases/", api.handleReleaseDetail)
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

	groups := api.buildReleaseGroups()

	items := []portalReleaseGroup{}
	for _, group := range groups {
		if _, ok := group.Resources["releaseEvidence"]; !ok {
			continue
		}

		group.ResourceCount = len(group.Resources)
		items = append(items, *group)
	}

	sort.Slice(items, func(i, j int) bool {
		if items[i].ModifiedUnix == items[j].ModifiedUnix {
			return items[i].ReleaseID > items[j].ReleaseID
		}
		return items[i].ModifiedUnix > items[j].ModifiedUnix
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

func (api *portalAPI) handleReleaseDetail(w http.ResponseWriter, r *http.Request) {
	if !api.requireGET(w, r) {
		return
	}

	releaseID := strings.TrimPrefix(r.URL.Path, "/api/releases/")
	releaseID = strings.TrimSpace(releaseID)

	if releaseID == "" || strings.Contains(releaseID, "/") {
		writePortalJSON(w, http.StatusNotFound, map[string]interface{}{
			"error": "release not found",
			"path":  r.URL.Path,
		})
		return
	}

	groups := api.buildReleaseGroups()
	group, ok := groups[releaseID]
	if !ok {
		writePortalJSON(w, http.StatusNotFound, map[string]interface{}{
			"error":                  "release not found",
			"releaseId":              releaseID,
			"reportDir":              api.reportDir,
			"availableReleaseIds":    availablePortalReleaseIDs(groups, 20),
			"requiresEvidenceBacked": true,
		})
		return
	}

	if _, ok := group.Resources["releaseEvidence"]; !ok {
		writePortalJSON(w, http.StatusNotFound, map[string]interface{}{
			"error":                  "release is not evidence-backed",
			"releaseId":              releaseID,
			"reportDir":              api.reportDir,
			"requiresEvidenceBacked": true,
		})
		return
	}

	group.ResourceCount = len(group.Resources)

	writePortalJSON(w, http.StatusOK, portalReleaseDetailResponse{
		SchemaVersion: "release-portal/v1alpha1",
		GeneratedAt:   time.Now().Format(time.RFC3339),
		ReportDir:     api.reportDir,
		Release:       *group,
		Safety: map[string]bool{
			"readOnly":         true,
			"willExecute":      false,
			"supportsRollback": false,
			"supportsPromote":  false,
			"supportsPatch":    false,
			"supportsDelete":   false,
		},
	})
}

func (api *portalAPI) buildReleaseGroups() map[string]*portalReleaseGroup {
	resources := api.listPortalReportResources()

	resourceByBase := map[string]portalReleaseResource{}
	evidenceIDByBase := map[string]string{}
	groups := map[string]*portalReleaseGroup{}

	for _, res := range resources {
		resourceByBase[res.BaseName] = res
		if res.Kind == "releaseEvidence" && res.ReleaseID != "" {
			evidenceIDByBase[res.BaseName] = res.ReleaseID
			addResourceToReleaseGroup(groups, res.ReleaseID, res)
		}
	}

	for _, res := range resources {
		if res.Kind == "releaseEvidence" {
			continue
		}

		if targetID := api.sourceReleaseIDFromJSON(res.File, evidenceIDByBase); targetID != "" {
			addResourceToReleaseGroup(groups, targetID, res)
			continue
		}

		addResourceToReleaseGroup(groups, res.ReleaseID, res)
	}

	for _, res := range resources {
		if res.Kind != "releaseEvidence" || res.ReleaseID == "" {
			continue
		}

		group := groups[res.ReleaseID]
		api.attachReferencedResourcesFromJSON(group, res.File, resourceByBase)
		api.decorateReleaseGroupSummary(group, res.File)
	}

	return groups
}

func availablePortalReleaseIDs(groups map[string]*portalReleaseGroup, limit int) []string {
	ids := []string{}

	for id, group := range groups {
		if _, ok := group.Resources["releaseEvidence"]; ok {
			ids = append(ids, id)
		}
	}

	sort.Slice(ids, func(i, j int) bool {
		left := groups[ids[i]]
		right := groups[ids[j]]

		if left.ModifiedUnix == right.ModifiedUnix {
			return ids[i] > ids[j]
		}
		return left.ModifiedUnix > right.ModifiedUnix
	})

	if limit > 0 && len(ids) > limit {
		return ids[:limit]
	}

	return ids
}

func (api *portalAPI) listPortalReportResources() []portalReleaseResource {
	patterns := []string{
		"release-evidence-*.json",
		"release-summary-*.md",
		"action-plan-*.json",
		"release-intelligence-*.json",
		"approval-record-*.json",
		"failure-evidence-*.json",
		"ai-advice-*.md",
		"ai-decision-*.json",
		"policy-decision-*.json",
		"release-context-*.json",
	}

	seen := map[string]bool{}
	resources := []portalReleaseResource{}

	for _, pattern := range patterns {
		matches, _ := filepath.Glob(filepath.Join(api.reportDir, pattern))
		for _, path := range matches {
			base := filepath.Base(path)
			if seen[base] || strings.Contains(base, "-latest.") {
				continue
			}
			seen[base] = true

			res, ok := api.reportResourceFromPath(path)
			if ok {
				resources = append(resources, res)
			}
		}
	}

	return resources
}

func (api *portalAPI) reportResourceFromPath(path string) (portalReleaseResource, bool) {
	base := filepath.Base(path)
	kind := kindFromReportFile(base)
	releaseID := releaseIDFromReportFile(base)

	if kind == "unknown" || releaseID == "" {
		return portalReleaseResource{}, false
	}

	info, err := os.Stat(path)
	if err != nil || info.IsDir() {
		return portalReleaseResource{}, false
	}

	return portalReleaseResource{
		Kind:         kind,
		File:         path,
		BaseName:     base,
		ReleaseID:    releaseID,
		SizeBytes:    info.Size(),
		ModifiedAt:   info.ModTime().Format(time.RFC3339),
		ModifiedUnix: info.ModTime().Unix(),
	}, true
}

func addResourceToReleaseGroup(groups map[string]*portalReleaseGroup, releaseID string, res portalReleaseResource) {
	if releaseID == "" {
		return
	}

	group, ok := groups[releaseID]
	if !ok {
		group = &portalReleaseGroup{
			ReleaseID:   releaseID,
			GeneratedAt: releaseID,
			Summary:     map[string]interface{}{},
			Resources:   map[string]portalReleaseResource{},
		}
		groups[releaseID] = group
	}

	existing, exists := group.Resources[res.Kind]
	if !exists || res.ModifiedUnix >= existing.ModifiedUnix {
		group.Resources[res.Kind] = res
	}

	if res.ModifiedUnix >= group.ModifiedUnix {
		group.ModifiedUnix = res.ModifiedUnix
		group.ModifiedAt = res.ModifiedAt
	}
}

func (api *portalAPI) sourceReleaseIDFromJSON(path string, evidenceIDByBase map[string]string) string {
	doc, ok := readPortalJSONDocument(path)
	if !ok {
		return ""
	}

	values := []string{}
	collectPortalStringValues(doc, &values)

	for _, value := range values {
		base := filepath.Base(value)
		if id, ok := evidenceIDByBase[base]; ok {
			return id
		}

		for evidenceBase, id := range evidenceIDByBase {
			if strings.Contains(value, evidenceBase) {
				return id
			}
		}
	}

	return ""
}

func (api *portalAPI) attachReferencedResourcesFromJSON(group *portalReleaseGroup, path string, resourceByBase map[string]portalReleaseResource) {
	if group == nil {
		return
	}

	doc, ok := readPortalJSONDocument(path)
	if !ok {
		return
	}

	values := []string{}
	collectPortalStringValues(doc, &values)

	for _, value := range values {
		base := filepath.Base(value)
		if res, ok := resourceByBase[base]; ok {
			addResourceToReleaseGroup(map[string]*portalReleaseGroup{group.ReleaseID: group}, group.ReleaseID, res)
			continue
		}

		for knownBase, res := range resourceByBase {
			if strings.Contains(value, knownBase) {
				addResourceToReleaseGroup(map[string]*portalReleaseGroup{group.ReleaseID: group}, group.ReleaseID, res)
			}
		}
	}
}

func (api *portalAPI) decorateReleaseGroupSummary(group *portalReleaseGroup, evidenceFile string) {
	if group == nil {
		return
	}

	doc, ok := readPortalJSONDocument(evidenceFile)
	if !ok {
		return
	}

	keys := []string{
		"releaseResult",
		"policyDecision",
		"finalAction",
		"executionMode",
		"requiresHumanApproval",
		"safeToRetry",
		"riskLevel",
		"riskScore",
	}

	for _, key := range keys {
		if value, ok := findPortalJSONValue(doc, key); ok {
			group.Summary[key] = value
		}
	}
}

func readPortalJSONDocument(path string) (interface{}, bool) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, false
	}

	var doc interface{}
	if err := json.Unmarshal(data, &doc); err != nil {
		return nil, false
	}

	return doc, true
}

func collectPortalStringValues(value interface{}, out *[]string) {
	switch v := value.(type) {
	case string:
		*out = append(*out, v)
	case []interface{}:
		for _, item := range v {
			collectPortalStringValues(item, out)
		}
	case map[string]interface{}:
		for _, item := range v {
			collectPortalStringValues(item, out)
		}
	}
}

func findPortalJSONValue(value interface{}, key string) (interface{}, bool) {
	switch v := value.(type) {
	case map[string]interface{}:
		if found, ok := v[key]; ok {
			return found, true
		}

		for _, item := range v {
			if found, ok := findPortalJSONValue(item, key); ok {
				return found, true
			}
		}
	case []interface{}:
		for _, item := range v {
			if found, ok := findPortalJSONValue(item, key); ok {
				return found, true
			}
		}
	}

	return nil, false
}

func releaseIDFromReportFile(base string) string {
	prefixes := []string{
		"release-evidence-",
		"release-summary-",
		"action-plan-",
		"release-intelligence-",
		"approval-record-",
		"failure-evidence-",
		"ai-advice-",
		"ai-decision-",
		"policy-decision-",
		"release-context-",
	}

	for _, prefix := range prefixes {
		if strings.HasPrefix(base, prefix) {
			id := strings.TrimPrefix(base, prefix)
			id = strings.TrimSuffix(id, ".json")
			id = strings.TrimSuffix(id, ".md")
			if id == "latest" {
				return ""
			}
			return id
		}
	}

	return ""
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
	case strings.HasPrefix(base, "ai-advice-"):
		return "aiAdvice"
	case strings.HasPrefix(base, "ai-decision-"):
		return "aiDecision"
	case strings.HasPrefix(base, "policy-decision-"):
		return "policyDecision"
	case strings.HasPrefix(base, "release-context-"):
		return "releaseContext"
	default:
		return "unknown"
	}
}
