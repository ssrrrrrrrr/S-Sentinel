package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"k8s.io/client-go/dynamic"
	"k8s.io/client-go/rest"
	"k8s.io/client-go/tools/clientcmd"
)

type WatchEvent struct {
	Key              string
	RolloutPhase     string
	RolloutMessage   string
	RolloutAbort     bool
	AnalysisRunName  string
	AnalysisRunPhase string
	Reason           string
}

type State struct {
	Processed []string `json:"processed"`
}

var (
	rolloutGVR = schema.GroupVersionResource{
		Group:    "argoproj.io",
		Version:  "v1alpha1",
		Resource: "rollouts",
	}

	analysisRunGVR = schema.GroupVersionResource{
		Group:    "argoproj.io",
		Version:  "v1alpha1",
		Resource: "analysisruns",
	}
)

func buildConfig() (*rest.Config, error) {
	if kubeconfig := os.Getenv("KUBECONFIG"); kubeconfig != "" {
		return clientcmd.BuildConfigFromFlags("", kubeconfig)
	}

	home, err := os.UserHomeDir()
	if err == nil {
		kubeconfig := filepath.Join(home, ".kube", "config")
		if _, statErr := os.Stat(kubeconfig); statErr == nil {
			return clientcmd.BuildConfigFromFlags("", kubeconfig)
		}
	}

	return rest.InClusterConfig()
}

func loadState(path string) State {
	data, err := os.ReadFile(path)
	if err != nil {
		return State{Processed: []string{}}
	}

	var s State
	if err := json.Unmarshal(data, &s); err != nil {
		return State{Processed: []string{}}
	}

	return s
}

func saveState(path string, s State) {
	data, _ := json.MarshalIndent(s, "", "  ")
	_ = os.MkdirAll(filepath.Dir(path), 0755)
	_ = os.WriteFile(path, data, 0644)
}

func contains(list []string, item string) bool {
	for _, v := range list {
		if v == item {
			return true
		}
	}
	return false
}

func tailKeep(list []string, max int) []string {
	if len(list) <= max {
		return list
	}
	return list[len(list)-max:]
}

func getString(obj *unstructured.Unstructured, fields ...string) string {
	v, found, _ := unstructured.NestedString(obj.Object, fields...)
	if !found {
		return ""
	}
	return v
}

func getBool(obj *unstructured.Unstructured, fields ...string) bool {
	v, found, _ := unstructured.NestedBool(obj.Object, fields...)
	if !found {
		return false
	}
	return v
}

func getInt64(obj *unstructured.Unstructured, fields ...string) int64 {
	v, found, _ := unstructured.NestedInt64(obj.Object, fields...)
	if !found {
		return 0
	}
	return v
}

func latestAnalysisRun(ctx context.Context, client dynamic.Interface, namespace string, rolloutName string) (*unstructured.Unstructured, error) {
	list, err := client.Resource(analysisRunGVR).Namespace(namespace).List(ctx, metav1.ListOptions{})
	if err != nil {
		return nil, err
	}

	var latest *unstructured.Unstructured
	var latestTime time.Time

	for i := range list.Items {
		item := &list.Items[i]
		name := item.GetName()

		matched := strings.HasPrefix(name, rolloutName+"-")

		for _, owner := range item.GetOwnerReferences() {
			if owner.Kind == "Rollout" && owner.Name == rolloutName {
				matched = true
				break
			}
		}

		if !matched {
			continue
		}

		t := item.GetCreationTimestamp().Time
		if latest == nil || t.After(latestTime) {
			latest = item
			latestTime = t
		}
	}

	return latest, nil
}

func buildEvent(rollout *unstructured.Unstructured, ar *unstructured.Unstructured) WatchEvent {
	phase := getString(rollout, "status", "phase")
	message := getString(rollout, "status", "message")
	abort := getBool(rollout, "status", "abort")

	observedGeneration := getInt64(rollout, "status", "observedGeneration")
	if observedGeneration == 0 {
		observedGeneration = rollout.GetGeneration()
	}

	arName := "none"
	arPhase := "none"

	if ar != nil {
		arName = ar.GetName()
		arPhase = getString(ar, "status", "phase")
	}

	reasons := []string{}

	if strings.EqualFold(phase, "Degraded") {
		reasons = append(reasons, "rollout phase is Degraded")
	}

	if abort {
		reasons = append(reasons, "rollout abort is true")
	}

	if strings.EqualFold(arPhase, "Failed") || strings.EqualFold(arPhase, "Error") {
		reasons = append(reasons, fmt.Sprintf("analysisrun %s phase is %s", arName, arPhase))
	}

	msgLower := strings.ToLower(message)
	if strings.Contains(msgLower, "abort") || strings.Contains(msgLower, "failed") {
		reasons = append(reasons, "rollout message contains failure signal")
	}

	key := fmt.Sprintf(
		"%s:%d:%s:%s:%s:%t",
		rollout.GetUID(),
		observedGeneration,
		arName,
		arPhase,
		phase,
		abort,
	)

	return WatchEvent{
		Key:              key,
		RolloutPhase:     phase,
		RolloutMessage:   message,
		RolloutAbort:     abort,
		AnalysisRunName:  arName,
		AnalysisRunPhase: arPhase,
		Reason:           strings.Join(reasons, "; "),
	}
}

func shouldTrigger(e WatchEvent) bool {
	return e.Reason != ""
}

func runScript(repoDir string, env []string, script string) error {
	cmd := exec.Command("bash", script)
	cmd.Dir = repoDir
	cmd.Env = env
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}

func runReportJob(repoDir string, ollamaURL string, model string, e WatchEvent) {
	log.Printf(
		"trigger report job: phase=%s abort=%v analysisrun=%s analysisrunPhase=%s reason=%s",
		e.RolloutPhase,
		e.RolloutAbort,
		e.AnalysisRunName,
		e.AnalysisRunPhase,
		e.Reason,
	)

	env := os.Environ()
	env = append(env, "OLLAMA_URL="+ollamaURL)
	env = append(env, "MODEL="+model)

	if err := runScript(repoDir, env, "scripts/collect-release-report.sh"); err != nil {
		log.Printf("collect-release-report.sh failed: %v", err)
	}

	if err := runScript(repoDir, env, "scripts/ai-release-advisor.sh"); err != nil {
		log.Printf("ai-release-advisor.sh failed: %v", err)
	}

	log.Printf("report job finished")
}

func main() {
	namespace := flag.String("namespace", "slo-rollout", "rollout namespace")
	rolloutName := flag.String("rollout", "demo-app", "rollout name")
	interval := flag.Duration("interval", 10*time.Second, "poll interval")
	repoDir := flag.String("repo-dir", "/root/slo-rollout-demo", "repository directory")
	stateFile := flag.String("state-file", "/root/slo-rollout-demo/docs/release-reports/go-rollout-watcher-state.json", "state file")
	ollamaURL := flag.String("ollama-url", "http://192.168.30.1:11434", "ollama api url")
	model := flag.String("model", "qwen2.5:3b", "ollama model")
	flag.Parse()

	cfg, err := buildConfig()
	if err != nil {
		log.Fatalf("failed to build kube config: %v", err)
	}

	client, err := dynamic.NewForConfig(cfg)
	if err != nil {
		log.Fatalf("failed to create dynamic client: %v", err)
	}

	log.Printf("go rollout watcher started: namespace=%s rollout=%s interval=%s", *namespace, *rolloutName, interval.String())

	for {
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)

		rollout, err := client.Resource(rolloutGVR).Namespace(*namespace).Get(ctx, *rolloutName, metav1.GetOptions{})
		if err != nil {
			log.Printf("failed to get rollout: %v", err)
			cancel()
			time.Sleep(*interval)
			continue
		}

		ar, err := latestAnalysisRun(ctx, client, *namespace, *rolloutName)
		if err != nil {
			log.Printf("failed to list analysisruns: %v", err)
		}

		event := buildEvent(rollout, ar)

		log.Printf(
			"check: rolloutPhase=%s abort=%v analysisRun=%s analysisRunPhase=%s",
			event.RolloutPhase,
			event.RolloutAbort,
			event.AnalysisRunName,
			event.AnalysisRunPhase,
		)

		if shouldTrigger(event) {
			state := loadState(*stateFile)

			if contains(state.Processed, event.Key) {
				log.Printf("event already processed: %s", event.Key)
			} else {
				runReportJob(*repoDir, *ollamaURL, *model, event)

				state.Processed = append(state.Processed, event.Key)
				state.Processed = tailKeep(state.Processed, 100)
				saveState(*stateFile, state)
			}
		}

		cancel()
		time.Sleep(*interval)
	}
}
