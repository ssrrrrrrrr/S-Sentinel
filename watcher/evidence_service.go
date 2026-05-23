package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

type EvidenceServiceConfig struct {
	RepoDir   string
	ReportDir string
}

type EvidenceService struct {
	cfg        EvidenceServiceConfig
	runtime    EvidenceRuntime
	repository EvidenceRepository
}

type EvidenceRuntime interface {
	Descriptor() EvidenceRuntimeDescriptor
	Mode() string
	DBFile() string
	ScriptFile() string
	PythonBin() string
	RefreshStateFile() string
	EnsureDBReady() (string, error)
	Run(ctx context.Context, args ...string) ([]byte, error)
}

type EvidenceRuntimeDescriptor struct {
	RuntimeID                   string `json:"runtimeId"`
	RuntimeType                 string `json:"runtimeType"`
	Mode                        string `json:"mode"`
	LegacyMode                  string `json:"legacyMode,omitempty"`
	Backend                     string `json:"backend"`
	Adapter                     string `json:"adapter"`
	Storage                     string `json:"storage"`
	QueryModel                  string `json:"queryModel"`
	ContractVersion             string `json:"contractVersion"`
	ReadOnly                    bool   `json:"readOnly"`
	WillExecute                 bool   `json:"willExecute"`
	SupportsRefresh             bool   `json:"supportsRefresh"`
	SupportsSearch              bool   `json:"supportsSearch"`
	SupportsGraph               bool   `json:"supportsGraph"`
	SupportsVerificationSummary bool   `json:"supportsVerificationSummary"`
	SupportsNativeSQLite        bool   `json:"supportsNativeSQLite"`
	SupportsRemoteAPI           bool   `json:"supportsRemoteApi"`
	Description                 string `json:"description"`
}

func NewEvidenceService(cfg Config, reportDir string) *EvidenceService {
	runtime := NewCLIEvidenceRuntime(cfg.RepoDir)

	return &EvidenceService{
		cfg: EvidenceServiceConfig{
			RepoDir:   cfg.RepoDir,
			ReportDir: reportDir,
		},
		runtime:    runtime,
		repository: NewEvidenceRepositoryForRuntime(runtime),
	}
}

func (api *portalAPI) evidenceService() *EvidenceService {
	return NewEvidenceService(api.cfg, api.reportDir)
}

func (api *portalAPI) evidenceRepository() EvidenceRepository {
	return api.evidenceService().Repository()
}

func (svc *EvidenceService) Repository() EvidenceRepository {
	return svc.repository
}

func (svc *EvidenceService) DBFile() string {
	return svc.runtime.DBFile()
}

func (svc *EvidenceService) ScriptFile() string {
	return svc.runtime.ScriptFile()
}

func (svc *EvidenceService) PythonBin() string {
	return svc.runtime.PythonBin()
}

func (svc *EvidenceService) RefreshStateFile() string {
	return svc.runtime.RefreshStateFile()
}

func (svc *EvidenceService) serviceContract() map[string]interface{} {
	return map[string]interface{}{
		"name":                  "s-sentinel-evidence-api",
		"schemaVersion":         "evidence.service/v1alpha1",
		"contractVersion":       "evidence.api.service/v1alpha1",
		"role":                  "release-evidence-control-plane",
		"readOnly":              true,
		"willExecute":           false,
		"doesNotModifyCluster":  true,
		"doesNotModifyGitOps":   true,
		"doesNotTriggerRollout": true,
	}
}

func (svc *EvidenceService) runtimePaths() map[string]interface{} {
	return map[string]interface{}{
		"repoDir":          svc.cfg.RepoDir,
		"reportDir":        svc.cfg.ReportDir,
		"dbFile":           svc.runtime.DBFile(),
		"scriptFile":       svc.runtime.ScriptFile(),
		"refreshStateFile": svc.runtime.RefreshStateFile(),
	}
}

func (svc *EvidenceService) capabilities() map[string]interface{} {
	return map[string]interface{}{
		"readOnly":                  true,
		"willExecute":               false,
		"refresh":                   true,
		"listReleases":              true,
		"getRelease":                true,
		"getObject":                 true,
		"listArtifacts":             true,
		"search":                    true,
		"verificationSummary":       true,
		"graph":                     true,
		"nativeSQLiteRepository":    false,
		"remoteEvidenceAPI":         false,
		"backgroundRefreshWorker":   false,
		"localEvidenceIndexRefresh": true,
		"policyRuntimeConsumer":     true,
		"signedGateConsumer":        true,
		"agentTraceConsumer":        true,
	}
}

func (svc *EvidenceService) ControlPlaneMetadata(response *EvidenceRepositoryResponse) map[string]interface{} {
	return svc.ControlPlaneMetadataForOperation(response, "query", false)
}

func (svc *EvidenceService) ControlPlaneMetadataForOperation(
	response *EvidenceRepositoryResponse,
	operation string,
	mutatesLocalEvidenceIndex bool,
) map[string]interface{} {
	runtimeDescriptor := svc.runtime.Descriptor()
	repositoryDescriptor := svc.repository.Descriptor()
	dbFile := svc.runtime.DBFile()

	if response != nil {
		if response.Runtime.RuntimeID != "" {
			runtimeDescriptor = response.Runtime
		}
		if response.Repository.RepositoryID != "" {
			repositoryDescriptor = response.Repository
		}
		if response.DBFile != "" {
			dbFile = response.DBFile
		}
	}

	return map[string]interface{}{
		"schemaVersion":             "evidence.api.controlPlane/v1alpha1",
		"apiVersion":                "s-sentinel.io/evidence-api/v1alpha1",
		"contractVersion":           "evidence.api.response/v1alpha1",
		"generatedAt":               time.Now().Format(time.RFC3339),
		"generatedBy":               "s-sentinel-evidence-api",
		"operation":                 operation,
		"service":                   svc.serviceContract(),
		"runtime":                   runtimeDescriptor,
		"repository":                repositoryDescriptor,
		"paths":                     svc.runtimePaths(),
		"capabilities":              svc.capabilities(),
		"dbFile":                    dbFile,
		"runtimeMode":               runtimeDescriptor.Mode,
		"repositoryType":            repositoryDescriptor.RepositoryType,
		"repositoryMode":            repositoryDescriptor.Mode,
		"repositoryContract":        repositoryDescriptor.ContractVersion,
		"readOnly":                  true,
		"willExecute":               false,
		"doesNotModifyCluster":      true,
		"doesNotModifyGitOps":       true,
		"doesNotTriggerRollout":     true,
		"mutatesLocalEvidenceIndex": mutatesLocalEvidenceIndex,
		"mutationSemantics": map[string]interface{}{
			"doesNotModifyCluster":      true,
			"doesNotModifyGitOps":       true,
			"doesNotTriggerRollout":     true,
			"mutatesLocalEvidenceIndex": mutatesLocalEvidenceIndex,
		},
	}
}

func (svc *EvidenceService) Status(ctx context.Context) map[string]interface{} {
	dbFile := svc.runtime.DBFile()
	scriptFile := svc.runtime.ScriptFile()
	refreshStateFile := svc.runtime.RefreshStateFile()
	descriptor := svc.runtime.Descriptor()
	repositoryDescriptor := svc.repository.Descriptor()

	body := map[string]interface{}{
		"schemaVersion":             "evidence.store.status/v1alpha1",
		"generatedAt":               time.Now().Format(time.RFC3339),
		"mode":                      descriptor.Mode,
		"legacyMode":                descriptor.LegacyMode,
		"service":                   svc.serviceContract(),
		"runtime":                   descriptor,
		"repository":                repositoryDescriptor,
		"paths":                     svc.runtimePaths(),
		"capabilities":              svc.capabilities(),
		"controlPlane":              svc.ControlPlaneMetadataForOperation(nil, "status", false),
		"readOnly":                  true,
		"willExecute":               false,
		"doesNotModifyCluster":      true,
		"doesNotModifyGitOps":       true,
		"doesNotTriggerRollout":     true,
		"mutatesLocalEvidenceIndex": false,
		"repoDir":                   svc.cfg.RepoDir,
		"reportDir":                 svc.cfg.ReportDir,
		"dbFile":                    dbFile,
		"scriptFile":                scriptFile,
		"pythonRuntime":             svc.runtime.PythonBin(),
		"refreshStateFile":          refreshStateFile,
		"ready":                     false,
	}

	if refreshState, ok, err := svc.readRefreshState(); err != nil {
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

	if info, err := os.Stat(svc.cfg.ReportDir); err == nil {
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

		output, queryErr := svc.runtime.Run(ctx, "list-releases", "--db", dbFile, "--limit", "500")
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

	return body
}

func (svc *EvidenceService) Refresh(ctx context.Context) (map[string]interface{}, error) {
	dbFile := svc.runtime.DBFile()
	descriptor := svc.runtime.Descriptor()
	repositoryDescriptor := svc.repository.Descriptor()

	initOutput, err := svc.runtime.Run(ctx, "init-db", "--db", dbFile)
	if err != nil {
		return nil, fmt.Errorf("failed to initialize evidence store: %w", err)
	}

	importOutput, err := svc.runtime.Run(ctx, "import-dir", "--db", dbFile, "--report-dir", svc.cfg.ReportDir)
	if err != nil {
		return nil, fmt.Errorf("failed to import evidence store: %w", err)
	}

	listOutput, err := svc.runtime.Run(ctx, "list-releases", "--db", dbFile, "--limit", "1")
	if err != nil {
		return nil, fmt.Errorf("failed to list evidence store releases: %w", err)
	}

	refreshResult := map[string]interface{}{
		"schemaVersion":             "evidence.store.refresh/v1alpha1",
		"generatedAt":               time.Now().Format(time.RFC3339),
		"mode":                      descriptor.Mode,
		"legacyMode":                descriptor.LegacyMode,
		"service":                   svc.serviceContract(),
		"runtime":                   descriptor,
		"repository":                repositoryDescriptor,
		"paths":                     svc.runtimePaths(),
		"capabilities":              svc.capabilities(),
		"controlPlane":              svc.ControlPlaneMetadataForOperation(nil, "refresh", true),
		"readOnly":                  true,
		"willExecute":               false,
		"doesNotModifyCluster":      true,
		"doesNotModifyGitOps":       true,
		"doesNotTriggerRollout":     true,
		"mutatesLocalEvidenceIndex": true,
		"repoDir":                   svc.cfg.RepoDir,
		"reportDir":                 svc.cfg.ReportDir,
		"dbFile":                    dbFile,
		"refreshStateFile":          svc.runtime.RefreshStateFile(),
		"initResult":                decodeEvidenceStoreJSON(initOutput),
		"importResult":              decodeEvidenceStoreJSON(importOutput),
		"releaseList":               decodeEvidenceStoreJSON(listOutput),
	}

	refreshResult["latestRelease"] = latestEvidenceStoreRelease(refreshResult["releaseList"].(map[string]interface{}))

	if err := svc.writeRefreshState(refreshResult); err != nil {
		refreshResult["refreshStateError"] = err.Error()
	}

	return refreshResult, nil
}

func (svc *EvidenceService) writeRefreshState(state map[string]interface{}) error {
	stateFile := svc.runtime.RefreshStateFile()

	if err := os.MkdirAll(filepath.Dir(stateFile), 0755); err != nil {
		return err
	}

	data, err := json.MarshalIndent(state, "", "  ")
	if err != nil {
		return err
	}

	return os.WriteFile(stateFile, data, 0644)
}

func (svc *EvidenceService) readRefreshState() (map[string]interface{}, bool, error) {
	stateFile := svc.runtime.RefreshStateFile()

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

type CLIEvidenceRuntime struct {
	repoDir string
}

func NewCLIEvidenceRuntime(repoDir string) *CLIEvidenceRuntime {
	return &CLIEvidenceRuntime{
		repoDir: repoDir,
	}
}

func (runtime *CLIEvidenceRuntime) Descriptor() EvidenceRuntimeDescriptor {
	return EvidenceRuntimeDescriptor{
		RuntimeID:                   "cli-sqlite",
		RuntimeType:                 "cli-backed-sqlite",
		Mode:                        "cli-sqlite-runtime",
		LegacyMode:                  "sqlite-adapter",
		Backend:                     "sqlite",
		Adapter:                     "python-cli",
		Storage:                     "local-file",
		QueryModel:                  "read-through-cli",
		ContractVersion:             "evidence.runtime/v1alpha1",
		ReadOnly:                    true,
		WillExecute:                 false,
		SupportsRefresh:             true,
		SupportsSearch:              true,
		SupportsGraph:               true,
		SupportsVerificationSummary: true,
		SupportsNativeSQLite:        false,
		SupportsRemoteAPI:           false,
		Description:                 "Compatibility runtime that serves Evidence API queries through scripts/evidence-store.py and a local SQLite index.",
	}
}

func (runtime *CLIEvidenceRuntime) Mode() string {
	return runtime.Descriptor().Mode
}

func (runtime *CLIEvidenceRuntime) DBFile() string {
	if dbFile := strings.TrimSpace(os.Getenv("S_SENTINEL_EVIDENCE_STORE_DB")); dbFile != "" {
		return dbFile
	}

	return filepath.Join(os.TempDir(), "s-sentinel-evidence-store", "portal-evidence-store.db")
}

func (runtime *CLIEvidenceRuntime) ScriptFile() string {
	if scriptFile := strings.TrimSpace(os.Getenv("S_SENTINEL_EVIDENCE_STORE_SCRIPT")); scriptFile != "" {
		return scriptFile
	}

	return filepath.Join(runtime.repoDir, "scripts", "evidence-store.py")
}

func (runtime *CLIEvidenceRuntime) PythonBin() string {
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

func (runtime *CLIEvidenceRuntime) RefreshStateFile() string {
	dbFile := runtime.DBFile()
	ext := filepath.Ext(dbFile)
	if ext == "" {
		return dbFile + "-refresh.json"
	}

	return strings.TrimSuffix(dbFile, ext) + "-refresh.json"
}

func (runtime *CLIEvidenceRuntime) EnsureDBReady() (string, error) {
	dbFile := runtime.DBFile()

	if _, err := os.Stat(dbFile); err != nil {
		if os.IsNotExist(err) {
			return "", fmt.Errorf("evidence store db is not initialized: %s; call POST /api/evidence-store/refresh first", dbFile)
		}

		return "", fmt.Errorf("failed to inspect evidence store db: %s: %w", dbFile, err)
	}

	return dbFile, nil
}

func (runtime *CLIEvidenceRuntime) Run(ctx context.Context, args ...string) ([]byte, error) {
	scriptFile := runtime.ScriptFile()
	if _, err := os.Stat(scriptFile); err != nil {
		return nil, fmt.Errorf("evidence store script unavailable: %s: %w", scriptFile, err)
	}

	commandArgs := append([]string{scriptFile}, args...)
	cmd := exec.CommandContext(ctx, runtime.PythonBin(), commandArgs...)
	cmd.Dir = runtime.repoDir

	var stdout bytes.Buffer
	var stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	if err := cmd.Run(); err != nil {
		return stdout.Bytes(), fmt.Errorf("evidence store command failed: %w: %s", err, strings.TrimSpace(stderr.String()))
	}

	return stdout.Bytes(), nil
}
