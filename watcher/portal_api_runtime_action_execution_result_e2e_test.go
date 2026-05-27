package main

import (
	"net/http"
	"os"
	"path/filepath"
	"testing"
)

func TestRuntimeActionExecutionResultEvidenceStoreAndPortalLatestResource(t *testing.T) {
	root, err := filepath.Abs("..")
	if err != nil {
		t.Fatalf("resolve repo root: %v", err)
	}

	tempRepo := t.TempDir()
	tempDB := filepath.Join(t.TempDir(), "evidence-store.db")
	t.Setenv("S_SENTINEL_EVIDENCE_STORE_DB", tempDB)

	scriptSource := filepath.Join(root, "scripts", "evidence-store.py")
	scriptData, err := os.ReadFile(scriptSource)
	if err != nil {
		t.Fatalf("read evidence-store.py: %v", err)
	}

	scriptDir := filepath.Join(tempRepo, "scripts")
	if err := os.MkdirAll(scriptDir, 0755); err != nil {
		t.Fatalf("create script dir: %v", err)
	}
	if err := os.WriteFile(filepath.Join(scriptDir, "evidence-store.py"), scriptData, 0755); err != nil {
		t.Fatalf("write evidence-store.py: %v", err)
	}

	reportDir := filepath.Join(tempRepo, "docs", "release-reports")
	if err := os.MkdirAll(reportDir, 0755); err != nil {
		t.Fatalf("create report dir: %v", err)
	}

	releaseID := "20260527-050505"
	resultID := "raer-" + releaseID
	preflightID := "rap-" + releaseID
	requestID := "rarq-" + releaseID
	recommendationID := "rar-" + releaseID

	releaseEvidence := `{
  "schemaVersion": "release.evidence/v1alpha1",
  "generatedBy": "portal_api_runtime_action_execution_result_e2e_test.go",
  "releaseId": "` + releaseID + `",
  "releaseResult": "STOP_PROMOTION",
  "policyDecision": "REQUIRE_HUMAN_APPROVAL",
  "service": "demo-app",
  "namespace": "slo-rollout",
  "env": "dev",
  "artifacts": {
    "runtimeActionExecutionResult": "runtime-action-execution-result-` + releaseID + `.json"
  }
}`

	result := `{
  "schemaVersion": "runtime.action.execution.result/v1alpha1",
  "runtimeActionExecutionResultId": "` + resultID + `",
  "generatedBy": "portal_api_runtime_action_execution_result_e2e_test.go",
  "generatedAt": "2026-05-27T05:05:05Z",
  "mode": "controlled_runtime_action_result",
  "sourceRuntimeActionPreflightId": "` + preflightID + `",
  "sourceRuntimeActionRequestId": "` + requestID + `",
  "release": {
    "releaseId": "` + releaseID + `",
    "service": "demo-app",
    "namespace": "slo-rollout",
    "env": "dev",
    "policyDecision": "REQUIRE_HUMAN_APPROVAL",
    "finalAction": "STOP_PROMOTION"
  },
  "target": {
    "cluster": "local-dev",
    "namespace": "slo-rollout",
    "rolloutName": "demo-app",
    "service": "demo-app",
    "env": "dev"
  },
  "action": {
    "requestedAction": "PAUSE_ROLLOUT",
    "actionStatus": "EXECUTION_SUCCEEDED",
    "commandMode": "kubectl_patch_rollout_spec_paused",
    "commandWillExecute": true,
    "commandExitCode": 0
  },
  "executor": {
    "executorName": "runtime-rollout-executor",
    "adapter": "runtime-rollout-control"
  },
  "writeGate": {
    "preflightStatus": "PREFLIGHT_PASSED",
    "eligibilityStatus": "ELIGIBLE_FOR_CONTROLLED_EXECUTOR",
    "finalExecuteEnabled": true,
    "writeAllowed": true
  },
  "beforeSnapshot": {
    "rolloutPhase": "Degraded",
    "analysisStatus": "Failed"
  },
  "afterSnapshot": {
    "observationMode": "live_readonly_rollout_get_after_action",
    "postActionRolloutGetAttempted": true,
    "postActionRolloutGetSucceeded": true,
    "paused": true,
    "specPaused": true,
    "statusPaused": false,
    "phase": "Degraded"
  },
  "postActionVerification": {
    "verificationType": "runtime_action_post_action_verification",
    "verificationStatus": "VERIFIED",
    "requestedAction": "PAUSE_ROLLOUT",
    "commandSucceeded": true,
    "postActionObserved": true,
    "desiredStateObserved": true,
    "pauseVerified": true,
    "expectedPaused": true,
    "observedPaused": true,
    "observedSpecPaused": true,
    "observedStatusPaused": false,
    "blockingReasons": [],
    "warningReasons": []
  },
  "result": {
    "requestedAction": "PAUSE_ROLLOUT",
    "actionStatus": "EXECUTION_SUCCEEDED",
    "executionStatus": "SUCCEEDED",
    "verificationStatus": "VERIFIED",
    "pauseVerified": true,
    "postActionObserved": true,
    "desiredStateObserved": true,
    "didPause": true,
    "attemptedKubernetesMutation": true,
    "mutatedKubernetes": true,
    "mutatedGitOps": false
  },
  "receipt": {
    "verificationStatus": "VERIFIED",
    "pauseVerified": true,
    "didModifyKubernetes": true,
    "didModifyGitOps": false
  },
  "evidenceRefs": {
    "runtimeActionPreflight": "runtime-action-preflight-` + releaseID + `.json",
    "runtimeActionRequest": "runtime-action-request-` + releaseID + `.json",
    "runtimeActionRecommendation": "runtime-action-recommendation-` + releaseID + `.json",
    "rolloutRuntimeInspect": "rollout-runtime-inspect-` + releaseID + `.json",
    "sourceRuntimeActionPreflightId": "` + preflightID + `",
    "sourceRuntimeActionRequestId": "` + requestID + `",
    "sourceRuntimeActionRecommendationId": "` + recommendationID + `",
    "sourceRolloutRuntimeInspectId": "rti-` + releaseID + `"
  },
  "guardrails": {
    "willExecute": true,
    "postActionVerified": true,
    "doesNotModifyGitOps": true
  }
}`

	writeB4TestFile(t, filepath.Join(reportDir, "release-evidence-"+releaseID+".json"), releaseEvidence)
	writeB4TestFile(t, filepath.Join(reportDir, "runtime-action-execution-result-"+releaseID+".json"), result)
	writeB4TestFile(t, filepath.Join(reportDir, "runtime-action-execution-result-latest.json"), result)

	api := &portalAPI{
		cfg: Config{
			RepoDir: tempRepo,
		},
		reportDir: reportDir,
	}

	latestResult := callB4PortalJSON(t, api.handleLatestResource("runtimeActionExecutionResult"), http.MethodGet, "/api/releases/latest/runtime-action-execution-result", http.StatusOK)
	requireB4String(t, latestResult, "runtimeActionExecutionResultId", resultID)
	requireB4NestedString(t, latestResult, "action", "requestedAction", "PAUSE_ROLLOUT")
	requireB4NestedString(t, latestResult, "action", "actionStatus", "EXECUTION_SUCCEEDED")
	requireB4NestedString(t, latestResult, "result", "executionStatus", "SUCCEEDED")
	requireB4NestedString(t, latestResult, "result", "verificationStatus", "VERIFIED")
	requireB4NestedString(t, latestResult, "postActionVerification", "verificationStatus", "VERIFIED")
	requireB4JSONContains(t, latestResult, "pauseVerified")
	requireB4JSONContains(t, latestResult, "postActionObserved")
	requireB4JSONContains(t, latestResult, "live_readonly_rollout_get_after_action")

	refresh := callB4PortalJSON(t, api.handleEvidenceStoreRefresh, http.MethodPost, "/api/evidence-store/refresh", http.StatusOK)
	requireB4String(t, refresh, "schemaVersion", "evidence.store.refresh/v1alpha1")

	resultObject := callB4PortalJSON(t, api.handleEvidenceStoreObjectDetail, http.MethodGet, "/api/evidence/objects/runtimeActionExecutionResult/"+resultID+"?releaseId="+releaseID+"&includeRaw=true", http.StatusOK)
	requireB4String(t, resultObject, "schemaVersion", "evidence.store.object/v1alpha1")
	requireB4JSONContains(t, resultObject, "runtimeActionExecutionResult")
	requireB4JSONContains(t, resultObject, "PAUSE_ROLLOUT")
	requireB4JSONContains(t, resultObject, "EXECUTION_SUCCEEDED")
	requireB4JSONContains(t, resultObject, "kubectl_patch_rollout_spec_paused")
	requireB4JSONContains(t, resultObject, "mutatedKubernetes")
	requireB4JSONContains(t, resultObject, "verificationStatus")
	requireB4JSONContains(t, resultObject, "VERIFIED")
	requireB4JSONContains(t, resultObject, "pauseVerified")
	requireB4JSONContains(t, resultObject, "postActionObserved")
	requireB4JSONContains(t, resultObject, "live_readonly_rollout_get_after_action")

	releaseDetail := callB4PortalJSON(t, api.handleEvidenceStoreReleaseDetail, http.MethodGet, "/api/evidence/releases/"+releaseID+"?includeRaw=true", http.StatusOK)
	requireB4String(t, releaseDetail, "schemaVersion", "evidence.store.release/v1alpha1")
	requireB4JSONContains(t, releaseDetail, "runtimeActionExecutionResult")
	requireB4JSONContains(t, releaseDetail, resultID)
	requireB4JSONContains(t, releaseDetail, "verificationStatus")
	requireB4JSONContains(t, releaseDetail, "VERIFIED")
	requireB4JSONContains(t, releaseDetail, "pauseVerified")
}

func TestRuntimeActionExecutionResultResumeEvidenceStoreAndPortalLatestResource(t *testing.T) {
	root, err := filepath.Abs("..")
	if err != nil {
		t.Fatalf("resolve repo root: %v", err)
	}

	tempRepo := t.TempDir()
	tempDB := filepath.Join(t.TempDir(), "evidence-store.db")
	t.Setenv("S_SENTINEL_EVIDENCE_STORE_DB", tempDB)

	scriptSource := filepath.Join(root, "scripts", "evidence-store.py")
	scriptData, err := os.ReadFile(scriptSource)
	if err != nil {
		t.Fatalf("read evidence-store.py: %v", err)
	}

	scriptDir := filepath.Join(tempRepo, "scripts")
	if err := os.MkdirAll(scriptDir, 0755); err != nil {
		t.Fatalf("create script dir: %v", err)
	}
	if err := os.WriteFile(filepath.Join(scriptDir, "evidence-store.py"), scriptData, 0755); err != nil {
		t.Fatalf("write evidence-store.py: %v", err)
	}

	reportDir := filepath.Join(tempRepo, "docs", "release-reports")
	if err := os.MkdirAll(reportDir, 0755); err != nil {
		t.Fatalf("create report dir: %v", err)
	}

	releaseID := "20260527-060606"
	resultID := "raer-" + releaseID
	preflightID := "rap-" + releaseID
	requestID := "rarq-" + releaseID
	recommendationID := "rar-" + releaseID

	releaseEvidence := `{
  "schemaVersion": "release.evidence/v1alpha1",
  "generatedBy": "portal_api_runtime_action_execution_result_e2e_test.go",
  "releaseId": "` + releaseID + `",
  "releaseResult": "MANUAL_RUNTIME_ACTION",
  "policyDecision": "APPROVED",
  "finalAction": "RESUME_ROLLOUT",
  "service": "demo-app",
  "namespace": "slo-rollout",
  "env": "dev",
  "artifacts": {
    "runtimeActionExecutionResult": "runtime-action-execution-result-` + releaseID + `.json"
  }
}`

	result := `{
  "schemaVersion": "runtime.action.execution.result/v1alpha1",
  "runtimeActionExecutionResultId": "` + resultID + `",
  "generatedBy": "portal_api_runtime_action_execution_result_e2e_test.go",
  "generatedAt": "2026-05-27T06:06:06Z",
  "mode": "controlled_runtime_action_result",
  "sourceRuntimeActionPreflightId": "` + preflightID + `",
  "sourceRuntimeActionRequestId": "` + requestID + `",
  "release": {
    "releaseId": "` + releaseID + `",
    "service": "demo-app",
    "namespace": "slo-rollout",
    "env": "dev",
    "policyDecision": "APPROVED",
    "finalAction": "RESUME_ROLLOUT"
  },
  "target": {
    "cluster": "local-dev",
    "namespace": "slo-rollout",
    "rolloutName": "demo-app",
    "service": "demo-app",
    "env": "dev"
  },
  "action": {
    "requestedAction": "RESUME_ROLLOUT",
    "actionStatus": "EXECUTION_SUCCEEDED",
    "commandMode": "kubectl_patch_rollout_spec_paused_false",
    "commandWillExecute": true,
    "commandExitCode": 0
  },
  "executor": {
    "executorName": "runtime-rollout-executor",
    "adapter": "runtime-rollout-control"
  },
  "writeGate": {
    "preflightStatus": "PREFLIGHT_PASSED",
    "eligibilityStatus": "ELIGIBLE_FOR_CONTROLLED_EXECUTOR",
    "operation": "RESUME_ROLLOUT",
    "operationGateEnv": "S_SENTINEL_ALLOW_RUNTIME_RESUME",
    "finalExecuteEnv": "S_SENTINEL_RUNTIME_RESUME_EXECUTE",
    "finalExecuteEnabled": true,
    "writeAllowed": true
  },
  "beforeSnapshot": {
    "rolloutPhase": "Paused",
    "analysisStatus": "Unknown"
  },
  "afterSnapshot": {
    "observationMode": "live_readonly_rollout_get_after_action",
    "postActionRolloutGetAttempted": true,
    "postActionRolloutGetSucceeded": true,
    "paused": false,
    "specPaused": false,
    "statusPaused": false,
    "phase": "Healthy"
  },
  "postActionVerification": {
    "verificationType": "runtime_action_post_action_verification",
    "verificationStatus": "VERIFIED",
    "requestedAction": "RESUME_ROLLOUT",
    "commandSucceeded": true,
    "postActionObserved": true,
    "desiredStateObserved": true,
    "pauseVerified": false,
    "resumeVerified": true,
    "expectedPaused": false,
    "observedPaused": false,
    "observedSpecPaused": false,
    "observedStatusPaused": false,
    "blockingReasons": [],
    "warningReasons": []
  },
  "result": {
    "requestedAction": "RESUME_ROLLOUT",
    "actionStatus": "EXECUTION_SUCCEEDED",
    "executionStatus": "SUCCEEDED",
    "verificationStatus": "VERIFIED",
    "pauseVerified": false,
    "resumeVerified": true,
    "postActionObserved": true,
    "desiredStateObserved": true,
    "didPause": false,
    "didResume": true,
    "attemptedKubernetesMutation": true,
    "mutatedKubernetes": true,
    "mutatedGitOps": false
  },
  "receipt": {
    "verificationStatus": "VERIFIED",
    "pauseVerified": false,
    "resumeVerified": true,
    "didPause": false,
    "didResume": true,
    "didModifyKubernetes": true,
    "didModifyGitOps": false
  },
  "evidenceRefs": {
    "runtimeActionPreflight": "runtime-action-preflight-` + releaseID + `.json",
    "runtimeActionRequest": "runtime-action-request-` + releaseID + `.json",
    "runtimeActionRecommendation": "runtime-action-recommendation-` + releaseID + `.json",
    "rolloutRuntimeInspect": "rollout-runtime-inspect-` + releaseID + `.json",
    "sourceRuntimeActionPreflightId": "` + preflightID + `",
    "sourceRuntimeActionRequestId": "` + requestID + `",
    "sourceRuntimeActionRecommendationId": "` + recommendationID + `",
    "sourceRolloutRuntimeInspectId": "rti-` + releaseID + `"
  },
  "guardrails": {
    "willExecute": true,
    "postActionVerified": true,
    "doesNotPause": true,
    "doesNotResume": false,
    "doesNotModifyGitOps": true
  }
}`

	writeB4TestFile(t, filepath.Join(reportDir, "release-evidence-"+releaseID+".json"), releaseEvidence)
	writeB4TestFile(t, filepath.Join(reportDir, "runtime-action-execution-result-"+releaseID+".json"), result)
	writeB4TestFile(t, filepath.Join(reportDir, "runtime-action-execution-result-latest.json"), result)

	api := &portalAPI{
		cfg: Config{
			RepoDir: tempRepo,
		},
		reportDir: reportDir,
	}

	latestResult := callB4PortalJSON(t, api.handleLatestResource("runtimeActionExecutionResult"), http.MethodGet, "/api/releases/latest/runtime-action-execution-result", http.StatusOK)
	requireB4String(t, latestResult, "runtimeActionExecutionResultId", resultID)
	requireB4NestedString(t, latestResult, "action", "requestedAction", "RESUME_ROLLOUT")
	requireB4NestedString(t, latestResult, "action", "actionStatus", "EXECUTION_SUCCEEDED")
	requireB4NestedString(t, latestResult, "result", "executionStatus", "SUCCEEDED")
	requireB4NestedString(t, latestResult, "result", "verificationStatus", "VERIFIED")
	requireB4NestedString(t, latestResult, "postActionVerification", "verificationStatus", "VERIFIED")
	requireB4JSONContains(t, latestResult, "resumeVerified")
	requireB4JSONContains(t, latestResult, "didResume")
	requireB4JSONContains(t, latestResult, "RESUME_ROLLOUT")
	requireB4JSONContains(t, latestResult, "kubectl_patch_rollout_spec_paused_false")
	requireB4JSONContains(t, latestResult, "live_readonly_rollout_get_after_action")

	refresh := callB4PortalJSON(t, api.handleEvidenceStoreRefresh, http.MethodPost, "/api/evidence-store/refresh", http.StatusOK)
	requireB4String(t, refresh, "schemaVersion", "evidence.store.refresh/v1alpha1")

	resultObject := callB4PortalJSON(t, api.handleEvidenceStoreObjectDetail, http.MethodGet, "/api/evidence/objects/runtimeActionExecutionResult/"+resultID+"?releaseId="+releaseID+"&includeRaw=true", http.StatusOK)
	requireB4String(t, resultObject, "schemaVersion", "evidence.store.object/v1alpha1")
	requireB4JSONContains(t, resultObject, "runtimeActionExecutionResult")
	requireB4JSONContains(t, resultObject, "RESUME_ROLLOUT")
	requireB4JSONContains(t, resultObject, "EXECUTION_SUCCEEDED")
	requireB4JSONContains(t, resultObject, "kubectl_patch_rollout_spec_paused_false")
	requireB4JSONContains(t, resultObject, "mutatedKubernetes")
	requireB4JSONContains(t, resultObject, "verificationStatus")
	requireB4JSONContains(t, resultObject, "VERIFIED")
	requireB4JSONContains(t, resultObject, "resumeVerified")
	requireB4JSONContains(t, resultObject, "didResume")
	requireB4JSONContains(t, resultObject, "postActionObserved")
	requireB4JSONContains(t, resultObject, "live_readonly_rollout_get_after_action")

	releaseDetail := callB4PortalJSON(t, api.handleEvidenceStoreReleaseDetail, http.MethodGet, "/api/evidence/releases/"+releaseID+"?includeRaw=true", http.StatusOK)
	requireB4String(t, releaseDetail, "schemaVersion", "evidence.store.release/v1alpha1")
	requireB4JSONContains(t, releaseDetail, "runtimeActionExecutionResult")
	requireB4JSONContains(t, releaseDetail, resultID)
	requireB4JSONContains(t, releaseDetail, "RESUME_ROLLOUT")
	requireB4JSONContains(t, releaseDetail, "verificationStatus")
	requireB4JSONContains(t, releaseDetail, "VERIFIED")
	requireB4JSONContains(t, releaseDetail, "resumeVerified")
	requireB4JSONContains(t, releaseDetail, "didResume")
}

func TestRuntimeActionExecutionResultPromoteEvidenceStoreAndPortalLatestResource(t *testing.T) {
	root, err := filepath.Abs("..")
	if err != nil {
		t.Fatalf("resolve repo root: %v", err)
	}

	tempRepo := t.TempDir()
	tempDB := filepath.Join(t.TempDir(), "evidence-store.db")
	t.Setenv("S_SENTINEL_EVIDENCE_STORE_DB", tempDB)

	scriptSource := filepath.Join(root, "scripts", "evidence-store.py")
	scriptData, err := os.ReadFile(scriptSource)
	if err != nil {
		t.Fatalf("read evidence-store.py: %v", err)
	}

	scriptDir := filepath.Join(tempRepo, "scripts")
	if err := os.MkdirAll(scriptDir, 0755); err != nil {
		t.Fatalf("create script dir: %v", err)
	}
	if err := os.WriteFile(filepath.Join(scriptDir, "evidence-store.py"), scriptData, 0755); err != nil {
		t.Fatalf("write evidence-store.py: %v", err)
	}

	reportDir := filepath.Join(tempRepo, "docs", "release-reports")
	if err := os.MkdirAll(reportDir, 0755); err != nil {
		t.Fatalf("create report dir: %v", err)
	}

	releaseID := "20260527-070707"
	resultID := "raer-" + releaseID
	preflightID := "rap-" + releaseID
	requestID := "rarq-" + releaseID
	recommendationID := "rar-" + releaseID

	releaseEvidence := `{
  "schemaVersion": "release.evidence/v1alpha1",
  "generatedBy": "portal_api_runtime_action_execution_result_e2e_test.go",
  "releaseId": "` + releaseID + `",
  "releaseResult": "MANUAL_RUNTIME_ACTION",
  "policyDecision": "APPROVED",
  "finalAction": "PROMOTE_ROLLOUT",
  "service": "demo-app",
  "namespace": "slo-rollout",
  "env": "dev",
  "artifacts": {
    "runtimeActionExecutionResult": "runtime-action-execution-result-` + releaseID + `.json"
  }
}`

	result := `{
  "schemaVersion": "runtime.action.execution.result/v1alpha1",
  "runtimeActionExecutionResultId": "` + resultID + `",
  "generatedBy": "portal_api_runtime_action_execution_result_e2e_test.go",
  "generatedAt": "2026-05-27T07:07:07Z",
  "mode": "controlled_runtime_action_result",
  "sourceRuntimeActionPreflightId": "` + preflightID + `",
  "sourceRuntimeActionRequestId": "` + requestID + `",
  "release": {
    "releaseId": "` + releaseID + `",
    "service": "demo-app",
    "namespace": "slo-rollout",
    "env": "dev",
    "policyDecision": "APPROVED",
    "finalAction": "PROMOTE_ROLLOUT"
  },
  "target": {
    "cluster": "local-dev",
    "namespace": "slo-rollout",
    "rolloutName": "demo-app",
    "service": "demo-app",
    "env": "dev"
  },
  "action": {
    "requestedAction": "PROMOTE_ROLLOUT",
    "actionStatus": "EXECUTION_SUCCEEDED",
    "commandMode": "kubectl_argo_rollouts_promote",
    "commandWillExecute": true,
    "commandExitCode": 0
  },
  "executor": {
    "executorName": "runtime-rollout-executor",
    "adapter": "runtime-rollout-control"
  },
  "writeGate": {
    "preflightStatus": "PREFLIGHT_PASSED",
    "eligibilityStatus": "ELIGIBLE_FOR_CONTROLLED_EXECUTOR",
    "operation": "PROMOTE_ROLLOUT",
    "operationGateEnv": "S_SENTINEL_ALLOW_RUNTIME_PROMOTE",
    "finalExecuteEnv": "S_SENTINEL_RUNTIME_PROMOTE_EXECUTE",
    "finalExecuteEnabled": true,
    "writeAllowed": true
  },
  "beforeSnapshot": {
    "rolloutPhase": "Paused",
    "analysisStatus": "Successful",
    "currentStepIndex": 1
  },
  "afterSnapshot": {
    "observationMode": "live_readonly_rollout_get_after_action",
    "postActionRolloutGetAttempted": true,
    "postActionRolloutGetSucceeded": true,
    "paused": false,
    "specPaused": false,
    "statusPaused": false,
    "phase": "Healthy",
    "currentStepIndex": 2,
    "degraded": false
  },
  "postActionVerification": {
    "verificationType": "runtime_action_post_action_verification",
    "verificationStatus": "VERIFIED",
    "requestedAction": "PROMOTE_ROLLOUT",
    "commandSucceeded": true,
    "postActionObserved": true,
    "desiredStateObserved": true,
    "pauseVerified": false,
    "resumeVerified": false,
    "promoteVerified": true,
    "promoteStepAdvanced": true,
    "promotePhaseObserved": true,
    "blockingReasons": [],
    "warningReasons": []
  },
  "result": {
    "requestedAction": "PROMOTE_ROLLOUT",
    "actionStatus": "EXECUTION_SUCCEEDED",
    "executionStatus": "SUCCEEDED",
    "verificationStatus": "VERIFIED",
    "pauseVerified": false,
    "resumeVerified": false,
    "promoteVerified": true,
    "postActionObserved": true,
    "desiredStateObserved": true,
    "didPause": false,
    "didResume": false,
    "didPromote": true,
    "attemptedKubernetesMutation": true,
    "mutatedKubernetes": true,
    "mutatedGitOps": false
  },
  "receipt": {
    "verificationStatus": "VERIFIED",
    "pauseVerified": false,
    "resumeVerified": false,
    "promoteVerified": true,
    "didPause": false,
    "didResume": false,
    "didPromote": true,
    "didModifyKubernetes": true,
    "didModifyGitOps": false
  },
  "evidenceRefs": {
    "runtimeActionPreflight": "runtime-action-preflight-` + releaseID + `.json",
    "runtimeActionRequest": "runtime-action-request-` + releaseID + `.json",
    "runtimeActionRecommendation": "runtime-action-recommendation-` + releaseID + `.json",
    "rolloutRuntimeInspect": "rollout-runtime-inspect-` + releaseID + `.json",
    "sourceRuntimeActionPreflightId": "` + preflightID + `",
    "sourceRuntimeActionRequestId": "` + requestID + `",
    "sourceRuntimeActionRecommendationId": "` + recommendationID + `",
    "sourceRolloutRuntimeInspectId": "rti-` + releaseID + `"
  },
  "guardrails": {
    "willExecute": true,
    "postActionVerified": true,
    "doesNotPause": true,
    "doesNotResume": true,
    "doesNotPromote": false,
    "doesNotModifyGitOps": true
  }
}`

	writeB4TestFile(t, filepath.Join(reportDir, "release-evidence-"+releaseID+".json"), releaseEvidence)
	writeB4TestFile(t, filepath.Join(reportDir, "runtime-action-execution-result-"+releaseID+".json"), result)
	writeB4TestFile(t, filepath.Join(reportDir, "runtime-action-execution-result-latest.json"), result)

	api := &portalAPI{
		cfg: Config{
			RepoDir: tempRepo,
		},
		reportDir: reportDir,
	}

	latestResult := callB4PortalJSON(t, api.handleLatestResource("runtimeActionExecutionResult"), http.MethodGet, "/api/releases/latest/runtime-action-execution-result", http.StatusOK)
	requireB4String(t, latestResult, "runtimeActionExecutionResultId", resultID)
	requireB4NestedString(t, latestResult, "action", "requestedAction", "PROMOTE_ROLLOUT")
	requireB4NestedString(t, latestResult, "action", "actionStatus", "EXECUTION_SUCCEEDED")
	requireB4NestedString(t, latestResult, "action", "commandMode", "kubectl_argo_rollouts_promote")
	requireB4NestedString(t, latestResult, "result", "executionStatus", "SUCCEEDED")
	requireB4NestedString(t, latestResult, "result", "verificationStatus", "VERIFIED")
	requireB4NestedString(t, latestResult, "postActionVerification", "verificationStatus", "VERIFIED")
	requireB4JSONContains(t, latestResult, "promoteVerified")
	requireB4JSONContains(t, latestResult, "didPromote")
	requireB4JSONContains(t, latestResult, "PROMOTE_ROLLOUT")
	requireB4JSONContains(t, latestResult, "kubectl_argo_rollouts_promote")
	requireB4JSONContains(t, latestResult, "live_readonly_rollout_get_after_action")

	refresh := callB4PortalJSON(t, api.handleEvidenceStoreRefresh, http.MethodPost, "/api/evidence-store/refresh", http.StatusOK)
	requireB4String(t, refresh, "schemaVersion", "evidence.store.refresh/v1alpha1")

	resultObject := callB4PortalJSON(t, api.handleEvidenceStoreObjectDetail, http.MethodGet, "/api/evidence/objects/runtimeActionExecutionResult/"+resultID+"?releaseId="+releaseID+"&includeRaw=true", http.StatusOK)
	requireB4String(t, resultObject, "schemaVersion", "evidence.store.object/v1alpha1")
	requireB4JSONContains(t, resultObject, "runtimeActionExecutionResult")
	requireB4JSONContains(t, resultObject, "PROMOTE_ROLLOUT")
	requireB4JSONContains(t, resultObject, "EXECUTION_SUCCEEDED")
	requireB4JSONContains(t, resultObject, "kubectl_argo_rollouts_promote")
	requireB4JSONContains(t, resultObject, "mutatedKubernetes")
	requireB4JSONContains(t, resultObject, "verificationStatus")
	requireB4JSONContains(t, resultObject, "VERIFIED")
	requireB4JSONContains(t, resultObject, "promoteVerified")
	requireB4JSONContains(t, resultObject, "didPromote")
	requireB4JSONContains(t, resultObject, "postActionObserved")
	requireB4JSONContains(t, resultObject, "live_readonly_rollout_get_after_action")

	releaseDetail := callB4PortalJSON(t, api.handleEvidenceStoreReleaseDetail, http.MethodGet, "/api/evidence/releases/"+releaseID+"?includeRaw=true", http.StatusOK)
	requireB4String(t, releaseDetail, "schemaVersion", "evidence.store.release/v1alpha1")
	requireB4JSONContains(t, releaseDetail, "runtimeActionExecutionResult")
	requireB4JSONContains(t, releaseDetail, resultID)
	requireB4JSONContains(t, releaseDetail, "PROMOTE_ROLLOUT")
	requireB4JSONContains(t, releaseDetail, "verificationStatus")
	requireB4JSONContains(t, releaseDetail, "VERIFIED")
	requireB4JSONContains(t, releaseDetail, "promoteVerified")
	requireB4JSONContains(t, releaseDetail, "didPromote")
}

func TestRuntimeActionExecutionResultAbortEvidenceStoreAndPortalLatestResource(t *testing.T) {
	root, err := filepath.Abs("..")
	if err != nil {
		t.Fatalf("resolve repo root: %v", err)
	}

	tempRepo := t.TempDir()
	tempDB := filepath.Join(t.TempDir(), "evidence-store.db")
	t.Setenv("S_SENTINEL_EVIDENCE_STORE_DB", tempDB)

	scriptSource := filepath.Join(root, "scripts", "evidence-store.py")
	scriptData, err := os.ReadFile(scriptSource)
	if err != nil {
		t.Fatalf("read evidence-store.py: %v", err)
	}

	scriptDir := filepath.Join(tempRepo, "scripts")
	if err := os.MkdirAll(scriptDir, 0755); err != nil {
		t.Fatalf("create script dir: %v", err)
	}
	if err := os.WriteFile(filepath.Join(scriptDir, "evidence-store.py"), scriptData, 0755); err != nil {
		t.Fatalf("write evidence-store.py: %v", err)
	}

	reportDir := filepath.Join(tempRepo, "docs", "release-reports")
	if err := os.MkdirAll(reportDir, 0755); err != nil {
		t.Fatalf("create report dir: %v", err)
	}

	releaseID := "20260527-080808"
	resultID := "raer-" + releaseID
	preflightID := "rap-" + releaseID
	requestID := "rarq-" + releaseID
	recommendationID := "rar-" + releaseID

	releaseEvidence := `{
  "schemaVersion": "release.evidence/v1alpha1",
  "generatedBy": "portal_api_runtime_action_execution_result_e2e_test.go",
  "releaseId": "` + releaseID + `",
  "releaseResult": "MANUAL_RUNTIME_ACTION",
  "policyDecision": "APPROVED",
  "finalAction": "ABORT_ROLLOUT",
  "service": "demo-app",
  "namespace": "slo-rollout",
  "env": "dev",
  "artifacts": {
    "runtimeActionExecutionResult": "runtime-action-execution-result-` + releaseID + `.json"
  }
}`

	result := `{
  "schemaVersion": "runtime.action.execution.result/v1alpha1",
  "runtimeActionExecutionResultId": "` + resultID + `",
  "generatedBy": "portal_api_runtime_action_execution_result_e2e_test.go",
  "generatedAt": "2026-05-27T08:08:08Z",
  "mode": "controlled_runtime_action_result",
  "sourceRuntimeActionPreflightId": "` + preflightID + `",
  "sourceRuntimeActionRequestId": "` + requestID + `",
  "release": {
    "releaseId": "` + releaseID + `",
    "service": "demo-app",
    "namespace": "slo-rollout",
    "env": "dev",
    "policyDecision": "APPROVED",
    "finalAction": "ABORT_ROLLOUT"
  },
  "target": {
    "cluster": "local-dev",
    "namespace": "slo-rollout",
    "rolloutName": "demo-app",
    "service": "demo-app",
    "env": "dev"
  },
  "action": {
    "requestedAction": "ABORT_ROLLOUT",
    "actionStatus": "EXECUTION_SUCCEEDED",
    "commandMode": "kubectl_argo_rollouts_abort",
    "commandWillExecute": true,
    "commandExitCode": 0
  },
  "executor": {
    "executorName": "runtime-rollout-executor",
    "adapter": "runtime-rollout-control"
  },
  "writeGate": {
    "preflightStatus": "PREFLIGHT_PASSED",
    "eligibilityStatus": "ELIGIBLE_FOR_CONTROLLED_EXECUTOR",
    "operation": "ABORT_ROLLOUT",
    "operationGateEnv": "S_SENTINEL_ALLOW_RUNTIME_ABORT",
    "finalExecuteEnv": "S_SENTINEL_RUNTIME_ABORT_EXECUTE",
    "finalExecuteEnabled": true,
    "writeAllowed": true
  },
  "beforeSnapshot": {
    "rolloutPhase": "Progressing",
    "analysisStatus": "Running",
    "currentStepIndex": 1
  },
  "afterSnapshot": {
    "observationMode": "live_readonly_rollout_get_after_action",
    "postActionRolloutGetAttempted": true,
    "postActionRolloutGetSucceeded": true,
    "phase": "Degraded",
    "message": "RolloutAborted: Rollout aborted update to revision 61",
    "aborted": true,
    "degraded": true
  },
  "postActionVerification": {
    "verificationType": "runtime_action_post_action_verification",
    "verificationStatus": "VERIFIED",
    "requestedAction": "ABORT_ROLLOUT",
    "commandSucceeded": true,
    "postActionObserved": true,
    "desiredStateObserved": true,
    "pauseVerified": false,
    "resumeVerified": false,
    "promoteVerified": false,
    "abortVerified": true,
    "abortPhaseObserved": true,
    "observedAborted": true,
    "blockingReasons": [],
    "warningReasons": []
  },
  "result": {
    "requestedAction": "ABORT_ROLLOUT",
    "actionStatus": "EXECUTION_SUCCEEDED",
    "executionStatus": "SUCCEEDED",
    "verificationStatus": "VERIFIED",
    "pauseVerified": false,
    "resumeVerified": false,
    "promoteVerified": false,
    "abortVerified": true,
    "postActionObserved": true,
    "desiredStateObserved": true,
    "didPause": false,
    "didResume": false,
    "didPromote": false,
    "didAbort": true,
    "attemptedKubernetesMutation": true,
    "mutatedKubernetes": true,
    "mutatedGitOps": false
  },
  "receipt": {
    "verificationStatus": "VERIFIED",
    "pauseVerified": false,
    "resumeVerified": false,
    "promoteVerified": false,
    "abortVerified": true,
    "didPause": false,
    "didResume": false,
    "didPromote": false,
    "didAbort": true,
    "didModifyKubernetes": true,
    "didModifyGitOps": false
  },
  "evidenceRefs": {
    "runtimeActionPreflight": "runtime-action-preflight-` + releaseID + `.json",
    "runtimeActionRequest": "runtime-action-request-` + releaseID + `.json",
    "runtimeActionRecommendation": "runtime-action-recommendation-` + releaseID + `.json",
    "rolloutRuntimeInspect": "rollout-runtime-inspect-` + releaseID + `.json",
    "sourceRuntimeActionPreflightId": "` + preflightID + `",
    "sourceRuntimeActionRequestId": "` + requestID + `",
    "sourceRuntimeActionRecommendationId": "` + recommendationID + `",
    "sourceRolloutRuntimeInspectId": "rti-` + releaseID + `"
  },
  "guardrails": {
    "willExecute": true,
    "postActionVerified": true,
    "doesNotAbort": false,
    "doesNotRollback": true,
    "doesNotModifyGitOps": true
  }
}`

	writeB4TestFile(t, filepath.Join(reportDir, "release-evidence-"+releaseID+".json"), releaseEvidence)
	writeB4TestFile(t, filepath.Join(reportDir, "runtime-action-execution-result-"+releaseID+".json"), result)
	writeB4TestFile(t, filepath.Join(reportDir, "runtime-action-execution-result-latest.json"), result)

	api := &portalAPI{
		cfg: Config{
			RepoDir: tempRepo,
		},
		reportDir: reportDir,
	}

	latestResult := callB4PortalJSON(t, api.handleLatestResource("runtimeActionExecutionResult"), http.MethodGet, "/api/releases/latest/runtime-action-execution-result", http.StatusOK)
	requireB4String(t, latestResult, "runtimeActionExecutionResultId", resultID)
	requireB4NestedString(t, latestResult, "action", "requestedAction", "ABORT_ROLLOUT")
	requireB4NestedString(t, latestResult, "action", "actionStatus", "EXECUTION_SUCCEEDED")
	requireB4NestedString(t, latestResult, "action", "commandMode", "kubectl_argo_rollouts_abort")
	requireB4NestedString(t, latestResult, "result", "executionStatus", "SUCCEEDED")
	requireB4NestedString(t, latestResult, "result", "verificationStatus", "VERIFIED")
	requireB4NestedString(t, latestResult, "postActionVerification", "verificationStatus", "VERIFIED")
	requireB4JSONContains(t, latestResult, "abortVerified")
	requireB4JSONContains(t, latestResult, "didAbort")
	requireB4JSONContains(t, latestResult, "ABORT_ROLLOUT")
	requireB4JSONContains(t, latestResult, "kubectl_argo_rollouts_abort")
	requireB4JSONContains(t, latestResult, "live_readonly_rollout_get_after_action")

	refresh := callB4PortalJSON(t, api.handleEvidenceStoreRefresh, http.MethodPost, "/api/evidence-store/refresh", http.StatusOK)
	requireB4String(t, refresh, "schemaVersion", "evidence.store.refresh/v1alpha1")

	resultObject := callB4PortalJSON(t, api.handleEvidenceStoreObjectDetail, http.MethodGet, "/api/evidence/objects/runtimeActionExecutionResult/"+resultID+"?releaseId="+releaseID+"&includeRaw=true", http.StatusOK)
	requireB4String(t, resultObject, "schemaVersion", "evidence.store.object/v1alpha1")
	requireB4JSONContains(t, resultObject, "runtimeActionExecutionResult")
	requireB4JSONContains(t, resultObject, "ABORT_ROLLOUT")
	requireB4JSONContains(t, resultObject, "EXECUTION_SUCCEEDED")
	requireB4JSONContains(t, resultObject, "kubectl_argo_rollouts_abort")
	requireB4JSONContains(t, resultObject, "mutatedKubernetes")
	requireB4JSONContains(t, resultObject, "verificationStatus")
	requireB4JSONContains(t, resultObject, "VERIFIED")
	requireB4JSONContains(t, resultObject, "abortVerified")
	requireB4JSONContains(t, resultObject, "didAbort")
	requireB4JSONContains(t, resultObject, "postActionObserved")
	requireB4JSONContains(t, resultObject, "live_readonly_rollout_get_after_action")

	releaseDetail := callB4PortalJSON(t, api.handleEvidenceStoreReleaseDetail, http.MethodGet, "/api/evidence/releases/"+releaseID+"?includeRaw=true", http.StatusOK)
	requireB4String(t, releaseDetail, "schemaVersion", "evidence.store.release/v1alpha1")
	requireB4JSONContains(t, releaseDetail, "runtimeActionExecutionResult")
	requireB4JSONContains(t, releaseDetail, resultID)
	requireB4JSONContains(t, releaseDetail, "ABORT_ROLLOUT")
	requireB4JSONContains(t, releaseDetail, "verificationStatus")
	requireB4JSONContains(t, releaseDetail, "VERIFIED")
	requireB4JSONContains(t, releaseDetail, "abortVerified")
	requireB4JSONContains(t, releaseDetail, "didAbort")
}
