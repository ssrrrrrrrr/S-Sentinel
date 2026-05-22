package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"os/exec"
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

	mux.HandleFunc("/api/evidence-store/status", api.handleEvidenceStoreStatus)
	mux.HandleFunc("/api/evidence-store/refresh", api.handleEvidenceStoreRefresh)

	mux.HandleFunc("/api/evidence-store/releases", api.handleEvidenceStoreReleaseList)
	mux.HandleFunc("/api/evidence-store/releases/", api.handleEvidenceStoreReleaseDetail)
	mux.HandleFunc("/api/evidence-store/objects/", api.handleEvidenceStoreObjectDetail)
	mux.HandleFunc("/api/releases/latest/evidence", api.handleLatestResource("releaseEvidence"))
	mux.HandleFunc("/api/releases/latest/evidence-record", api.handleLatestResource("evidenceRecord"))
	mux.HandleFunc("/api/releases/latest/summary", api.handleLatestResource("releaseSummary"))
	mux.HandleFunc("/api/releases/latest/action-plan", api.handleLatestResource("actionPlan"))
	mux.HandleFunc("/api/releases/latest/intelligence", api.handleLatestResource("releaseIntelligence"))
	mux.HandleFunc("/api/releases/latest/approval", api.handleLatestResource("approvalRecord"))
	mux.HandleFunc("/api/releases/latest/failure-evidence", api.handleLatestResource("failureEvidence"))
	mux.HandleFunc("/api/releases/latest/advice", api.handleLatestResource("aiAdvice"))
	mux.HandleFunc("/api/releases/latest/memory", api.handleLatestResource("releaseMemory"))
	mux.HandleFunc("/api/releases/latest/timeline", api.handleLatestResource("releaseTimeline"))
	mux.HandleFunc("/api/releases/latest/runbook", api.handleLatestResource("runbook"))
	mux.HandleFunc("/api/releases/latest/rca", api.handleLatestResource("rca"))
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
			Name:         "evidenceRecord",
			Endpoint:     "/api/releases/latest/evidence-record",
			Candidates:   []string{"evidence-record-latest.json"},
			FallbackGlob: "evidence-record-*.json",
			ContentType:  "application/json; charset=utf-8",
			Description:  "Latest evidence control-plane record.",
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
			Name:         "releaseTimeline",
			Endpoint:     "/api/releases/latest/timeline",
			Candidates:   []string{"release-timeline-latest.json"},
			FallbackGlob: "release-timeline-*.json",
			ContentType:  "application/json; charset=utf-8",
			Description:  "Latest release evidence timeline.",
		},
		{
			Name:         "runbook",
			Endpoint:     "/api/releases/latest/runbook",
			Candidates:   []string{"runbook-latest.md"},
			FallbackGlob: "runbook-*.md",
			ContentType:  "text/markdown; charset=utf-8",
			Description:  "Latest operator runbook markdown.",
		},
		{
			Name:         "rca",
			Endpoint:     "/api/releases/latest/rca",
			Candidates:   []string{"rca-latest.md"},
			FallbackGlob: "rca-*.md",
			ContentType:  "text/markdown; charset=utf-8",
			Description:  "Latest release RCA markdown.",
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

func (api *portalAPI) handleEvidenceStoreStatus(w http.ResponseWriter, r *http.Request) {
	if !api.requireGET(w, r) {
		return
	}

	dbFile := api.evidenceStoreDBFile()
	scriptFile := api.evidenceStoreScriptFile()
	refreshStateFile := api.evidenceStoreRefreshStateFile()

	body := map[string]interface{}{
		"schemaVersion":    "evidence.store.status/v1alpha1",
		"generatedAt":      time.Now().Format(time.RFC3339),
		"mode":             "sqlite-adapter",
		"readOnly":         true,
		"willExecute":      false,
		"repoDir":          api.cfg.RepoDir,
		"reportDir":        api.reportDir,
		"dbFile":           dbFile,
		"scriptFile":       scriptFile,
		"pythonRuntime":    api.evidenceStorePythonBin(),
		"refreshStateFile": refreshStateFile,
		"ready":            false,
	}

	if refreshState, ok, err := api.readEvidenceStoreRefreshState(); err != nil {
		body["refreshStateError"] = err.Error()
	} else if ok {
		body["lastRefresh"] = refreshState

		if importResult, ok := refreshState["importResult"].(map[string]interface{}); ok {
			body["lastImportResult"] = importResult
		}

		if generatedAt, ok := refreshState["generatedAt"].(string); ok {
			body["lastRefreshAt"] = generatedAt
		}
	}

	if info, err := os.Stat(api.reportDir); err == nil {
		body["reportDirExists"] = true
		body["reportDirModifiedAt"] = info.ModTime().Format(time.RFC3339)
	} else {
		body["reportDirExists"] = false
		body["reportDirError"] = err.Error()
	}

	if info, err := os.Stat(scriptFile); err == nil {
		body["scriptExists"] = true
		body["scriptModifiedAt"] = info.ModTime().Format(time.RFC3339)
	} else {
		body["scriptExists"] = false
		body["scriptError"] = err.Error()
	}

	if info, err := os.Stat(dbFile); err == nil {
		body["dbExists"] = true
		body["dbSizeBytes"] = info.Size()
		body["dbModifiedAt"] = info.ModTime().Format(time.RFC3339)

		output, queryErr := api.runEvidenceStoreCommand(r, "list-releases", "--db", dbFile, "--limit", "500")
		if queryErr != nil {
			body["queryError"] = queryErr.Error()
		} else {
			listResult := decodeEvidenceStoreJSON(output)
			body["releaseList"] = listResult
			body["latestRelease"] = latestEvidenceStoreRelease(listResult)
			body["ready"] = true
		}
	} else {
		body["dbExists"] = false
		body["dbError"] = err.Error()
		body["hint"] = "Call POST /api/evidence-store/refresh to initialize and import the SQLite index."
	}

	writePortalJSON(w, http.StatusOK, body)
}

func (api *portalAPI) handleEvidenceStoreRefresh(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writePortalJSON(w, http.StatusMethodNotAllowed, map[string]interface{}{
			"schemaVersion": "evidence.store.refresh.error/v1alpha1",
			"generatedAt":   time.Now().Format(time.RFC3339),
			"error":         "method not allowed",
			"allowedMethod": "POST",
			"readOnly":      true,
			"willExecute":   false,
		})
		return
	}

	dbFile := api.evidenceStoreDBFile()

	initOutput, err := api.runEvidenceStoreCommand(r, "init-db", "--db", dbFile)
	if err != nil {
		api.writeEvidenceStoreError(w, http.StatusInternalServerError, "failed to initialize evidence store", err)
		return
	}

	importOutput, err := api.runEvidenceStoreCommand(r, "import-dir", "--db", dbFile, "--report-dir", api.reportDir)
	if err != nil {
		api.writeEvidenceStoreError(w, http.StatusInternalServerError, "failed to import evidence store", err)
		return
	}

	listOutput, err := api.runEvidenceStoreCommand(r, "list-releases", "--db", dbFile, "--limit", "1")
	if err != nil {
		api.writeEvidenceStoreError(w, http.StatusInternalServerError, "failed to list evidence store releases", err)
		return
	}

	generatedAt := time.Now().Format(time.RFC3339)
	initResult := decodeEvidenceStoreJSON(initOutput)
	importResult := decodeEvidenceStoreJSON(importOutput)
	listResult := decodeEvidenceStoreJSON(listOutput)
	latestRelease := latestEvidenceStoreRelease(listResult)

	refreshResult := map[string]interface{}{
		"schemaVersion":    "evidence.store.refresh/v1alpha1",
		"generatedAt":      generatedAt,
		"mode":             "sqlite-adapter",
		"readOnly":         true,
		"willExecute":      false,
		"repoDir":          api.cfg.RepoDir,
		"reportDir":        api.reportDir,
		"dbFile":           dbFile,
		"refreshStateFile": api.evidenceStoreRefreshStateFile(),
		"initResult":       initResult,
		"importResult":     importResult,
		"releaseList":      listResult,
		"latestRelease":    latestRelease,
	}

	if err := api.writeEvidenceStoreRefreshState(refreshResult); err != nil {
		refreshResult["refreshStateError"] = err.Error()
	}

	writePortalJSON(w, http.StatusOK, refreshResult)
}

func decodeEvidenceStoreJSON(data []byte) map[string]interface{} {
	result := map[string]interface{}{}
	if err := json.Unmarshal(data, &result); err != nil {
		return map[string]interface{}{
			"decodeError": err.Error(),
			"raw":         strings.TrimSpace(string(data)),
		}
	}

	return result
}

func latestEvidenceStoreRelease(listResult map[string]interface{}) map[string]interface{} {
	items, ok := listResult["items"].([]interface{})
	if !ok || len(items) == 0 {
		return nil
	}

	item, ok := items[0].(map[string]interface{})
	if !ok {
		return nil
	}

	return item
}

func (api *portalAPI) handleEvidenceStoreReleaseList(w http.ResponseWriter, r *http.Request) {
	if !api.requireGET(w, r) {
		return
	}

	query := r.URL.Query()
	api.writeEvidenceRepositoryResponse(w, r, func(repository EvidenceRepository) (*EvidenceRepositoryResponse, error) {
		return repository.ListReleases(r, EvidenceReleaseListQuery{
			Limit:         query.Get("limit"),
			Service:       query.Get("service"),
			Env:           query.Get("env"),
			ReleaseResult: query.Get("releaseResult"),
		})
	})
}

func (api *portalAPI) handleEvidenceStoreReleaseDetail(w http.ResponseWriter, r *http.Request) {
	if !api.requireGET(w, r) {
		return
	}

	releaseID := strings.Trim(strings.TrimPrefix(r.URL.Path, "/api/evidence-store/releases/"), "/")
	if releaseID == "" || strings.Contains(releaseID, "/") {
		writePortalJSON(w, http.StatusNotFound, map[string]interface{}{
			"error": "evidence store release not found",
			"path":  r.URL.Path,
		})
		return
	}

	api.writeEvidenceRepositoryResponse(w, r, func(repository EvidenceRepository) (*EvidenceRepositoryResponse, error) {
		return repository.GetRelease(r, EvidenceReleaseQuery{
			ReleaseID:  releaseID,
			IncludeRaw: strings.EqualFold(strings.TrimSpace(r.URL.Query().Get("includeRaw")), "true"),
		})
	})
}

func (api *portalAPI) handleEvidenceStoreObjectDetail(w http.ResponseWriter, r *http.Request) {
	if !api.requireGET(w, r) {
		return
	}

	rest := strings.Trim(strings.TrimPrefix(r.URL.Path, "/api/evidence-store/objects/"), "/")
	parts := strings.Split(rest, "/")
	if len(parts) != 2 || strings.TrimSpace(parts[0]) == "" || strings.TrimSpace(parts[1]) == "" {
		writePortalJSON(w, http.StatusNotFound, map[string]interface{}{
			"error": "evidence store object not found",
			"path":  r.URL.Path,
		})
		return
	}

	api.writeEvidenceRepositoryResponse(w, r, func(repository EvidenceRepository) (*EvidenceRepositoryResponse, error) {
		return repository.GetObject(r, EvidenceObjectQuery{
			ObjectType: strings.TrimSpace(parts[0]),
			ObjectID:   strings.TrimSpace(parts[1]),
			ReleaseID:  r.URL.Query().Get("releaseId"),
			IncludeRaw: strings.EqualFold(strings.TrimSpace(r.URL.Query().Get("includeRaw")), "true"),
		})
	})
}

func (api *portalAPI) writeEvidenceRepositoryResponse(
	w http.ResponseWriter,
	r *http.Request,
	query func(repository EvidenceRepository) (*EvidenceRepositoryResponse, error),
) {
	response, err := query(api.evidenceRepository())
	if err != nil {
		if repositoryErr, ok := err.(*EvidenceRepositoryError); ok {
			api.writeEvidenceStoreError(w, repositoryErr.StatusCode, repositoryErr.Message, repositoryErr.Err)
			return
		}

		api.writeEvidenceStoreError(w, http.StatusInternalServerError, "failed to query evidence store", err)
		return
	}

	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Header().Set("X-S-Sentinel-Evidence-Store-Mode", response.Mode)
	w.Header().Set("X-S-Sentinel-Evidence-Store-DB", response.DBFile)
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write(response.Body)
}

func (api *portalAPI) ensureEvidenceStoreDBReady() (string, error) {
	dbFile := api.evidenceStoreDBFile()

	if _, err := os.Stat(dbFile); err != nil {
		if os.IsNotExist(err) {
			return "", fmt.Errorf("evidence store db is not initialized: %s; call POST /api/evidence-store/refresh first", dbFile)
		}

		return "", fmt.Errorf("failed to inspect evidence store db: %s: %w", dbFile, err)
	}

	return dbFile, nil
}

func (api *portalAPI) runEvidenceStoreCommand(r *http.Request, args ...string) ([]byte, error) {
	scriptFile := api.evidenceStoreScriptFile()
	if _, err := os.Stat(scriptFile); err != nil {
		return nil, fmt.Errorf("evidence store script unavailable: %s: %w", scriptFile, err)
	}

	commandArgs := append([]string{scriptFile}, args...)
	cmd := exec.CommandContext(r.Context(), api.evidenceStorePythonBin(), commandArgs...)
	cmd.Dir = api.cfg.RepoDir

	var stdout bytes.Buffer
	var stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	if err := cmd.Run(); err != nil {
		return stdout.Bytes(), fmt.Errorf("evidence store command failed: %w: %s", err, strings.TrimSpace(stderr.String()))
	}

	return stdout.Bytes(), nil
}

func (api *portalAPI) evidenceStoreScriptFile() string {
	if scriptFile := strings.TrimSpace(os.Getenv("S_SENTINEL_EVIDENCE_STORE_SCRIPT")); scriptFile != "" {
		return scriptFile
	}

	return filepath.Join(api.cfg.RepoDir, "scripts", "evidence-store.py")
}

func (api *portalAPI) evidenceStorePythonBin() string {
	if pythonBin := strings.TrimSpace(os.Getenv("S_SENTINEL_PYTHON_BIN")); pythonBin != "" {
		return pythonBin
	}

	if _, err := exec.LookPath("python3"); err == nil {
		return "python3"
	}

	if _, err := exec.LookPath("python"); err == nil {
		return "python"
	}

	return "python3"
}

func (api *portalAPI) evidenceStoreDBFile() string {
	if dbFile := strings.TrimSpace(os.Getenv("S_SENTINEL_EVIDENCE_STORE_DB")); dbFile != "" {
		return dbFile
	}

	return filepath.Join(os.TempDir(), "s-sentinel-evidence-store", "portal-evidence-store.db")
}

func (api *portalAPI) evidenceStoreRefreshStateFile() string {
	dbFile := api.evidenceStoreDBFile()
	ext := filepath.Ext(dbFile)
	if ext == "" {
		return dbFile + "-refresh.json"
	}

	return strings.TrimSuffix(dbFile, ext) + "-refresh.json"
}

func (api *portalAPI) writeEvidenceStoreRefreshState(state map[string]interface{}) error {
	stateFile := api.evidenceStoreRefreshStateFile()

	if err := os.MkdirAll(filepath.Dir(stateFile), 0755); err != nil {
		return err
	}

	data, err := json.MarshalIndent(state, "", "  ")
	if err != nil {
		return err
	}

	return os.WriteFile(stateFile, data, 0644)
}

func (api *portalAPI) readEvidenceStoreRefreshState() (map[string]interface{}, bool, error) {
	stateFile := api.evidenceStoreRefreshStateFile()

	data, err := os.ReadFile(stateFile)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, false, nil
		}

		return nil, false, err
	}

	state := map[string]interface{}{}
	if err := json.Unmarshal(data, &state); err != nil {
		return nil, false, err
	}

	return state, true, nil
}

func (api *portalAPI) writeEvidenceStoreError(w http.ResponseWriter, statusCode int, message string, err error) {
	body := map[string]interface{}{
		"schemaVersion": "evidence.store.adapter.error/v1alpha1",
		"generatedAt":   time.Now().Format(time.RFC3339),
		"error":         message,
		"readOnly":      true,
		"willExecute":   false,
	}

	if err != nil {
		body["detail"] = err.Error()
	}

	writePortalJSON(w, statusCode, body)
}

func (api *portalAPI) handleLatestIndex(w http.ResponseWriter, r *http.Request) {
	if !api.requireGET(w, r) {
		return
	}

	resources := map[string]portalResourceStatus{}
	endpoints := []string{
		"/api/releases",
		"/api/releases/latest",
		"/api/evidence-store/releases",
		"/api/evidence-store/releases/{releaseId}",
		"/api/evidence-store/objects/{objectType}/{objectId}",
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

	rest := strings.TrimPrefix(r.URL.Path, "/api/releases/")
	rest = strings.Trim(rest, "/")

	if rest == "" {
		writePortalJSON(w, http.StatusNotFound, map[string]interface{}{
			"error": "release not found",
			"path":  r.URL.Path,
		})
		return
	}

	parts := strings.Split(rest, "/")
	if len(parts) != 1 && len(parts) != 2 {
		writePortalJSON(w, http.StatusNotFound, map[string]interface{}{
			"error": "release resource not found",
			"path":  r.URL.Path,
		})
		return
	}

	releaseID := strings.TrimSpace(parts[0])
	if releaseID == "" {
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

	if len(parts) == 2 {
		api.handleReleaseResourceContent(w, releaseID, group, strings.TrimSpace(parts[1]))
		return
	}

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

func (api *portalAPI) handleReleaseResourceContent(w http.ResponseWriter, releaseID string, group *portalReleaseGroup, resourceName string) {
	kind, contentType, ok := portalResourceKindFromPathSegment(resourceName)
	if !ok {
		writePortalJSON(w, http.StatusNotFound, map[string]interface{}{
			"error":              "unknown release resource",
			"releaseId":          releaseID,
			"resource":           resourceName,
			"availableResources": availablePortalResourceNames(group),
		})
		return
	}

	resource, ok := group.Resources[kind]
	if !ok && kind == "releaseTimeline" {
		timelineFile := filepath.Join(api.reportDir, "release-timeline-"+releaseID+".json")
		if info, err := os.Stat(timelineFile); err == nil && !info.IsDir() {
			resource = portalReleaseResource{
				Kind:         kind,
				File:         timelineFile,
				BaseName:     filepath.Base(timelineFile),
				ReleaseID:    releaseID,
				SizeBytes:    info.Size(),
				ModifiedAt:   info.ModTime().Format(time.RFC3339),
				ModifiedUnix: info.ModTime().Unix(),
			}
			ok = true
		}
	}

	if !ok {
		writePortalJSON(w, http.StatusNotFound, map[string]interface{}{
			"error":              "release resource not found",
			"releaseId":          releaseID,
			"resource":           resourceName,
			"kind":               kind,
			"availableResources": availablePortalResourceNames(group),
		})
		return
	}

	data, err := os.ReadFile(resource.File)
	if err != nil {
		writePortalJSON(w, http.StatusInternalServerError, map[string]interface{}{
			"error":     err.Error(),
			"releaseId": releaseID,
			"resource":  resourceName,
			"file":      resource.File,
		})
		return
	}

	w.Header().Set("Content-Type", contentType)
	w.Header().Set("X-Release-Portal-Release-ID", releaseID)
	w.Header().Set("X-Release-Portal-Resource", kind)
	w.Header().Set("X-Release-Portal-File", resource.BaseName)
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write(data)
}

func portalResourceKindFromPathSegment(resourceName string) (string, string, bool) {
	switch resourceName {
	case "evidence":
		return "releaseEvidence", "application/json; charset=utf-8", true
	case "evidence-record":
		return "evidenceRecord", "application/json; charset=utf-8", true
	case "summary":
		return "releaseSummary", "text/markdown; charset=utf-8", true
	case "action-plan":
		return "actionPlan", "application/json; charset=utf-8", true
	case "intelligence":
		return "releaseIntelligence", "application/json; charset=utf-8", true
	case "approval":
		return "approvalRecord", "application/json; charset=utf-8", true
	case "failure-evidence":
		return "failureEvidence", "application/json; charset=utf-8", true
	case "advice":
		return "aiAdvice", "text/markdown; charset=utf-8", true
	case "ai-decision":
		return "aiDecision", "application/json; charset=utf-8", true
	case "policy-decision":
		return "policyDecision", "application/json; charset=utf-8", true
	case "context":
		return "releaseContext", "application/json; charset=utf-8", true
	case "timeline":
		return "releaseTimeline", "application/json; charset=utf-8", true
	case "runbook":
		return "runbook", "text/markdown; charset=utf-8", true
	case "rca":
		return "rca", "text/markdown; charset=utf-8", true
	default:
		return "", "", false
	}
}

func availablePortalResourceNames(group *portalReleaseGroup) []string {
	if group == nil {
		return []string{}
	}

	resourceByKind := map[string]string{
		"releaseEvidence":     "evidence",
		"evidenceRecord":      "evidence-record",
		"releaseSummary":      "summary",
		"actionPlan":          "action-plan",
		"releaseIntelligence": "intelligence",
		"approvalRecord":      "approval",
		"failureEvidence":     "failure-evidence",
		"aiAdvice":            "advice",
		"aiDecision":          "ai-decision",
		"policyDecision":      "policy-decision",
		"releaseContext":      "context",
		"releaseTimeline":     "timeline",
		"runbook":             "runbook",
		"rca":                 "rca",
	}

	names := []string{}
	for kind := range group.Resources {
		if name, ok := resourceByKind[kind]; ok {
			names = append(names, name)
		}
	}

	sort.Strings(names)
	return names
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
		"release-timeline-*.json",
		"runbook-*.md",
		"rca-*.md",
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
		"evidence-record-",
		"release-summary-",
		"action-plan-",
		"release-intelligence-",
		"approval-record-",
		"failure-evidence-",
		"ai-advice-",
		"ai-decision-",
		"policy-decision-",
		"release-context-",
		"release-timeline-",
		"runbook-",
		"rca-",
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
	case strings.HasPrefix(base, "evidence-record-"):
		return "evidenceRecord"
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
	case strings.HasPrefix(base, "release-timeline-"):
		return "releaseTimeline"
	case strings.HasPrefix(base, "runbook-"):
		return "runbook"
	case strings.HasPrefix(base, "rca-"):
		return "rca"
	default:
		return "unknown"
	}
}
