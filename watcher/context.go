package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strconv"
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
	GeneratedAt           string                `json:"generatedAt"`
	Namespace             string                `json:"namespace"`
	Rollout               string                `json:"rollout"`
	RolloutPhase          string                `json:"rolloutPhase"`
	RolloutAbort          bool                  `json:"rolloutAbort"`
	RolloutMessage        string                `json:"rolloutMessage"`
	StableReplicaSet      string                `json:"stableReplicaSet"`
	CurrentDesiredVersion string                `json:"currentDesiredVersion"`
	AnalysisRun           string                `json:"analysisRun"`
	AnalysisRunPhase      string                `json:"analysisRunPhase"`
	FailedMetric          string                `json:"failedMetric"`
	FailedMetrics         []string              `json:"failedMetrics"`
	AnalysisRunMetrics    []MetricResult        `json:"analysisRunMetrics"`
	Severity              string                `json:"severity"`
	RiskScore             int                   `json:"riskScore"`
	RiskReasons           []string              `json:"riskReasons"`
	ChangeContextFile     string                `json:"changeContextFile,omitempty"`
	ChangeRiskLevel       string                `json:"changeRiskLevel,omitempty"`
	ChangeRiskScore       int                   `json:"changeRiskScore,omitempty"`
	ChangeRiskHints       []string              `json:"changeRiskHints,omitempty"`
	ChangeContext         *ChangeContextSummary `json:"changeContext,omitempty"`
	Reason                string                `json:"reason"`
	Decision              string                `json:"decision"`
	RecommendedAction     string                `json:"recommendedAction"`
}

type ReleaseEventArchiveRecord struct {
	ID                    string   `json:"id"`
	GeneratedAt           string   `json:"generatedAt"`
	Namespace             string   `json:"namespace"`
	Rollout               string   `json:"rollout"`
	RolloutPhase          string   `json:"rolloutPhase"`
	RolloutAbort          bool     `json:"rolloutAbort"`
	StableReplicaSet      string   `json:"stableReplicaSet"`
	CurrentDesiredVersion string   `json:"currentDesiredVersion"`
	AnalysisRun           string   `json:"analysisRun"`
	AnalysisRunPhase      string   `json:"analysisRunPhase"`
	FailedMetrics         []string `json:"failedMetrics"`
	Severity              string   `json:"severity"`
	RiskScore             int      `json:"riskScore"`
	Decision              string   `json:"decision"`
	RecommendedAction     string   `json:"recommendedAction"`
	ContextFile           string   `json:"contextFile"`
}

func appendReleaseEventArchive(cfg Config, ctx ReleaseContext, contextFile string) error {
	reportDir := filepath.Join(cfg.RepoDir, "docs", "release-reports")
	if err := os.MkdirAll(reportDir, 0755); err != nil {
		return err
	}

	archivePath := filepath.Join(reportDir, "release-events.jsonl")

	record := ReleaseEventArchiveRecord{
		ID:                    ctx.GeneratedAt + ":" + ctx.Namespace + "/" + ctx.Rollout + ":" + ctx.AnalysisRun,
		GeneratedAt:           ctx.GeneratedAt,
		Namespace:             ctx.Namespace,
		Rollout:               ctx.Rollout,
		RolloutPhase:          ctx.RolloutPhase,
		RolloutAbort:          ctx.RolloutAbort,
		StableReplicaSet:      ctx.StableReplicaSet,
		CurrentDesiredVersion: ctx.CurrentDesiredVersion,
		AnalysisRun:           ctx.AnalysisRun,
		AnalysisRunPhase:      ctx.AnalysisRunPhase,
		FailedMetrics:         ctx.FailedMetrics,
		Severity:              ctx.Severity,
		RiskScore:             ctx.RiskScore,
		Decision:              ctx.Decision,
		RecommendedAction:     ctx.RecommendedAction,
		ContextFile:           contextFile,
	}

	data, err := json.Marshal(record)
	if err != nil {
		return err
	}

	f, err := os.OpenFile(archivePath, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0644)
	if err != nil {
		return err
	}
	defer f.Close()

	if _, err := f.Write(append(data, '\n')); err != nil {
		return err
	}

	return nil
}

func metricValueFloat(value string) (float64, bool) {
	v := strings.TrimSpace(value)
	v = strings.TrimPrefix(v, "[")
	v = strings.TrimSuffix(v, "]")

	if strings.Contains(v, ",") {
		v = strings.Split(v, ",")[0]
	}

	v = strings.TrimSpace(v)
	if v == "" {
		return 0, false
	}

	n, err := strconv.ParseFloat(v, 64)
	if err != nil {
		return 0, false
	}

	return n, true
}

func hasMetric(metrics []string, name string) bool {
	for _, m := range metrics {
		if m == name {
			return true
		}
	}
	return false
}

func metricByName(metrics []MetricResult, name string) *MetricResult {
	for i := range metrics {
		if metrics[i].Name == name {
			return &metrics[i]
		}
	}
	return nil
}

func calculateRisk(e WatchEvent) (string, int, []string) {
	score := 0
	reasons := []string{}

	if strings.EqualFold(e.RolloutPhase, "Degraded") {
		score += 25
		reasons = append(reasons, "rollout phase is Degraded")
	}

	if e.RolloutAbort {
		score += 25
		reasons = append(reasons, "rollout has been aborted")
	}

	if strings.EqualFold(e.AnalysisRunPhase, "Failed") || strings.EqualFold(e.AnalysisRunPhase, "Error") {
		score += 20
		reasons = append(reasons, "analysisRun phase is "+e.AnalysisRunPhase)
	}

	if hasMetric(e.FailedMetrics, "error-rate") {
		score += 20
		if m := metricByName(e.AnalysisRunMetrics, "error-rate"); m != nil {
			if v, ok := metricValueFloat(m.Value); ok {
				reasons = append(reasons, "error-rate is "+strconv.FormatFloat(v, 'f', 2, 64)+"%, above 5% threshold")
				if v >= 50 {
					score += 10
				}
			} else {
				reasons = append(reasons, "error-rate metric failed")
			}
		} else {
			reasons = append(reasons, "error-rate metric failed")
		}
	}

	if hasMetric(e.FailedMetrics, "p95-latency") {
		score += 15
		if m := metricByName(e.AnalysisRunMetrics, "p95-latency"); m != nil {
			if v, ok := metricValueFloat(m.Value); ok {
				reasons = append(reasons, "p95-latency is "+strconv.FormatFloat(v, 'f', 3, 64)+"s, above 0.3s threshold")
				if v >= 1 {
					score += 5
				}
			} else {
				reasons = append(reasons, "p95-latency metric failed")
			}
		} else {
			reasons = append(reasons, "p95-latency metric failed")
		}
	}

	if hasMetric(e.FailedMetrics, "request-count") {
		score += 10
		reasons = append(reasons, "request-count failed, sample size may be insufficient")
	}

	if hasMetric(e.FailedMetrics, "error-rate") && hasMetric(e.FailedMetrics, "p95-latency") {
		score += 10
		reasons = append(reasons, "multiple SLO gates failed in the same rollout")
	}

	if score > 100 {
		score = 100
	}

	severity := "low"
	switch {
	case score >= 85:
		severity = "critical"
	case score >= 65:
		severity = "high"
	case score >= 35:
		severity = "medium"
	default:
		severity = "low"
	}

	return severity, score, reasons
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

	severity, riskScore, riskReasons := calculateRisk(e)

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
		Severity:              severity,
		RiskScore:             riskScore,
		RiskReasons:           riskReasons,
		Reason:                e.Reason,
		Decision:              decision,
		RecommendedAction:     action,
	}
}

func writeReleaseContext(cfg Config, e WatchEvent) (string, error) {
	ctx := buildReleaseContext(e)

	if changeCtx, _ := loadLatestChangeContext(cfg); changeCtx != nil {
		ctx.ChangeContextFile = changeCtx.File
		ctx.ChangeRiskLevel = changeCtx.RiskLevel
		ctx.ChangeRiskScore = changeCtx.RiskScore
		ctx.ChangeRiskHints = changeCtx.RiskHints
		ctx.ChangeContext = changeCtx
	}

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

	if err := appendReleaseEventArchive(cfg, ctx, path); err != nil {
		return "", err
	}

	return path, nil
}
