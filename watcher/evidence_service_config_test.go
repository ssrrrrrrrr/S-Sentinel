package main

import (
	"path/filepath"
	"testing"
)

func TestEvidenceServiceUsesConfiguredRuntimePaths(t *testing.T) {
	t.Setenv("S_SENTINEL_EVIDENCE_STORE_DB", "")
	t.Setenv("S_SENTINEL_EVIDENCE_STORE_SCRIPT", "")
	t.Setenv("S_SENTINEL_PYTHON_BIN", "")
	t.Setenv("S_SENTINEL_EVIDENCE_STORE_REFRESH_STATE_FILE", "")

	root := t.TempDir()

	cfg := Config{
		RepoDir:                       filepath.Join(root, "repo"),
		ReportDir:                     filepath.Join(root, "reports"),
		EvidenceStoreDB:               filepath.Join(root, "store", "portal-evidence-store.db"),
		EvidenceStoreScriptFile:       filepath.Join(root, "scripts", "custom-evidence-store.py"),
		EvidenceStorePython:           "custom-python",
		EvidenceStoreRefreshStateFile: filepath.Join(root, "store", "portal-evidence-store-refresh.json"),
	}

	api := &portalAPI{
		cfg:       cfg,
		reportDir: cfg.ReportDir,
	}

	svc := api.evidenceService()

	assertEqual := func(name, got, want string) {
		t.Helper()
		if got != want {
			t.Fatalf("%s mismatch: got %q want %q", name, got, want)
		}
	}

	assertEqual("reportDir", svc.cfg.ReportDir, cfg.ReportDir)
	assertEqual("dbFile", svc.DBFile(), cfg.EvidenceStoreDB)
	assertEqual("scriptFile", svc.ScriptFile(), cfg.EvidenceStoreScriptFile)
	assertEqual("pythonBin", svc.PythonBin(), cfg.EvidenceStorePython)
	assertEqual("refreshStateFile", svc.RefreshStateFile(), cfg.EvidenceStoreRefreshStateFile)
}
