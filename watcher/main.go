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

	"gopkg.in/yaml.v3"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"k8s.io/client-go/dynamic"
	"k8s.io/client-go/rest"
	"k8s.io/client-go/tools/clientcmd"
)

type Target struct {
	Namespace string `yaml:"namespace"`
	Rollout   string `yaml:"rollout"`
}

type Config struct {
	Namespace string   `yaml:"namespace"`
	Rollout   string   `yaml:"rollout"`
	Targets   []Target `yaml:"targets"`

	Interval  string `yaml:"interval"`
	RepoDir   string `yaml:"repoDir"`
	StateFile string `yaml:"stateFile"`
	OllamaURL string `yaml:"ollamaUrl"`
	Model     string `yaml:"model"`
}

type WatchEvent struct {
	Key              string
	Namespace        string
	RolloutName      string
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

func defaultConfig() Config {
	return Config{
		Interval:  "10s",
		RepoDir:   "/root/slo-rollout-demo",
		StateFile: "/root/slo-rollout-demo/docs/release-reports/go-rollout-watcher-state.json",
		OllamaURL: "http://192.168.30.1:11434",
		Model:     "qwen2.5:3b",
		Targets: []Target{
			{
				Namespace: "slo-rollout",
				Rollout:   "demo-app",
			},
		},
	}
}

func loadConfig(path string) (Config, error) {
	cfg := defaultConfig()

	if path != "" {
		data, err := os.ReadFile(path)
		if err != nil {
			return cfg, err
		}

		if err := yaml.Unmarshal(data, &cfg); err != nil {
			return cfg, err
		}
	}

	def := defaultConfig()

	if cfg.Interval == "" {
		cfg.Interval = def.Interval
	}
	if cfg.RepoDir == "" {
		cfg.RepoDir = def.RepoDir
	}
	if cfg.StateFile == "" {
		cfg.StateFile = def.StateFile
	}
	if cfg.OllamaURL == "" {
		cfg.OllamaURL = def.OllamaURL
	}
	if cfg.Model == "" {
		cfg.Model = def.Model
	}

	// 兼容旧配置：namespace + rollout
	if len(cfg.Targets) == 0 && cfg.Namespace != "" && cfg.Rollout != "" {
		cfg.Targets = []Target{
			{
				Namespace: cfg.Namespace,
				Rollout:   cfg.Rollout,
			},
		}
	}

	// 如果没有任何 target，就使用默认 target
	if len(cfg.Targets) == 0 {
		cfg.Targets = def.Targets
	}

	return cfg, nil
}

func buildKubeConfig() (*rest.Config, error) {
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

func latestAnalysisRun(ctx context.Context, client dynamic.Interface, target Target) (*unstructured.Unstructured, error) {
	list, err := client.Resource(analysisRunGVR).Namespace(target.Namespace).List(ctx, metav1.ListOptions{})
	if err != nil {
		return nil, err
	}

	var latest *unstructured.Unstructured
	var latestTime time.Time

	for i := range list.Items {
		item := &list.Items[i]
		name := item.GetName()

		matched := strings.HasPrefix(name, target.Rollout+"-")

		for _, owner := range item.GetOwnerReferences() {
			if owner.Kind == "Rollout" && owner.Name == target.Rollout {
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

func buildEvent(target Target, rollout *unstructured.Unstructured, ar *unstructured.Unstructured) WatchEvent {
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
		"%s/%s:%s:%d:%s:%s:%s:%t",
		target.Namespace,
		target.Rollout,
		rollout.GetUID(),
		observedGeneration,
		arName,
		arPhase,
		phase,
		abort,
	)

	return WatchEvent{
		Key:              key,
		Namespace:        target.Namespace,
		RolloutName:      target.Rollout,
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

func runReportJob(cfg Config, e WatchEvent) {
	log.Printf(
		"trigger report job: namespace=%s rollout=%s phase=%s abort=%v analysisrun=%s analysisrunPhase=%s reason=%s",
		e.Namespace,
		e.RolloutName,
		e.RolloutPhase,
		e.RolloutAbort,
		e.AnalysisRunName,
		e.AnalysisRunPhase,
		e.Reason,
	)

	env := os.Environ()
	env = append(env, "OLLAMA_URL="+cfg.OllamaURL)
	env = append(env, "MODEL="+cfg.Model)

	// 先传给脚本，后面我们会把 collect-release-report.sh 改成 target-aware。
	env = append(env, "RELEASE_NAMESPACE="+e.Namespace)
	env = append(env, "RELEASE_ROLLOUT="+e.RolloutName)

	if err := runScript(cfg.RepoDir, env, "scripts/collect-release-report.sh"); err != nil {
		log.Printf("collect-release-report.sh failed: %v", err)
	}

	if err := runScript(cfg.RepoDir, env, "scripts/ai-release-advisor.sh"); err != nil {
		log.Printf("ai-release-advisor.sh failed: %v", err)
	}

	log.Printf("report job finished")
}

func processTarget(ctx context.Context, client dynamic.Interface, cfg Config, target Target) {
	rollout, err := client.Resource(rolloutGVR).Namespace(target.Namespace).Get(ctx, target.Rollout, metav1.GetOptions{})
	if err != nil {
		log.Printf("failed to get rollout %s/%s: %v", target.Namespace, target.Rollout, err)
		return
	}

	ar, err := latestAnalysisRun(ctx, client, target)
	if err != nil {
		log.Printf("failed to list analysisruns for %s/%s: %v", target.Namespace, target.Rollout, err)
	}

	event := buildEvent(target, rollout, ar)

	log.Printf(
		"check: namespace=%s rollout=%s rolloutPhase=%s abort=%v analysisRun=%s analysisRunPhase=%s",
		event.Namespace,
		event.RolloutName,
		event.RolloutPhase,
		event.RolloutAbort,
		event.AnalysisRunName,
		event.AnalysisRunPhase,
	)

	if !shouldTrigger(event) {
		return
	}

	state := loadState(cfg.StateFile)

	if contains(state.Processed, event.Key) {
		log.Printf("event already processed: %s", event.Key)
		return
	}

	runReportJob(cfg, event)

	state.Processed = append(state.Processed, event.Key)
	state.Processed = tailKeep(state.Processed, 100)
	saveState(cfg.StateFile, state)
}

func main() {
	configPath := flag.String("config", "", "config yaml path")

	namespaceOverride := flag.String("namespace", "", "override single rollout namespace")
	rolloutOverride := flag.String("rollout", "", "override single rollout name")
	intervalOverride := flag.String("interval", "", "override poll interval, example: 10s")
	repoDirOverride := flag.String("repo-dir", "", "override repository directory")
	stateFileOverride := flag.String("state-file", "", "override state file")
	ollamaURLOverride := flag.String("ollama-url", "", "override ollama api url")
	modelOverride := flag.String("model", "", "override ollama model")

	flag.Parse()

	cfg, err := loadConfig(*configPath)
	if err != nil {
		log.Fatalf("failed to load config: %v", err)
	}

	// 命令行覆盖：如果传了 namespace + rollout，则只监听这个单 target。
	if *namespaceOverride != "" && *rolloutOverride != "" {
		cfg.Targets = []Target{
			{
				Namespace: *namespaceOverride,
				Rollout:   *rolloutOverride,
			},
		}
	}

	if *intervalOverride != "" {
		cfg.Interval = *intervalOverride
	}
	if *repoDirOverride != "" {
		cfg.RepoDir = *repoDirOverride
	}
	if *stateFileOverride != "" {
		cfg.StateFile = *stateFileOverride
	}
	if *ollamaURLOverride != "" {
		cfg.OllamaURL = *ollamaURLOverride
	}
	if *modelOverride != "" {
		cfg.Model = *modelOverride
	}

	interval, err := time.ParseDuration(cfg.Interval)
	if err != nil {
		log.Fatalf("invalid interval %q: %v", cfg.Interval, err)
	}

	kubeCfg, err := buildKubeConfig()
	if err != nil {
		log.Fatalf("failed to build kube config: %v", err)
	}

	client, err := dynamic.NewForConfig(kubeCfg)
	if err != nil {
		log.Fatalf("failed to create dynamic client: %v", err)
	}

	log.Printf(
		"go rollout watcher started: targets=%d interval=%s repoDir=%s stateFile=%s model=%s ollamaURL=%s",
		len(cfg.Targets),
		interval.String(),
		cfg.RepoDir,
		cfg.StateFile,
		cfg.Model,
		cfg.OllamaURL,
	)

	for _, target := range cfg.Targets {
		log.Printf("watch target: namespace=%s rollout=%s", target.Namespace, target.Rollout)
	}

	for {
		ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)

		for _, target := range cfg.Targets {
			processTarget(ctx, client, cfg, target)
		}

		cancel()
		time.Sleep(interval)
	}
}
