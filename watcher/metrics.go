package main

import (
	"fmt"
	"net/http"
	"sync/atomic"
	"time"
)

var watcherChecksTotal atomic.Int64
var watcherTriggeredReportsTotal atomic.Int64
var watcherProcessedEventsTotal atomic.Int64
var watcherErrorsTotal atomic.Int64
var watcherLastCheckUnix atomic.Int64
var watcherWatchEventsTotal atomic.Int64
var watcherWatchRestartsTotal atomic.Int64

func incWatcherChecks() {
	watcherChecksTotal.Add(1)
	watcherLastCheckUnix.Store(time.Now().Unix())
}

func incWatcherTriggeredReports() {
	watcherTriggeredReportsTotal.Add(1)
}

func incWatcherProcessedEvents() {
	watcherProcessedEventsTotal.Add(1)
}

func incWatcherErrors() {
	watcherErrorsTotal.Add(1)
}

func incWatcherWatchEvents() {
	watcherWatchEventsTotal.Add(1)
}

func incWatcherWatchRestarts() {
	watcherWatchRestartsTotal.Add(1)
}

func writeMetrics(w http.ResponseWriter, r *http.Request) {
	ready := int64(0)
	if watcherReady.Load() {
		ready = 1
	}

	w.Header().Set("Content-Type", "text/plain; version=0.0.4; charset=utf-8")

	fmt.Fprintf(w, "# HELP rollout_watcher_ready Whether rollout watcher is ready. 1 means ready, 0 means not ready.\n")
	fmt.Fprintf(w, "# TYPE rollout_watcher_ready gauge\n")
	fmt.Fprintf(w, "rollout_watcher_ready %d\n", ready)

	fmt.Fprintf(w, "# HELP rollout_watcher_checks_total Total rollout check attempts.\n")
	fmt.Fprintf(w, "# TYPE rollout_watcher_checks_total counter\n")
	fmt.Fprintf(w, "rollout_watcher_checks_total %d\n", watcherChecksTotal.Load())

	fmt.Fprintf(w, "# HELP rollout_watcher_triggered_reports_total Total release report trigger attempts.\n")
	fmt.Fprintf(w, "# TYPE rollout_watcher_triggered_reports_total counter\n")
	fmt.Fprintf(w, "rollout_watcher_triggered_reports_total %d\n", watcherTriggeredReportsTotal.Load())

	fmt.Fprintf(w, "# HELP rollout_watcher_processed_events_total Total already processed rollout events observed.\n")
	fmt.Fprintf(w, "# TYPE rollout_watcher_processed_events_total counter\n")
	fmt.Fprintf(w, "rollout_watcher_processed_events_total %d\n", watcherProcessedEventsTotal.Load())

	fmt.Fprintf(w, "# HELP rollout_watcher_errors_total Total watcher errors.\n")
	fmt.Fprintf(w, "# TYPE rollout_watcher_errors_total counter\n")
	fmt.Fprintf(w, "rollout_watcher_errors_total %d\n", watcherErrorsTotal.Load())

	fmt.Fprintf(w, "# HELP rollout_watcher_watch_events_total Total Kubernetes watch events observed.\n")
	fmt.Fprintf(w, "# TYPE rollout_watcher_watch_events_total counter\n")
	fmt.Fprintf(w, "rollout_watcher_watch_events_total %d\n", watcherWatchEventsTotal.Load())

	fmt.Fprintf(w, "# HELP rollout_watcher_watch_restarts_total Total Kubernetes watch restart attempts.\n")
	fmt.Fprintf(w, "# TYPE rollout_watcher_watch_restarts_total counter\n")
	fmt.Fprintf(w, "rollout_watcher_watch_restarts_total %d\n", watcherWatchRestartsTotal.Load())

	fmt.Fprintf(w, "# HELP rollout_watcher_last_check_timestamp_seconds Last successful or attempted check unix timestamp.\n")
	fmt.Fprintf(w, "# TYPE rollout_watcher_last_check_timestamp_seconds gauge\n")
	fmt.Fprintf(w, "rollout_watcher_last_check_timestamp_seconds %d\n", watcherLastCheckUnix.Load())
}
