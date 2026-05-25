package main

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
)

func TestPortalExecutionAPIContract(t *testing.T) {
	api, releaseID := newExecutionContractAPI(t)

	statusBody := callPortalExecutionHandler(
		t,
		api.handleExecutionStatus,
		http.MethodGet,
		"/api/execution/status",
		http.StatusOK,
	)
	assertPortalSchema(t, statusBody, "execution.noop.status/v1alpha1")
	assertPortalBool(t, statusBody, "readOnly", true)
	assertPortalBool(t, statusBody, "willExecute", false)
	assertPortalBool(t, statusBody, "doesNotModifyCluster", true)
	assertPortalBool(t, statusBody, "doesNotModifyGitOps", true)
	assertPortalBool(t, statusBody, "doesNotTriggerRollout", true)
	assertPortalBool(t, statusBody, "mutatesLocalEvidenceFiles", false)
	assertPortalNestedString(t, statusBody, "runtime", "mode", "noop-executor-runtime")
	assertPortalNestedString(t, statusBody, "controlPlane", "apiVersion", "s-sentinel.io/execution-api/v1alpha1")

	latestErrorBody := callPortalExecutionHandler(
		t,
		api.handleExecutionLatest,
		http.MethodGet,
		"/api/execution/latest",
		http.StatusNotFound,
	)
	assertPortalSchema(t, latestErrorBody, "execution.noop.latest.error/v1alpha1")

	methodErrorBody := callPortalExecutionHandler(
		t,
		api.handleExecutionNoop,
		http.MethodGet,
		"/api/execution/noop",
		http.StatusMethodNotAllowed,
	)
	assertPortalSchema(t, methodErrorBody, "execution.noop.run.error/v1alpha1")
	assertPortalBool(t, methodErrorBody, "mutatesLocalEvidenceFiles", true)

	runBody := callPortalExecutionHandler(
		t,
		api.handleExecutionNoop,
		http.MethodPost,
		"/api/execution/noop?releaseId="+releaseID,
		http.StatusOK,
	)
	assertPortalSchema(t, runBody, "execution.noop.run/v1alpha1")
	assertPortalBool(t, runBody, "readOnly", false)
	assertPortalBool(t, runBody, "willExecute", false)
	assertPortalBool(t, runBody, "doesNotModifyCluster", true)
	assertPortalBool(t, runBody, "doesNotModifyGitOps", true)
	assertPortalBool(t, runBody, "doesNotTriggerRollout", true)
	assertPortalBool(t, runBody, "mutatesLocalEvidenceFiles", true)
	assertPortalNestedString(t, runBody, "controlPlane", "operation", "noop")
	assertPortalNestedString(t, runBody, "executionResult", "executionResultId", "xr-"+releaseID)

	latestBody := callPortalExecutionHandler(
		t,
		api.handleExecutionLatest,
		http.MethodGet,
		"/api/execution/latest",
		http.StatusOK,
	)
	assertPortalSchema(t, latestBody, "execution.noop.latest/v1alpha1")
	assertPortalBool(t, latestBody, "readOnly", true)
	assertPortalNestedString(t, latestBody, "executionResult", "executionResultId", "xr-"+releaseID)
	assertPortalNestedString(t, latestBody, "executionResult", "mode", "noop_executor_result")

	statusAfterRunBody := callPortalExecutionHandler(
		t,
		api.handleExecutionStatus,
		http.MethodGet,
		"/api/execution/status",
		http.StatusOK,
	)
	assertPortalSchema(t, statusAfterRunBody, "execution.noop.status/v1alpha1")
	assertPortalStringNotEmpty(t, statusAfterRunBody, "latestExecutionResultFile")
}

func newExecutionContractAPI(t *testing.T) (*portalAPI, string) {
	t.Helper()

	tempRepo := t.TempDir()
	reportDir := filepath.Join(tempRepo, "docs", "release-reports")
	if err := os.MkdirAll(reportDir, 0755); err != nil {
		t.Fatalf("create report dir: %v", err)
	}

	scriptDir := filepath.Join(tempRepo, "scripts")
	if err := os.MkdirAll(scriptDir, 0755); err != nil {
		t.Fatalf("create script dir: %v", err)
	}

	scriptFile := filepath.Join(scriptDir, "run-noop-executor.sh")
	if err := os.WriteFile(scriptFile, []byte("#!/usr/bin/env bash\nexit 0\n"), 0755); err != nil {
		t.Fatalf("write noop executor script: %v", err)
	}

	releaseID := "20260101-050505"
	releaseEvidencePath := filepath.Join(reportDir, "release-evidence-"+releaseID+".json")
	releaseEvidence := map[string]interface{}{
		"schemaVersion":         "release.evidence.bundle/v1alpha1",
		"generatedBy":           "execution_api_contract_test.go",
		"generatedAt":           "2026-01-01T05:05:05Z",
		"releaseId":             releaseID,
		"releaseResult":         "FAIL_BY_MULTIPLE_SLO",
		"policyDecision":        "REQUIRE_HUMAN_APPROVAL",
		"finalAction":           "STOP_PROMOTION",
		"executionMode":         "manual_approval",
		"requiresHumanApproval": true,
		"safeToRetry":           false,
		"service":               "demo-app",
		"namespace":             "slo-rollout",
		"env":                   "dev",
		"summary": map[string]interface{}{
			"riskLevel":          "high",
			"riskScore":          85,
			"rolloutPhase":       "Paused",
			"rolloutAbort":       false,
			"analysisRunPhase":   "Running",
			"matchedPolicyRules": []interface{}{},
			"failedMetrics":      []interface{}{"error-rate"},
		},
		"artifacts": map[string]interface{}{
			"executionPreview": filepath.Join(reportDir, "execution-preview-"+releaseID+".json"),
		},
		"decisionRefs": map[string]interface{}{},
	}
	writeExecutionTestJSON(t, releaseEvidencePath, releaseEvidence)
	writeExecutionTestJSON(t, filepath.Join(reportDir, "execution-preview-"+releaseID+".json"), map[string]interface{}{
		"schemaVersion":      "execution.preview/v1alpha1",
		"executionPreviewId": "ep-" + releaseID,
		"generatedBy":        "execution_api_contract_test.go",
		"generatedAt":        "2026-01-01T05:05:06Z",
		"mode":               "dry_run_execution_preview",
		"release": map[string]interface{}{
			"releaseId":      releaseID,
			"service":        "demo-app",
			"env":            "dev",
			"namespace":      "slo-rollout",
			"policyDecision": "REQUIRE_HUMAN_APPROVAL",
			"finalAction":    "STOP_PROMOTION",
		},
		"inputs": map[string]interface{}{
			"releaseEvidence":      releaseEvidencePath,
			"executionRequest":     nil,
			"executionEligibility": nil,
			"actionPlan":           nil,
			"renderedReleasePlan":  nil,
			"environmentConfig":    nil,
			"supplyChainDecision":  nil,
		},
		"preview": map[string]interface{}{
			"previewStatus":    "WAITING_APPROVAL",
			"readyToExecute":   false,
			"requestedAction":  "STOP_PROMOTION",
			"summary":          "Preview only.",
			"plannedActions":   []interface{}{map[string]interface{}{"actionId": "preview-1", "title": "Inspect rollout", "category": "command_preview", "dryRunOnly": true, "blocked": false, "requiresApproval": true}},
			"blockedActions":   []interface{}{},
			"humanCheckpoints": []interface{}{},
			"gitopsChanges":    []interface{}{},
			"rolloutPlan":      map[string]interface{}{},
		},
		"guardrails": map[string]interface{}{
			"readOnly":                true,
			"dryRunOnly":              true,
			"willExecute":             false,
			"doesNotModifyKubernetes": true,
			"doesNotModifyGitOps":     true,
			"doesNotRollback":         true,
			"doesNotPromote":          true,
			"doesNotPatchResources":   true,
			"doesNotDeleteResources":  true,
			"doesNotBuildImages":      true,
			"doesNotCommitOrPush":     true,
		},
	})

	runtime := &stubExecutionRuntime{
		descriptor: NewCLIExecutionRuntime(tempRepo).Descriptor(),
		scriptFile: scriptFile,
		shellBin:   "bash",
		runNoop: func(_ context.Context, evidenceFile string) ([]byte, error) {
			evidence := readExecutionTestJSON(t, evidenceFile)
			evidence["executionResultId"] = "xr-" + releaseID
			artifacts := ensureExecutionTestMap(evidence, "artifacts")
			artifacts["executionResult"] = filepath.Join(reportDir, "execution-result-"+releaseID+".json")
			decisionRefs := ensureExecutionTestMap(evidence, "decisionRefs")
			decisionRefs["executionResult"] = map[string]interface{}{
				"executionResultId":   "xr-" + releaseID,
				"executionStatus":     "PREVIEW_ONLY",
				"readyForExecution":   false,
				"requestedAction":     "STOP_PROMOTION",
				"executedActionCount": 1,
				"blockedActionCount":  0,
				"executorAdapter":     "noop-executor",
				"source":              filepath.Join(reportDir, "execution-result-"+releaseID+".json"),
			}
			writeExecutionTestJSON(t, evidenceFile, evidence)

			writeExecutionTestJSON(t, filepath.Join(reportDir, "execution-result-"+releaseID+".json"), map[string]interface{}{
				"schemaVersion":     "execution.result/v1alpha1",
				"executionResultId": "xr-" + releaseID,
				"generatedBy":       "execution_api_contract_test.go",
				"generatedAt":       "2026-01-01T05:05:07Z",
				"mode":              "noop_executor_result",
				"executor": map[string]interface{}{
					"adapter":                "noop-executor",
					"adapterType":            "test-stub",
					"dryRunOnly":             true,
					"readOnly":               true,
					"willExecute":            false,
					"mutatesGitOps":          false,
					"mutatesKubernetes":      false,
					"emitsExecutionEvidence": true,
				},
				"release": map[string]interface{}{
					"releaseId":      releaseID,
					"service":        "demo-app",
					"env":            "dev",
					"namespace":      "slo-rollout",
					"policyDecision": "REQUIRE_HUMAN_APPROVAL",
					"finalAction":    "STOP_PROMOTION",
				},
				"inputs": map[string]interface{}{
					"releaseEvidence":      evidenceFile,
					"executionRequest":     nil,
					"executionEligibility": nil,
					"executionPreview":     filepath.Join(reportDir, "execution-preview-"+releaseID+".json"),
				},
				"result": map[string]interface{}{
					"executionStatus":   "PREVIEW_ONLY",
					"readyForExecution": false,
					"requestedAction":   "STOP_PROMOTION",
					"summary":           "Preview-only execution evidence.",
					"executedActions":   []interface{}{map[string]interface{}{"actionId": "preview-1", "title": "Inspect rollout", "outcome": "preview_recorded", "dryRunOnly": true}},
					"blockedActions":    []interface{}{},
					"evidenceArtifacts": map[string]interface{}{"executionLog": nil, "sourceExecutionPreview": filepath.Join(reportDir, "execution-preview-"+releaseID+".json")},
				},
				"guardrails": map[string]interface{}{
					"readOnly":                true,
					"dryRunOnly":              true,
					"willExecute":             false,
					"doesNotModifyKubernetes": true,
					"doesNotModifyGitOps":     true,
					"doesNotRollback":         true,
					"doesNotPromote":          true,
					"doesNotPatchResources":   true,
					"doesNotDeleteResources":  true,
					"doesNotBuildImages":      true,
					"doesNotCommitOrPush":     true,
				},
			})
			writeExecutionTestJSON(t, filepath.Join(reportDir, "execution-result-latest.json"), readExecutionTestJSON(t, filepath.Join(reportDir, "execution-result-"+releaseID+".json")))
			writeExecutionTestJSON(t, filepath.Join(reportDir, "evidence-record-"+releaseID+".json"), map[string]interface{}{
				"schemaVersion": "evidence.record/v1alpha1",
				"evidenceId":    "ev-" + releaseID,
				"releaseId":     releaseID,
				"executionResult": map[string]interface{}{
					"executionResultId": "xr-" + releaseID,
					"executionStatus":   "PREVIEW_ONLY",
				},
			})
			writeExecutionTestJSON(t, filepath.Join(reportDir, "evidence-record-latest.json"), readExecutionTestJSON(t, filepath.Join(reportDir, "evidence-record-"+releaseID+".json")))

			return []byte(`{"schemaVersion":"execution.noop.run/v1alpha1","executionResultId":"xr-` + releaseID + `"}`), nil
		},
	}

	api := &portalAPI{
		cfg: Config{
			RepoDir: tempRepo,
		},
		reportDir: reportDir,
		executionSvc: &ExecutionService{
			cfg: ExecutionServiceConfig{
				RepoDir:   tempRepo,
				ReportDir: reportDir,
			},
			runtime: runtime,
		},
	}

	return api, releaseID
}

type stubExecutionRuntime struct {
	descriptor ExecutionRuntimeDescriptor
	scriptFile string
	shellBin   string
	runNoop    func(ctx context.Context, releaseEvidenceFile string) ([]byte, error)
}

func (runtime *stubExecutionRuntime) Descriptor() ExecutionRuntimeDescriptor {
	return runtime.descriptor
}

func (runtime *stubExecutionRuntime) ScriptFile() string {
	return runtime.scriptFile
}

func (runtime *stubExecutionRuntime) ShellBin() string {
	return runtime.shellBin
}

func (runtime *stubExecutionRuntime) RunNoop(ctx context.Context, releaseEvidenceFile string) ([]byte, error) {
	return runtime.runNoop(ctx, releaseEvidenceFile)
}

func callPortalExecutionHandler(
	t *testing.T,
	handler http.HandlerFunc,
	method string,
	target string,
	expectedStatus int,
) map[string]interface{} {
	t.Helper()

	req := httptest.NewRequest(method, target, nil)
	rec := httptest.NewRecorder()

	handler(rec, req)

	if rec.Code != expectedStatus {
		t.Fatalf("expected HTTP %d for %s %s, got %d: %s", expectedStatus, method, target, rec.Code, rec.Body.String())
	}

	body := map[string]interface{}{}
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode response for %s %s: %v: %s", method, target, err, rec.Body.String())
	}

	return body
}

func writeExecutionTestJSON(t *testing.T, path string, payload map[string]interface{}) {
	t.Helper()

	data, err := json.MarshalIndent(payload, "", "  ")
	if err != nil {
		t.Fatalf("marshal %s: %v", path, err)
	}

	if err := os.WriteFile(path, append(data, '\n'), 0644); err != nil {
		t.Fatalf("write %s: %v", path, err)
	}
}

func readExecutionTestJSON(t *testing.T, path string) map[string]interface{} {
	t.Helper()

	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read %s: %v", path, err)
	}

	doc := map[string]interface{}{}
	if err := json.Unmarshal(data, &doc); err != nil {
		t.Fatalf("decode %s: %v", path, err)
	}

	return doc
}

func ensureExecutionTestMap(parent map[string]interface{}, key string) map[string]interface{} {
	if existing, ok := parent[key].(map[string]interface{}); ok {
		return existing
	}

	child := map[string]interface{}{}
	parent[key] = child
	return child
}
