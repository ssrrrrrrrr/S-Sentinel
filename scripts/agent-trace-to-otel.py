#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


def now_utc() -> str:
    return datetime.now(timezone.utc).isoformat()


def load_json(path: Path) -> dict[str, Any]:
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise SystemExit(f"ERROR: expected JSON object: {path}")
    return data


def write_json(path: Path, data: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def as_dict(value: Any) -> dict[str, Any]:
    return value if isinstance(value, dict) else {}


def as_list(value: Any) -> list[Any]:
    return value if isinstance(value, list) else []


def first_non_empty(*values: Any) -> Any:
    for value in values:
        if value not in (None, ""):
            return value
    return None


def slug(value: Any) -> str:
    raw = str(value or "unknown").strip()
    normalized = re.sub(r"[^A-Za-z0-9_.:-]+", "-", raw).strip("-")
    return normalized or "unknown"


def span_id(prefix: str, release_id: str, extra: str | int | None = None) -> str:
    parts = ["span", slug(prefix)]
    if extra is not None:
        parts.append(slug(extra))
    parts.append(slug(release_id))
    return "-".join(parts)


def clean_attrs(attrs: dict[str, Any]) -> dict[str, Any]:
    return {k: v for k, v in attrs.items() if v is not None}


def has_meaningful_value(value: Any) -> bool:
    if value is None:
        return False
    if isinstance(value, str):
        return bool(value)
    if isinstance(value, (list, dict)):
        return bool(value)
    return True


def find_latest_agent_trace(report_dir: Path) -> Path:
    candidates = [
        path for path in report_dir.glob("agent-trace-*.json")
        if path.name != "agent-trace-latest.json"
    ]
    if not candidates:
        raise SystemExit(f"ERROR: no agent-trace-*.json found under {report_dir}")
    return max(candidates, key=lambda path: path.stat().st_mtime)


def resolve_input(input_arg: str, report_dir: Path) -> Path:
    if input_arg == "latest":
        return find_latest_agent_trace(report_dir)

    path = Path(input_arg)
    if path.is_file():
        return path

    report_path = report_dir / input_arg
    if report_path.is_file():
        return report_path

    raise SystemExit(f"ERROR: input AgentTrace file does not exist: {input_arg}")


def build_bundle(agent_trace_path: Path) -> dict[str, Any]:
    trace = load_json(agent_trace_path)

    if trace.get("schemaVersion") != "agent.trace/v1alpha1":
        raise SystemExit(
            "ERROR: unsupported source schemaVersion: "
            f"{trace.get('schemaVersion')!r}"
        )

    release = as_dict(trace.get("release"))
    correlation = as_dict(trace.get("correlation"))
    agent_run = as_dict(trace.get("agentRun"))
    policy_trace = as_dict(trace.get("policyTrace"))
    signed_gate_trace = as_dict(trace.get("signedReleaseGateTrace"))
    evidence_trace = as_dict(trace.get("evidenceTrace"))

    release_id = str(first_non_empty(trace.get("releaseId"), release.get("releaseId"), "unknown-release"))
    trace_id = str(first_non_empty(trace.get("traceId"), f"trace-{release_id}"))
    agent_trace_id = str(first_non_empty(trace.get("agentTraceId"), f"at-{release_id}"))
    generated_at = now_utc()
    source_generated_at = str(first_non_empty(trace.get("generatedAt"), generated_at))

    root_span_id = span_id("agent-root", release_id)

    spans: list[dict[str, Any]] = []

    def add_span(
        name: str,
        sid: str,
        parent: str | None,
        attrs: dict[str, Any],
        status_code: str = "OK",
        status_message: str | None = None,
        events: list[dict[str, Any]] | None = None,
        links: list[dict[str, Any]] | None = None,
    ) -> None:
        status: dict[str, Any] = {"code": status_code}
        if status_message is not None:
            status["message"] = status_message

        spans.append({
            "traceId": trace_id,
            "spanId": sid,
            "parentSpanId": parent,
            "name": name,
            "kind": "internal",
            "startTime": source_generated_at,
            "endTime": generated_at,
            "status": status,
            "attributes": clean_attrs(attrs),
            "events": events or [],
            "links": links or [],
        })

    add_span(
        "ssentinel.agent.run",
        root_span_id,
        None,
        {
            "ssentinel.release_id": release_id,
            "ssentinel.trace_id": trace_id,
            "ssentinel.agent_trace_id": agent_trace_id,
            "ssentinel.agent_run_id": first_non_empty(correlation.get("agentRunId"), agent_run.get("agentRunId")),
            "ssentinel.release_result": agent_run.get("releaseResult"),
            "ssentinel.recommended_action": agent_run.get("recommendedAction"),
            "ssentinel.requires_human_approval": agent_run.get("requiresHumanApproval"),
            "ssentinel.service": release.get("service"),
            "ssentinel.env": release.get("env"),
            "ssentinel.namespace": release.get("namespace"),
            "ssentinel.version": release.get("version"),
            "ssentinel.commit": release.get("commit"),
            "ssentinel.image_digest": release.get("imageDigest"),
            "ssentinel.source_schema_version": trace.get("schemaVersion"),
        },
        status_code="OK" if agent_run.get("status") == "COMPLETED" else "UNSET",
    )

    if policy_trace:
        runtime = as_dict(policy_trace.get("runtime"))
        add_span(
            "ssentinel.policy.evaluate",
            span_id("policy", release_id),
            root_span_id,
            {
                "ssentinel.policy_decision_id": first_non_empty(
                    policy_trace.get("policyDecisionId"),
                    correlation.get("policyDecisionId"),
                ),
                "ssentinel.policy_runtime_result_id": first_non_empty(
                    policy_trace.get("policyRuntimeResultId"),
                    correlation.get("policyRuntimeResultId"),
                ),
                "ssentinel.policy_decision": policy_trace.get("policyDecision"),
                "ssentinel.final_action": policy_trace.get("finalAction"),
                "ssentinel.allowed": policy_trace.get("allowed"),
                "ssentinel.requires_human_approval": policy_trace.get("requiresHumanApproval"),
                "ssentinel.matched_rules": as_list(policy_trace.get("matchedRules")),
                "ssentinel.policy_runtime_name": runtime.get("name"),
                "ssentinel.policy_runtime_adapter": runtime.get("adapter"),
                "ssentinel.policy_runtime_mode": runtime.get("mode"),
            },
        )

    if any(has_meaningful_value(v) for v in signed_gate_trace.values()):
        add_span(
            "ssentinel.signed_release_gate.evaluate",
            span_id("signed-release-gate", release_id),
            root_span_id,
            {
                "ssentinel.signed_release_gate_id": first_non_empty(
                    signed_gate_trace.get("signedReleaseGateId"),
                    correlation.get("signedReleaseGateId"),
                ),
                "ssentinel.signed_release_gate_decision": signed_gate_trace.get("decision"),
                "ssentinel.allowed": signed_gate_trace.get("allowed"),
                "ssentinel.requires_human_approval": signed_gate_trace.get("requiresHumanApproval"),
                "ssentinel.risk_level": signed_gate_trace.get("riskLevel"),
                "ssentinel.risk_score": signed_gate_trace.get("riskScore"),
                "ssentinel.source": signed_gate_trace.get("source"),
            },
        )

    for index, tool_call in enumerate(as_list(trace.get("toolCallTraces"))):
        if not isinstance(tool_call, dict):
            continue

        tool_name = str(first_non_empty(tool_call.get("name"), f"tool-{index}"))
        add_span(
            f"ssentinel.tool_call.{slug(tool_name)}",
            span_id("tool", release_id, f"{tool_name}-{index}"),
            root_span_id,
            {
                "ssentinel.tool_call.name": tool_name,
                "ssentinel.tool_call.tool": tool_call.get("tool"),
                "ssentinel.tool_call.status": tool_call.get("status"),
                "ssentinel.tool_call.input_ref": tool_call.get("inputRef"),
                "ssentinel.tool_call.output_ref": tool_call.get("outputRef"),
                "ssentinel.tool_call.summary": as_dict(tool_call.get("summary")),
                "ssentinel.read_only": tool_call.get("readOnly"),
                "ssentinel.will_execute": tool_call.get("willExecute"),
            },
            status_code="OK" if tool_call.get("status") == "AVAILABLE" else "UNSET",
        )

    if evidence_trace:
        add_span(
            "ssentinel.evidence.link",
            span_id("evidence", release_id),
            root_span_id,
            {
                "ssentinel.evidence.release_evidence": evidence_trace.get("releaseEvidence"),
                "ssentinel.evidence.ai_decision": evidence_trace.get("aiDecision"),
                "ssentinel.evidence.policy_decision": evidence_trace.get("policyDecision"),
                "ssentinel.evidence.policy_runtime_result": evidence_trace.get("policyRuntimeResult"),
                "ssentinel.evidence.signed_release_gate": evidence_trace.get("signedReleaseGate"),
                "ssentinel.evidence.available_object_types": as_list(evidence_trace.get("availableObjectTypes")),
            },
        )

    span_names = [span["name"] for span in spans]

    return {
        "schemaVersion": "otel.span.bundle/v1alpha1",
        "kind": "OtelSpanBundle",
        "traceId": trace_id,
        "rootSpanId": root_span_id,
        "releaseId": release_id,
        "generatedBy": "agent-trace-to-otel.py",
        "generatedAt": generated_at,
        "source": {
            "kind": "AgentTrace",
            "schemaVersion": "agent.trace/v1alpha1",
            "agentTraceId": agent_trace_id,
            "path": str(agent_trace_path),
        },
        "resource": {
            "service": release.get("service"),
            "env": release.get("env"),
            "namespace": release.get("namespace"),
            "version": release.get("version"),
            "commit": release.get("commit"),
            "imageDigest": release.get("imageDigest"),
        },
        "spans": spans,
        "summary": {
            "spanCount": len(spans),
            "hasRootSpan": any(span["spanId"] == root_span_id and span["parentSpanId"] is None for span in spans),
            "sourceAgentTraceId": agent_trace_id,
            "releaseId": release_id,
            "spanNames": span_names,
        },
        "guardrails": {
            "localFileOnly": True,
            "doesNotSendExternalTelemetry": True,
            "doesNotCallExternalCollector": True,
            "doesNotModifyCluster": True,
            "doesNotModifyGitOps": True,
            "doesNotCommitOrPush": True,
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Convert S Sentinel AgentTrace JSON into a local OTel-style span bundle."
    )
    parser.add_argument("input", nargs="?", default="latest", help="AgentTrace JSON path, file name under report dir, or latest")
    parser.add_argument("--report-dir", default=os.environ.get("RELEASE_REPORT_DIR", "docs/release-reports"))
    parser.add_argument("--output-dir", default=os.environ.get("AGENT_OTEL_OUTPUT_DIR"))
    parser.add_argument("--output-file", default=os.environ.get("AGENT_OTEL_OUTPUT_FILE"))
    args = parser.parse_args()

    report_dir = Path(args.report_dir)
    output_dir = Path(args.output_dir) if args.output_dir else report_dir
    agent_trace_path = resolve_input(args.input, report_dir)

    bundle = build_bundle(agent_trace_path)
    release_id = bundle["releaseId"]

    output_file = Path(args.output_file) if args.output_file else output_dir / f"otel-span-bundle-{release_id}.json"
    latest = output_file.parent / "otel-span-bundle-latest.json"

    write_json(output_file, bundle)
    shutil.copyfile(output_file, latest)

    print(json.dumps({
        "schemaVersion": "otel.span.bundle.build/v1alpha1",
        "otelSpanBundle": str(output_file),
        "latest": str(latest),
        "traceId": bundle["traceId"],
        "rootSpanId": bundle["rootSpanId"],
        "releaseId": release_id,
        "sourceAgentTraceId": bundle["source"]["agentTraceId"],
        "spanCount": bundle["summary"]["spanCount"],
        "guardrails": bundle["guardrails"],
    }, ensure_ascii=False, indent=2))

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
