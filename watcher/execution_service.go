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

type ExecutionServiceConfig struct {
	RepoDir   string
	ReportDir string
}

type ExecutionService struct {
	cfg     ExecutionServiceConfig
	runtime ExecutionRuntime
}

type ExecutionRuntime interface {
	Descriptor() ExecutionRuntimeDescriptor
	ScriptFile() string
	ShellBin() string
	RunNoop(ctx context.Context, releaseEvidenceFile string) ([]byte, error)
}

type ExecutionRuntimeDescriptor struct {
	RuntimeID             string `json:"runtimeId"`
	RuntimeType           string `json:"runtimeType"`
	Mode                  string `json:"mode"`
	Backend               string `json:"backend"`
	Adapter               string `json:"adapter"`
	ContractVersion       string `json:"contractVersion"`
	ReadOnly              bool   `json:"readOnly"`
	WillExecute           bool   `json:"willExecute"`
	SupportsNoopExecution bool   `json:"supportsNoopExecution"`
	AutoBuildsPreview     bool   `json:"autoBuildsPreview"`
	MutatesLocalEvidence  bool   `json:"mutatesLocalEvidence"`
	DoesNotModifyCluster  bool   `json:"doesNotModifyCluster"`
	DoesNotModifyGitOps   bool   `json:"doesNotModifyGitOps"`
	DoesNotTriggerRollout bool   `json:"doesNotTriggerRollout"`
	Description           string `json:"description"`
}

func NewExecutionService(cfg Config, reportDir string) *ExecutionService {
	return &ExecutionService{
		cfg: ExecutionServiceConfig{
			RepoDir:   cfg.RepoDir,
			ReportDir: reportDir,
		},
		runtime: NewCLIExecutionRuntime(cfg.RepoDir),
	}
}

func (api *portalAPI) executionService() *ExecutionService {
	if api.executionSvc != nil {
		return api.executionSvc
	}

	return NewExecutionService(api.cfg, api.reportDir)
}

func (svc *ExecutionService) serviceContract() map[string]interface{} {
	return map[string]interface{}{
		"name":                  "s-sentinel-noop-executor-api",
		"schemaVersion":         "execution.service/v1alpha1",
		"contractVersion":       "execution.api.service/v1alpha1",
		"role":                  "policy-bound-noop-executor-control-plane",
		"readOnly":              false,
		"willExecute":           false,
		"doesNotModifyCluster":  true,
		"doesNotModifyGitOps":   true,
		"doesNotTriggerRollout": true,
	}
}

func (svc *ExecutionService) runtimePaths() map[string]interface{} {
	return map[string]interface{}{
		"repoDir":     svc.cfg.RepoDir,
		"reportDir":   svc.cfg.ReportDir,
		"scriptFile":  svc.runtime.ScriptFile(),
		"shellBinary": svc.runtime.ShellBin(),
	}
}

func (svc *ExecutionService) capabilities() map[string]interface{} {
	descriptor := svc.runtime.Descriptor()

	return map[string]interface{}{
		"runNoopExecution":          descriptor.SupportsNoopExecution,
		"autoBuildsPreview":         descriptor.AutoBuildsPreview,
		"mutatesLocalEvidence":      descriptor.MutatesLocalEvidence,
		"doesNotModifyCluster":      descriptor.DoesNotModifyCluster,
		"doesNotModifyGitOps":       descriptor.DoesNotModifyGitOps,
		"doesNotTriggerRollout":     descriptor.DoesNotTriggerRollout,
		"executionResultReader":     true,
		"evidenceRecordEmitter":     true,
		"gitopsAdapterReceipt":      true,
		"gitopsDeliveryWorkspace":   true,
		"gitopsAdapterRun":          true,
		"gitopsAdapterPickup":       true,
		"gitopsAdapterPickupAck":    true,
		"gitopsAdapterHandoffState": true,
		"gitopsAdapterPickupEvent":  true,
		"futureExecutorAdapter":     false,
		"approvalAwareExecutor":     true,
	}
}

func (svc *ExecutionService) ControlPlaneMetadataForOperation(operation string, mutatesLocalEvidence bool) map[string]interface{} {
	descriptor := svc.runtime.Descriptor()

	return map[string]interface{}{
		"schemaVersion":             "execution.api.controlPlane/v1alpha1",
		"apiVersion":                "s-sentinel.io/execution-api/v1alpha1",
		"contractVersion":           "execution.api.response/v1alpha1",
		"generatedAt":               time.Now().Format(time.RFC3339),
		"generatedBy":               "s-sentinel-noop-executor-api",
		"operation":                 operation,
		"service":                   svc.serviceContract(),
		"runtime":                   descriptor,
		"paths":                     svc.runtimePaths(),
		"capabilities":              svc.capabilities(),
		"readOnly":                  operation != "noop",
		"willExecute":               false,
		"doesNotModifyCluster":      true,
		"doesNotModifyGitOps":       true,
		"doesNotTriggerRollout":     true,
		"mutatesLocalEvidenceFiles": mutatesLocalEvidence,
		"mutationSemantics": map[string]interface{}{
			"doesNotModifyCluster":      true,
			"doesNotModifyGitOps":       true,
			"doesNotTriggerRollout":     true,
			"mutatesLocalEvidenceFiles": mutatesLocalEvidence,
		},
	}
}

func (svc *ExecutionService) Status(ctx context.Context) map[string]interface{} {
	_ = ctx

	latestReleaseEvidenceFile, _ := svc.resolveReleaseEvidenceFile("")
	latestExecutionPreviewFile, _ := svc.findLatestReportFile("execution-preview-*.json", "execution-preview-latest.json")
	latestExecutionResultFile, _ := svc.findLatestReportFile("execution-result-*.json", "execution-result-latest.json")
	latestGitOpsProposalFile, _ := svc.findLatestReportFile("gitops-patch-proposal-*.json", "gitops-patch-proposal-latest.json")
	latestGitOpsBundleFile, _ := svc.findLatestReportFile("gitops-pr-bundle-*.json", "gitops-pr-bundle-latest.json")
	latestGitOpsHandoffFile, _ := svc.findLatestReportFile("gitops-handoff-bundle-*.json", "gitops-handoff-bundle-latest.json")
	latestGitOpsAdapterRequestFile, _ := svc.findLatestReportFile("gitops-adapter-request-*.json", "gitops-adapter-request-latest.json")
	latestGitOpsAdapterResultFile, _ := svc.findLatestReportFile("gitops-adapter-result-*.json", "gitops-adapter-result-latest.json")
	latestGitOpsAdapterDeliveryFile, _ := svc.findLatestReportFile("gitops-adapter-delivery-*.json", "gitops-adapter-delivery-latest.json")
	latestGitOpsAdapterRunFile, _ := svc.findLatestReportFile("gitops-adapter-run-*.json", "gitops-adapter-run-latest.json")
	latestGitOpsAdapterPickupFile, _ := svc.findLatestReportFile("gitops-adapter-pickup-*.json", "gitops-adapter-pickup-latest.json")
	latestGitOpsAdapterPickupAckFile, _ := svc.findLatestReportFile("gitops-adapter-pickup-ack-*.json", "gitops-adapter-pickup-ack-latest.json")
	latestGitOpsAdapterHandoffStateFile, _ := svc.findLatestReportFile("gitops-adapter-handoff-state-*.json", "gitops-adapter-handoff-state-latest.json")
	latestGitOpsAdapterPickupEventFile, _ := svc.findLatestReportFile("gitops-adapter-pickup-event-*.json", "gitops-adapter-pickup-event-latest.json")
	latestEvidenceRecordFile, _ := svc.findLatestReportFile("evidence-record-*.json", "evidence-record-latest.json")

	ready := false
	if scriptFile := svc.runtime.ScriptFile(); scriptFile != "" {
		if _, err := os.Stat(scriptFile); err == nil {
			ready = true
		}
	}

	body := map[string]interface{}{
		"schemaVersion":                   "execution.noop.status/v1alpha1",
		"generatedAt":                     time.Now().Format(time.RFC3339),
		"mode":                            svc.runtime.Descriptor().Mode,
		"service":                         svc.serviceContract(),
		"runtime":                         svc.runtime.Descriptor(),
		"paths":                           svc.runtimePaths(),
		"capabilities":                    svc.capabilities(),
		"controlPlane":                    svc.ControlPlaneMetadataForOperation("status", false),
		"ready":                           ready,
		"readOnly":                        true,
		"willExecute":                     false,
		"doesNotModifyCluster":            true,
		"doesNotModifyGitOps":             true,
		"doesNotTriggerRollout":           true,
		"mutatesLocalEvidenceFiles":       false,
		"latestReleaseEvidenceFile":       latestReleaseEvidenceFile,
		"latestExecutionPreviewFile":      latestExecutionPreviewFile,
		"latestExecutionResultFile":       latestExecutionResultFile,
		"latestGitOpsProposalFile":        latestGitOpsProposalFile,
		"latestGitOpsBundleFile":          latestGitOpsBundleFile,
		"latestGitOpsHandoffFile":         latestGitOpsHandoffFile,
		"latestGitOpsAdapterRequest":      latestGitOpsAdapterRequestFile,
		"latestGitOpsAdapterResult":       latestGitOpsAdapterResultFile,
		"latestGitOpsAdapterDelivery":     latestGitOpsAdapterDeliveryFile,
		"latestGitOpsAdapterRun":          latestGitOpsAdapterRunFile,
		"latestGitOpsAdapterPickup":       latestGitOpsAdapterPickupFile,
		"latestGitOpsAdapterPickupAck":    latestGitOpsAdapterPickupAckFile,
		"latestGitOpsAdapterHandoffState": latestGitOpsAdapterHandoffStateFile,
		"latestGitOpsAdapterPickupEvent":  latestGitOpsAdapterPickupEventFile,
		"latestEvidenceRecordFile":        latestEvidenceRecordFile,
	}

	if latestResult := svc.readJSONFile(latestExecutionResultFile); latestResult != nil {
		body["latestExecutionResult"] = latestResult
	}

	return body
}

func (svc *ExecutionService) Latest(ctx context.Context) (map[string]interface{}, error) {
	_ = ctx

	latestExecutionResultFile, err := svc.findLatestReportFile("execution-result-*.json", "execution-result-latest.json")
	if err != nil {
		return nil, err
	}

	latestExecutionResult := svc.readJSONFile(latestExecutionResultFile)
	if latestExecutionResult == nil {
		return nil, fmt.Errorf("failed to decode execution result: %s", latestExecutionResultFile)
	}

	body := map[string]interface{}{
		"schemaVersion":             "execution.noop.latest/v1alpha1",
		"generatedAt":               time.Now().Format(time.RFC3339),
		"runtime":                   svc.runtime.Descriptor(),
		"controlPlane":              svc.ControlPlaneMetadataForOperation("latest", false),
		"readOnly":                  true,
		"willExecute":               false,
		"doesNotModifyCluster":      true,
		"doesNotModifyGitOps":       true,
		"doesNotTriggerRollout":     true,
		"mutatesLocalEvidenceFiles": false,
		"latestExecutionResultFile": latestExecutionResultFile,
		"executionResult":           latestExecutionResult,
	}

	if latestEvidenceRecordFile, recordErr := svc.findLatestReportFile("evidence-record-*.json", "evidence-record-latest.json"); recordErr == nil {
		body["latestEvidenceRecordFile"] = latestEvidenceRecordFile
	}
	if latestGitOpsProposalFile, proposalErr := svc.findLatestReportFile("gitops-patch-proposal-*.json", "gitops-patch-proposal-latest.json"); proposalErr == nil {
		body["latestGitOpsProposalFile"] = latestGitOpsProposalFile
	}
	if latestGitOpsBundleFile, bundleErr := svc.findLatestReportFile("gitops-pr-bundle-*.json", "gitops-pr-bundle-latest.json"); bundleErr == nil {
		body["latestGitOpsBundleFile"] = latestGitOpsBundleFile
	}
	if latestGitOpsHandoffFile, handoffErr := svc.findLatestReportFile("gitops-handoff-bundle-*.json", "gitops-handoff-bundle-latest.json"); handoffErr == nil {
		body["latestGitOpsHandoffFile"] = latestGitOpsHandoffFile
	}
	if latestGitOpsAdapterRequestFile, adapterErr := svc.findLatestReportFile("gitops-adapter-request-*.json", "gitops-adapter-request-latest.json"); adapterErr == nil {
		body["latestGitOpsAdapterRequestFile"] = latestGitOpsAdapterRequestFile
	}
	if latestGitOpsAdapterResultFile, adapterResultErr := svc.findLatestReportFile("gitops-adapter-result-*.json", "gitops-adapter-result-latest.json"); adapterResultErr == nil {
		body["latestGitOpsAdapterResultFile"] = latestGitOpsAdapterResultFile
		if latestGitOpsAdapterResult := svc.readJSONFile(latestGitOpsAdapterResultFile); latestGitOpsAdapterResult != nil {
			body["gitOpsAdapterResult"] = latestGitOpsAdapterResult
		}
	}
	if latestGitOpsAdapterDeliveryFile, adapterDeliveryErr := svc.findLatestReportFile("gitops-adapter-delivery-*.json", "gitops-adapter-delivery-latest.json"); adapterDeliveryErr == nil {
		body["latestGitOpsAdapterDeliveryFile"] = latestGitOpsAdapterDeliveryFile
		if latestGitOpsAdapterDelivery := svc.readJSONFile(latestGitOpsAdapterDeliveryFile); latestGitOpsAdapterDelivery != nil {
			body["gitOpsAdapterDelivery"] = latestGitOpsAdapterDelivery
		}
	}
	if latestGitOpsAdapterRunFile, adapterRunErr := svc.findLatestReportFile("gitops-adapter-run-*.json", "gitops-adapter-run-latest.json"); adapterRunErr == nil {
		body["latestGitOpsAdapterRunFile"] = latestGitOpsAdapterRunFile
		if latestGitOpsAdapterRun := svc.readJSONFile(latestGitOpsAdapterRunFile); latestGitOpsAdapterRun != nil {
			body["gitOpsAdapterRun"] = latestGitOpsAdapterRun
		}
	}
	if latestGitOpsAdapterPickupFile, adapterPickupErr := svc.findLatestReportFile("gitops-adapter-pickup-*.json", "gitops-adapter-pickup-latest.json"); adapterPickupErr == nil {
		body["latestGitOpsAdapterPickupFile"] = latestGitOpsAdapterPickupFile
		if latestGitOpsAdapterPickup := svc.readJSONFile(latestGitOpsAdapterPickupFile); latestGitOpsAdapterPickup != nil {
			body["gitOpsAdapterPickup"] = latestGitOpsAdapterPickup
		}
	}
	if latestGitOpsAdapterPickupAckFile, adapterPickupAckErr := svc.findLatestReportFile("gitops-adapter-pickup-ack-*.json", "gitops-adapter-pickup-ack-latest.json"); adapterPickupAckErr == nil {
		body["latestGitOpsAdapterPickupAckFile"] = latestGitOpsAdapterPickupAckFile
		if latestGitOpsAdapterPickupAck := svc.readJSONFile(latestGitOpsAdapterPickupAckFile); latestGitOpsAdapterPickupAck != nil {
			body["gitOpsAdapterPickupAck"] = latestGitOpsAdapterPickupAck
		}
	}
	if latestGitOpsAdapterHandoffStateFile, handoffStateErr := svc.findLatestReportFile("gitops-adapter-handoff-state-*.json", "gitops-adapter-handoff-state-latest.json"); handoffStateErr == nil {
		body["latestGitOpsAdapterHandoffStateFile"] = latestGitOpsAdapterHandoffStateFile
		if latestGitOpsAdapterHandoffState := svc.readJSONFile(latestGitOpsAdapterHandoffStateFile); latestGitOpsAdapterHandoffState != nil {
			body["gitOpsAdapterHandoffState"] = latestGitOpsAdapterHandoffState
		}
	}
	if latestGitOpsAdapterPickupEventFile, pickupEventErr := svc.findLatestReportFile("gitops-adapter-pickup-event-*.json", "gitops-adapter-pickup-event-latest.json"); pickupEventErr == nil {
		body["latestGitOpsAdapterPickupEventFile"] = latestGitOpsAdapterPickupEventFile
		if latestGitOpsAdapterPickupEvent := svc.readJSONFile(latestGitOpsAdapterPickupEventFile); latestGitOpsAdapterPickupEvent != nil {
			body["gitOpsAdapterPickupEvent"] = latestGitOpsAdapterPickupEvent
		}
	}

	return body, nil
}

func (svc *ExecutionService) RunNoop(ctx context.Context, releaseID string) (map[string]interface{}, error) {
	releaseEvidenceFile, err := svc.resolveReleaseEvidenceFile(releaseID)
	if err != nil {
		return nil, err
	}

	output, err := svc.runtime.RunNoop(ctx, releaseEvidenceFile)
	if err != nil {
		return nil, err
	}

	releaseEvidence := svc.readJSONFile(releaseEvidenceFile)
	releaseEvidenceID := extractString(releaseEvidence, "releaseId")
	if releaseEvidenceID == "" {
		releaseEvidenceID = releaseID
	}

	executionResultFile := ""
	if releaseEvidence != nil {
		if artifacts, ok := releaseEvidence["artifacts"].(map[string]interface{}); ok {
			executionResultFile = strings.TrimSpace(extractString(artifacts, "executionResult"))
		}
	}
	if executionResultFile == "" && releaseEvidenceID != "" {
		candidate := filepath.Join(svc.cfg.ReportDir, "execution-result-"+releaseEvidenceID+".json")
		if _, statErr := os.Stat(candidate); statErr == nil {
			executionResultFile = candidate
		}
	}

	evidenceRecordFile := ""
	if releaseEvidenceID != "" {
		candidate := filepath.Join(svc.cfg.ReportDir, "evidence-record-"+releaseEvidenceID+".json")
		if _, statErr := os.Stat(candidate); statErr == nil {
			evidenceRecordFile = candidate
		}
	}

	gitOpsProposalFile := ""
	if releaseEvidence != nil {
		if artifacts, ok := releaseEvidence["artifacts"].(map[string]interface{}); ok {
			gitOpsProposalFile = strings.TrimSpace(extractString(artifacts, "gitopsPatchProposal"))
		}
	}
	if gitOpsProposalFile == "" && releaseEvidenceID != "" {
		candidate := filepath.Join(svc.cfg.ReportDir, "gitops-patch-proposal-"+releaseEvidenceID+".json")
		if _, statErr := os.Stat(candidate); statErr == nil {
			gitOpsProposalFile = candidate
		}
	}

	gitOpsBundleFile := ""
	if releaseEvidence != nil {
		if artifacts, ok := releaseEvidence["artifacts"].(map[string]interface{}); ok {
			gitOpsBundleFile = strings.TrimSpace(extractString(artifacts, "gitopsPRBundle"))
		}
	}
	if gitOpsBundleFile == "" && releaseEvidenceID != "" {
		candidate := filepath.Join(svc.cfg.ReportDir, "gitops-pr-bundle-"+releaseEvidenceID+".json")
		if _, statErr := os.Stat(candidate); statErr == nil {
			gitOpsBundleFile = candidate
		}
	}

	gitOpsHandoffFile := ""
	if releaseEvidence != nil {
		if artifacts, ok := releaseEvidence["artifacts"].(map[string]interface{}); ok {
			gitOpsHandoffFile = strings.TrimSpace(extractString(artifacts, "gitopsHandoffBundle"))
		}
	}
	if gitOpsHandoffFile == "" && releaseEvidenceID != "" {
		candidate := filepath.Join(svc.cfg.ReportDir, "gitops-handoff-bundle-"+releaseEvidenceID+".json")
		if _, statErr := os.Stat(candidate); statErr == nil {
			gitOpsHandoffFile = candidate
		}
	}

	gitOpsAdapterRequestFile := ""
	if releaseEvidence != nil {
		if artifacts, ok := releaseEvidence["artifacts"].(map[string]interface{}); ok {
			gitOpsAdapterRequestFile = strings.TrimSpace(extractString(artifacts, "gitopsAdapterRequest"))
		}
	}
	if gitOpsAdapterRequestFile == "" && releaseEvidenceID != "" {
		candidate := filepath.Join(svc.cfg.ReportDir, "gitops-adapter-request-"+releaseEvidenceID+".json")
		if _, statErr := os.Stat(candidate); statErr == nil {
			gitOpsAdapterRequestFile = candidate
		}
	}

	gitOpsAdapterResultFile := ""
	if releaseEvidence != nil {
		if artifacts, ok := releaseEvidence["artifacts"].(map[string]interface{}); ok {
			gitOpsAdapterResultFile = strings.TrimSpace(extractString(artifacts, "gitopsAdapterResult"))
		}
	}
	if gitOpsAdapterResultFile == "" && releaseEvidenceID != "" {
		candidate := filepath.Join(svc.cfg.ReportDir, "gitops-adapter-result-"+releaseEvidenceID+".json")
		if _, statErr := os.Stat(candidate); statErr == nil {
			gitOpsAdapterResultFile = candidate
		}
	}

	gitOpsAdapterDeliveryFile := ""
	if releaseEvidence != nil {
		if artifacts, ok := releaseEvidence["artifacts"].(map[string]interface{}); ok {
			gitOpsAdapterDeliveryFile = strings.TrimSpace(extractString(artifacts, "gitopsAdapterDelivery"))
		}
	}
	if gitOpsAdapterDeliveryFile == "" && releaseEvidenceID != "" {
		candidate := filepath.Join(svc.cfg.ReportDir, "gitops-adapter-delivery-"+releaseEvidenceID+".json")
		if _, statErr := os.Stat(candidate); statErr == nil {
			gitOpsAdapterDeliveryFile = candidate
		}
	}

	gitOpsAdapterRunFile := ""
	if releaseEvidence != nil {
		if artifacts, ok := releaseEvidence["artifacts"].(map[string]interface{}); ok {
			gitOpsAdapterRunFile = strings.TrimSpace(extractString(artifacts, "gitopsAdapterRun"))
		}
	}

	gitOpsAdapterPickupFile := ""
	if releaseEvidence != nil {
		if artifacts, ok := releaseEvidence["artifacts"].(map[string]interface{}); ok {
			gitOpsAdapterPickupFile = strings.TrimSpace(extractString(artifacts, "gitopsAdapterPickup"))
		}
	}

	gitOpsAdapterPickupAckFile := ""
	if releaseEvidence != nil {
		if artifacts, ok := releaseEvidence["artifacts"].(map[string]interface{}); ok {
			gitOpsAdapterPickupAckFile = strings.TrimSpace(extractString(artifacts, "gitopsAdapterPickupAck"))
		}
	}
	if gitOpsAdapterPickupAckFile == "" && releaseEvidenceID != "" {
		candidate := filepath.Join(svc.cfg.ReportDir, "gitops-adapter-pickup-ack-"+releaseEvidenceID+".json")
		if _, statErr := os.Stat(candidate); statErr == nil {
			gitOpsAdapterPickupAckFile = candidate
		}
	}
	if gitOpsAdapterPickupFile == "" && releaseEvidenceID != "" {
		candidate := filepath.Join(svc.cfg.ReportDir, "gitops-adapter-pickup-"+releaseEvidenceID+".json")
		if _, statErr := os.Stat(candidate); statErr == nil {
			gitOpsAdapterPickupFile = candidate
		}
	}
	gitOpsAdapterHandoffStateFile := ""
	if releaseEvidence != nil {
		if artifacts, ok := releaseEvidence["artifacts"].(map[string]interface{}); ok {
			gitOpsAdapterHandoffStateFile = strings.TrimSpace(extractString(artifacts, "gitopsAdapterHandoffState"))
		}
	}
	if gitOpsAdapterHandoffStateFile == "" && releaseEvidenceID != "" {
		candidate := filepath.Join(svc.cfg.ReportDir, "gitops-adapter-handoff-state-"+releaseEvidenceID+".json")
		if _, statErr := os.Stat(candidate); statErr == nil {
			gitOpsAdapterHandoffStateFile = candidate
		}
	}
	gitOpsAdapterPickupEventFile := ""
	if releaseEvidence != nil {
		if artifacts, ok := releaseEvidence["artifacts"].(map[string]interface{}); ok {
			gitOpsAdapterPickupEventFile = strings.TrimSpace(extractString(artifacts, "gitopsAdapterPickupEvent"))
		}
	}
	if gitOpsAdapterPickupEventFile == "" && releaseEvidenceID != "" {
		candidate := filepath.Join(svc.cfg.ReportDir, "gitops-adapter-pickup-event-"+releaseEvidenceID+".json")
		if _, statErr := os.Stat(candidate); statErr == nil {
			gitOpsAdapterPickupEventFile = candidate
		}
	}
	if gitOpsAdapterRunFile == "" && releaseEvidenceID != "" {
		candidate := filepath.Join(svc.cfg.ReportDir, "gitops-adapter-run-"+releaseEvidenceID+".json")
		if _, statErr := os.Stat(candidate); statErr == nil {
			gitOpsAdapterRunFile = candidate
		}
	}

	body := map[string]interface{}{
		"schemaVersion":                 "execution.noop.run/v1alpha1",
		"generatedAt":                   time.Now().Format(time.RFC3339),
		"operation":                     "noop",
		"runtime":                       svc.runtime.Descriptor(),
		"controlPlane":                  svc.ControlPlaneMetadataForOperation("noop", true),
		"readOnly":                      false,
		"willExecute":                   false,
		"doesNotModifyCluster":          true,
		"doesNotModifyGitOps":           true,
		"doesNotTriggerRollout":         true,
		"mutatesLocalEvidenceFiles":     true,
		"releaseEvidenceFile":           releaseEvidenceFile,
		"executionResultFile":           executionResultFile,
		"gitOpsProposalFile":            gitOpsProposalFile,
		"gitOpsBundleFile":              gitOpsBundleFile,
		"gitOpsHandoffFile":             gitOpsHandoffFile,
		"gitOpsAdapterRequestFile":      gitOpsAdapterRequestFile,
		"gitOpsAdapterResultFile":       gitOpsAdapterResultFile,
		"gitOpsAdapterDeliveryFile":     gitOpsAdapterDeliveryFile,
		"gitOpsAdapterRunFile":          gitOpsAdapterRunFile,
		"gitOpsAdapterPickupFile":       gitOpsAdapterPickupFile,
		"gitOpsAdapterPickupAckFile":    gitOpsAdapterPickupAckFile,
		"gitOpsAdapterHandoffStateFile": gitOpsAdapterHandoffStateFile,
		"gitOpsAdapterPickupEventFile":  gitOpsAdapterPickupEventFile,
		"evidenceRecordFile":            evidenceRecordFile,
		"scriptOutput":                  decodeExecutionOutput(output),
	}

	if releaseEvidence != nil {
		body["releaseEvidence"] = releaseEvidence
	}
	if executionResult := svc.readJSONFile(executionResultFile); executionResult != nil {
		body["executionResult"] = executionResult
	}
	if gitOpsProposal := svc.readJSONFile(gitOpsProposalFile); gitOpsProposal != nil {
		body["gitOpsProposal"] = gitOpsProposal
	}
	if gitOpsBundle := svc.readJSONFile(gitOpsBundleFile); gitOpsBundle != nil {
		body["gitOpsBundle"] = gitOpsBundle
	}
	if gitOpsHandoff := svc.readJSONFile(gitOpsHandoffFile); gitOpsHandoff != nil {
		body["gitOpsHandoff"] = gitOpsHandoff
	}
	if gitOpsAdapterRequest := svc.readJSONFile(gitOpsAdapterRequestFile); gitOpsAdapterRequest != nil {
		body["gitOpsAdapterRequest"] = gitOpsAdapterRequest
	}
	if gitOpsAdapterResult := svc.readJSONFile(gitOpsAdapterResultFile); gitOpsAdapterResult != nil {
		body["gitOpsAdapterResult"] = gitOpsAdapterResult
	}
	if gitOpsAdapterDelivery := svc.readJSONFile(gitOpsAdapterDeliveryFile); gitOpsAdapterDelivery != nil {
		body["gitOpsAdapterDelivery"] = gitOpsAdapterDelivery
	}
	if gitOpsAdapterRun := svc.readJSONFile(gitOpsAdapterRunFile); gitOpsAdapterRun != nil {
		body["gitOpsAdapterRun"] = gitOpsAdapterRun
	}
	if gitOpsAdapterPickup := svc.readJSONFile(gitOpsAdapterPickupFile); gitOpsAdapterPickup != nil {
		body["gitOpsAdapterPickup"] = gitOpsAdapterPickup
	}
	if gitOpsAdapterPickupAck := svc.readJSONFile(gitOpsAdapterPickupAckFile); gitOpsAdapterPickupAck != nil {
		body["gitOpsAdapterPickupAck"] = gitOpsAdapterPickupAck
	}
	if gitOpsAdapterHandoffState := svc.readJSONFile(gitOpsAdapterHandoffStateFile); gitOpsAdapterHandoffState != nil {
		body["gitOpsAdapterHandoffState"] = gitOpsAdapterHandoffState
	}
	if gitOpsAdapterPickupEvent := svc.readJSONFile(gitOpsAdapterPickupEventFile); gitOpsAdapterPickupEvent != nil {
		body["gitOpsAdapterPickupEvent"] = gitOpsAdapterPickupEvent
	}
	if evidenceRecord := svc.readJSONFile(evidenceRecordFile); evidenceRecord != nil {
		body["evidenceRecord"] = evidenceRecord
	}

	return body, nil
}

func (svc *ExecutionService) resolveReleaseEvidenceFile(releaseID string) (string, error) {
	releaseID = strings.TrimSpace(releaseID)
	if releaseID != "" {
		path := filepath.Join(svc.cfg.ReportDir, "release-evidence-"+releaseID+".json")
		if _, err := os.Stat(path); err != nil {
			if os.IsNotExist(err) {
				return "", fmt.Errorf("release evidence file not found for releaseId=%s", releaseID)
			}

			return "", fmt.Errorf("failed to inspect release evidence file %s: %w", path, err)
		}

		return path, nil
	}

	return svc.findLatestReportFile("release-evidence-*.json", "release-evidence-latest.json")
}

func (svc *ExecutionService) findLatestReportFile(pattern string, latestName string) (string, error) {
	latestFile := filepath.Join(svc.cfg.ReportDir, latestName)
	if info, err := os.Stat(latestFile); err == nil && !info.IsDir() {
		return latestFile, nil
	}

	matches, err := filepath.Glob(filepath.Join(svc.cfg.ReportDir, pattern))
	if err != nil {
		return "", fmt.Errorf("glob report files %s: %w", pattern, err)
	}

	type candidate struct {
		path string
		mod  time.Time
	}

	var latest candidate
	found := false

	for _, match := range matches {
		base := filepath.Base(match)
		if strings.Contains(base, "-latest.") {
			continue
		}

		info, err := os.Stat(match)
		if err != nil || info.IsDir() {
			continue
		}

		if !found || info.ModTime().After(latest.mod) {
			found = true
			latest = candidate{path: match, mod: info.ModTime()}
		}
	}

	if !found {
		return "", fmt.Errorf("no report files found for pattern %s", pattern)
	}

	return latest.path, nil
}

func (svc *ExecutionService) readJSONFile(path string) map[string]interface{} {
	path = strings.TrimSpace(path)
	if path == "" {
		return nil
	}

	data, err := os.ReadFile(path)
	if err != nil {
		return nil
	}

	doc := map[string]interface{}{}
	if err := json.Unmarshal(data, &doc); err != nil {
		return nil
	}

	return doc
}

func decodeExecutionOutput(output []byte) interface{} {
	trimmed := strings.TrimSpace(string(output))
	if trimmed == "" {
		return ""
	}

	doc := map[string]interface{}{}
	if err := json.Unmarshal([]byte(trimmed), &doc); err == nil {
		return doc
	}

	return trimmed
}

func extractString(object map[string]interface{}, key string) string {
	if object == nil {
		return ""
	}

	value, ok := object[key]
	if !ok || value == nil {
		return ""
	}

	if text, ok := value.(string); ok {
		return strings.TrimSpace(text)
	}

	return strings.TrimSpace(fmt.Sprint(value))
}

type CLIExecutionRuntime struct {
	repoDir string
}

func NewCLIExecutionRuntime(repoDir string) *CLIExecutionRuntime {
	return &CLIExecutionRuntime{repoDir: repoDir}
}

func (runtime *CLIExecutionRuntime) Descriptor() ExecutionRuntimeDescriptor {
	return ExecutionRuntimeDescriptor{
		RuntimeID:             "noop-executor-cli",
		RuntimeType:           "cli-backed-noop-executor",
		Mode:                  "noop-executor-runtime",
		Backend:               "local-file",
		Adapter:               "bash-cli",
		ContractVersion:       "execution.runtime/v1alpha1",
		ReadOnly:              false,
		WillExecute:           false,
		SupportsNoopExecution: true,
		AutoBuildsPreview:     true,
		MutatesLocalEvidence:  true,
		DoesNotModifyCluster:  true,
		DoesNotModifyGitOps:   true,
		DoesNotTriggerRollout: true,
		Description:           "Compatibility runtime that orchestrates preview-only execution evidence through scripts/run-noop-executor.sh.",
	}
}

func (runtime *CLIExecutionRuntime) ScriptFile() string {
	if scriptFile := strings.TrimSpace(os.Getenv("S_SENTINEL_NOOP_EXECUTOR_SCRIPT")); scriptFile != "" {
		return scriptFile
	}

	return filepath.Join(runtime.repoDir, "scripts", "run-noop-executor.sh")
}

func (runtime *CLIExecutionRuntime) ShellBin() string {
	if shellBin := strings.TrimSpace(os.Getenv("S_SENTINEL_BASH_BIN")); shellBin != "" {
		return shellBin
	}

	return "bash"
}

func (runtime *CLIExecutionRuntime) RunNoop(ctx context.Context, releaseEvidenceFile string) ([]byte, error) {
	scriptFile := runtime.ScriptFile()
	if _, err := os.Stat(scriptFile); err != nil {
		return nil, fmt.Errorf("noop executor script unavailable: %s: %w", scriptFile, err)
	}

	cmd := exec.CommandContext(ctx, runtime.ShellBin(), scriptFile, releaseEvidenceFile)
	cmd.Dir = runtime.repoDir

	var stdout bytes.Buffer
	var stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	if err := cmd.Run(); err != nil {
		return stdout.Bytes(), fmt.Errorf("noop executor command failed: %w: %s", err, strings.TrimSpace(stderr.String()))
	}

	return stdout.Bytes(), nil
}
