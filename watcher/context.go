package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"time"
)

type MetricResult struct {
	Name         string `json:"name"`
	Phase        string `json:"phase"`
	Message      string `json:"message"`
	Value        string `json:"value,omitempty"`
	Successful   int64  `json:"successful"`
	Failed       int64  `json:"failed"`
	Inconclusive int64  `json:"inconclusive"`
	Error        int64  `json:"error"`
}

type ReleaseContext struct {
	GeneratedAt           string         `json:"generatedAt"`
	Namespace             string         `json:"namespace"`
	Rollout               string         `json:"rollout"`
	RolloutPhase          string         `json:"rolloutPhase"`
	RolloutAbort          bool           `json:"rolloutAbort"`
	RolloutMessage        string         `json:"rolloutMessage"`
	StableReplicaSet      string         `json:"stableReplicaSet"`
	CurrentDesiredVersion string         `json:"currentDesiredVersion"`
	AnalysisRun           string         `json:"analysisRun"`
	AnalysisRunPhase      string         `json:"analysisRunPhase"`
	FailedMetric          string         `json:"failedMetric"`
	FailedMetrics         []string       `json:"failedMetrics"`
	AnalysisRunMetrics    []MetricResult `json:"analysisRunMetrics"`
	Reason                string         `json:"reason"`
	Decision              string         `json:"decision"`
	RecommendedAction     string         `json:"recommendedAction"`
}

func buildReleaseContext(e WatchEvent) ReleaseContext {
	decision := "unknown"
	action := "manual_check"

	reasonLower := strings.ToLower(e.Reason)

	if strings.Contains(reasonLower, "degraded") ||
		strings.Contains(reasonLower, "failed") ||
		e.RolloutAbort {
		decision = "release_failed_or_aborted"
		action = "stop_promotion_and_investigate"
	}

	failedMetric := e.FailedMetric
	if failedMetric == "" {
		failedMetric = "unknown"
	}

	failedMetrics := e.FailedMetrics
	if len(failedMetrics) == 0 && failedMetric != "unknown" {
		failedMetrics = []string{failedMetric}
	}

	return ReleaseContext{
		GeneratedAt:           time.Now().Format(time.RFC3339),
		Namespace:             e.Namespace,
		Rollout:               e.RolloutName,
		RolloutPhase:          e.RolloutPhase,
		RolloutAbort:          e.RolloutAbort,
		RolloutMessage:        e.RolloutMessage,
		StableReplicaSet:      e.StableReplicaSet,
		CurrentDesiredVersion: e.CurrentDesiredVersion,
		AnalysisRun:           e.AnalysisRunName,
		AnalysisRunPhase:      e.AnalysisRunPhase,
		FailedMetric:          failedMetric,
		FailedMetrics:         failedMetrics,
		AnalysisRunMetrics:    e.AnalysisRunMetrics,
		Reason:                e.Reason,
		Decision:              decision,
		RecommendedAction:     action,
	}
}

func writeReleaseContext(cfg Config, e WatchEvent) (string, error) {
	ctx := buildReleaseContext(e)

	reportDir := filepath.Join(cfg.RepoDir, "docs", "release-reports")
	if err := os.MkdirAll(reportDir, 0755); err != nil {
		return "", err
	}

	name := "release-context-" + time.Now().Format("20060102-150405") + ".json"
	path := filepath.Join(reportDir, name)

	data, err := json.MarshalIndent(ctx, "", "  ")
	if err != nil {
		return "", err
	}

	if err := os.WriteFile(path, data, 0644); err != nil {
		return "", err
	}

	return path, nil
}
