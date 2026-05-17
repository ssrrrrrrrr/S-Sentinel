package main

import (
	"encoding/json"
	"os"
	"path/filepath"
)

type ChangeGitSummary struct {
	BaseRef        string `json:"baseRef,omitempty"`
	PreviousCommit string `json:"previousCommit,omitempty"`
	CurrentCommit  string `json:"currentCommit,omitempty"`
	CommitMessage  string `json:"commitMessage,omitempty"`
}

type ChangeImageSummary struct {
	Previous string `json:"previous,omitempty"`
	Current  string `json:"current,omitempty"`
	Changed  bool   `json:"changed"`
}

type ChangeEnvChangeSummary struct {
	Name     string      `json:"name,omitempty"`
	Previous interface{} `json:"previous,omitempty"`
	Current  interface{} `json:"current,omitempty"`
	Changed  bool        `json:"changed"`
	Risk     string      `json:"risk,omitempty"`
}

type ChangeGenericChangeSummary struct {
	Name     string      `json:"name,omitempty"`
	Previous interface{} `json:"previous,omitempty"`
	Current  interface{} `json:"current,omitempty"`
	Changed  bool        `json:"changed"`
}

type ChangeContextSummary struct {
	File                   string                       `json:"file,omitempty"`
	SchemaVersion          string                       `json:"schemaVersion,omitempty"`
	GeneratedAt            string                       `json:"generatedAt,omitempty"`
	ChangeType             string                       `json:"changeType,omitempty"`
	App                    string                       `json:"app,omitempty"`
	Namespace              string                       `json:"namespace,omitempty"`
	Git                    ChangeGitSummary             `json:"git,omitempty"`
	Image                  ChangeImageSummary           `json:"image,omitempty"`
	EnvChanges             []ChangeEnvChangeSummary     `json:"envChanges,omitempty"`
	SLOGateChanges         []ChangeGenericChangeSummary `json:"sloGateChanges,omitempty"`
	RolloutStrategyChanged bool                         `json:"rolloutStrategyChanged,omitempty"`
	RiskLevel              string                       `json:"riskLevel,omitempty"`
	RiskScore              int                          `json:"riskScore,omitempty"`
	RiskHints              []string                     `json:"riskHints,omitempty"`
}

type rawChangeContext struct {
	SchemaVersion string `json:"schemaVersion"`
	GeneratedAt   string `json:"generatedAt"`
	ChangeType    string `json:"changeType"`
	App           string `json:"app"`
	Namespace     string `json:"namespace"`

	Git   ChangeGitSummary   `json:"git"`
	Image ChangeImageSummary `json:"image"`

	Env struct {
		Changes []ChangeEnvChangeSummary `json:"changes"`
	} `json:"env"`

	RolloutStrategy struct {
		Changed bool `json:"changed"`
	} `json:"rolloutStrategy"`

	SLOGates struct {
		Changes []ChangeGenericChangeSummary `json:"changes"`
	} `json:"sloGates"`

	Risk struct {
		Level string   `json:"level"`
		Score int      `json:"score"`
		Hints []string `json:"hints"`
	} `json:"risk"`
}

func loadLatestChangeContext(cfg Config) (*ChangeContextSummary, error) {
	reportDir := filepath.Join(cfg.RepoDir, "docs", "release-reports")
	path := filepath.Join(reportDir, "change-context-latest.json")

	data, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, nil
		}
		return nil, err
	}

	var raw rawChangeContext
	if err := json.Unmarshal(data, &raw); err != nil {
		return nil, err
	}

	summary := &ChangeContextSummary{
		File:                   path,
		SchemaVersion:          raw.SchemaVersion,
		GeneratedAt:            raw.GeneratedAt,
		ChangeType:             raw.ChangeType,
		App:                    raw.App,
		Namespace:              raw.Namespace,
		Git:                    raw.Git,
		Image:                  raw.Image,
		EnvChanges:             raw.Env.Changes,
		SLOGateChanges:         raw.SLOGates.Changes,
		RolloutStrategyChanged: raw.RolloutStrategy.Changed,
		RiskLevel:              raw.Risk.Level,
		RiskScore:              raw.Risk.Score,
		RiskHints:              raw.Risk.Hints,
	}

	return summary, nil
}
