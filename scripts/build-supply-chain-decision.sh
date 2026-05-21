#!/usr/bin/env bash
set -euo pipefail

REPORT_DIR="${RELEASE_REPORT_DIR:-docs/release-reports}"
INPUT_FILE="${1:-latest}"
GITOPS_ROLLOUT_FILE="${GITOPS_ROLLOUT_FILE:-deploy/base/rollout.yaml}"

usage() {
  cat <<'USAGE'
Usage:
  scripts/build-supply-chain-decision.sh [latest|RELEASE_CONTEXT_JSON|RELEASE_EVIDENCE_JSON]

Environment:
  RELEASE_REPORT_DIR                  Optional report directory.
  SUPPLY_CHAIN_DECISION_OUTPUT_DIR    Optional output directory.
  SUPPLY_CHAIN_DECISION_OUTPUT_FILE   Optional exact output file.
  GITOPS_ROLLOUT_FILE                 Optional GitOps rollout manifest path. Defaults to deploy/base/rollout.yaml.

Behavior:
  - Reads release context directly, or release evidence and its artifacts.releaseContext.
  - Reads GitOps rollout manifest if available.
  - Generates supply-chain-decision-*.json and supply-chain-decision-latest.json.
  - Performs read-only supply-chain safety checks.
  - Does not modify Kubernetes, GitOps manifests, images, commits, or pushes.
USAGE
}

if [ "${INPUT_FILE:-}" = "-h" ] || [ "${INPUT_FILE:-}" = "--help" ]; then
  usage
  exit 0
fi

if [ "$#" -gt 1 ]; then
  echo "ERROR: too many arguments" >&2
  usage >&2
  exit 1
fi

if [ "$INPUT_FILE" = "latest" ] || [ -z "$INPUT_FILE" ]; then
  INPUT_FILE="$(ls -t "$REPORT_DIR"/release-evidence-*.json 2>/dev/null | grep -v 'release-evidence-latest.json' | head -1 || true)"
fi

if [ -z "$INPUT_FILE" ] || [ ! -f "$INPUT_FILE" ]; then
  echo "ERROR: input file does not exist: ${INPUT_FILE:-not provided}" >&2
  exit 1
fi

BASENAME="$(basename "$INPUT_FILE")"

case "$BASENAME" in
  release-evidence-*.json)
    SUFFIX="${BASENAME#release-evidence-}"
    ;;
  release-context-*.json)
    SUFFIX="${BASENAME#release-context-}"
    ;;
  *)
    SUFFIX="$(date +%Y%m%d-%H%M%S).json"
    ;;
esac

OUTPUT_DIR="${SUPPLY_CHAIN_DECISION_OUTPUT_DIR:-$(dirname "$INPUT_FILE")}"
mkdir -p "$OUTPUT_DIR"

OUTPUT_JSON="${SUPPLY_CHAIN_DECISION_OUTPUT_FILE:-$OUTPUT_DIR/supply-chain-decision-$SUFFIX}"
LATEST_JSON="$OUTPUT_DIR/supply-chain-decision-latest.json"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

validate_generated_release_contract() {
  local contract_file="${1:-}"
  local helper="${RELEASE_CONTRACT_VALIDATOR_HELPER:-$SCRIPT_DIR/validate-generated-release-contract.sh}"

  if [ "${RELEASE_CONTRACT_VALIDATION_MODE:-warn}" = "off" ]; then
    return 0
  fi

  if [ -f "$helper" ]; then
    bash "$helper" "$contract_file"
  else
    echo "WARN: release contract validator helper not found: $helper" >&2
  fi
}

python3 - "$INPUT_FILE" "$GITOPS_ROLLOUT_FILE" "$OUTPUT_JSON" "$LATEST_JSON" <<'PY_SUPPLY_CHAIN'
from __future__ import annotations

import json
import re
import shutil
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

try:
    import yaml
except Exception:
    yaml = None

input_path = Path(sys.argv[1])
gitops_manifest_path = Path(sys.argv[2]) if sys.argv[2] else None
output_json = Path(sys.argv[3])
latest_json = Path(sys.argv[4])

def now() -> str:
    return datetime.now(timezone.utc).isoformat()

def load_json(path: Path | None) -> dict[str, Any]:
    if not path or not path.exists():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8-sig"))
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}

def as_dict(value: Any) -> dict[str, Any]:
    return value if isinstance(value, dict) else {}

def nullable_string(value: Any) -> str | None:
    if value is None:
        return None
    text = str(value).strip()
    return text if text else None

def first_not_none(*values: Any) -> Any:
    for value in values:
        if value not in (None, ""):
            return value
    return None

def resolve_ref(ref: Any, base_path: Path) -> Path | None:
    if not ref:
        return None
    p = Path(str(ref))
    candidates: list[Path] = []
    if p.is_absolute():
        candidates.append(p)
    candidates.extend([
        Path.cwd() / p,
        base_path.parent / p,
        p,
    ])
    for candidate in candidates:
        if candidate.exists() and candidate.is_file():
            return candidate
    return None

def parse_image_ref(image: str | None) -> dict[str, Any]:
    if not image:
        return {
            "image": None,
            "imageTag": None,
            "imageDigest": None,
            "usesDigestReference": False,
            "usesMutableTag": False,
        }

    raw = str(image).strip()
    digest = None
    without_digest = raw

    if "@" in raw:
        without_digest, digest = raw.split("@", 1)

    last_slash = without_digest.rfind("/")
    last_colon = without_digest.rfind(":")
    tag = None

    if last_colon > last_slash:
        tag = without_digest[last_colon + 1:]

    mutable_tags = {"latest", "dev", "test", "stable", "current"}
    uses_mutable = bool(tag and tag.lower() in mutable_tags)

    return {
        "image": raw,
        "imageTag": tag,
        "imageDigest": digest,
        "usesDigestReference": bool(digest),
        "usesMutableTag": uses_mutable,
    }

def load_gitops_manifest(path: Path | None) -> dict[str, Any]:
    result: dict[str, Any] = {
        "manifest": str(path) if path else None,
        "manifestFound": bool(path and path.exists()),
        "rollout": None,
        "namespace": None,
        "image": None,
        "imageTag": None,
        "releaseTag": None,
    }

    if not path or not path.exists():
        return result

    text = path.read_text(encoding="utf-8")

    if yaml is not None:
        try:
            docs = [item for item in yaml.safe_load_all(text) if isinstance(item, dict)]
            for doc in docs:
                if doc.get("kind") != "Rollout":
                    continue
                metadata = as_dict(doc.get("metadata"))
                result["rollout"] = metadata.get("name")
                result["namespace"] = metadata.get("namespace")

                template = as_dict(as_dict(doc.get("spec")).get("template"))
                spec = as_dict(template.get("spec"))
                containers = spec.get("containers") or []
                if isinstance(containers, list) and containers:
                    container = containers[0] if isinstance(containers[0], dict) else {}
                    result["image"] = container.get("image")
                    for env in container.get("env") or []:
                        if isinstance(env, dict) and env.get("name") == "RELEASE_TAG":
                            result["releaseTag"] = env.get("value")
                break
        except Exception:
            pass

    if not result.get("image"):
        image_match = re.search(r"^\s*image:\s*['\"]?([^'\"\n]+)['\"]?\s*$", text, re.M)
        if image_match:
            result["image"] = image_match.group(1).strip()

    if not result.get("releaseTag"):
        lines = text.splitlines()
        for idx, line in enumerate(lines):
            if re.search(r"^\s*-\s*name:\s*RELEASE_TAG\s*$", line):
                for next_line in lines[idx + 1: idx + 5]:
                    m = re.search(r"^\s*value:\s*['\"]?([^'\"\n]+)['\"]?\s*$", next_line)
                    if m:
                        result["releaseTag"] = m.group(1).strip()
                        break

    parsed = parse_image_ref(result.get("image"))
    result["imageTag"] = parsed.get("imageTag")

    return result

def add_check(checks: list[dict[str, Any]], check_id: str, status: str, severity: str, message: str, evidence: dict[str, Any] | None = None) -> None:
    checks.append({
        "checkId": check_id,
        "status": status,
        "severity": severity,
        "message": message,
        "evidence": evidence or {},
    })

def risk_points(status: str, severity: str) -> int:
    if status == "PASS":
        return 0
    table = {
        "low": 5,
        "medium": 15,
        "high": 30,
        "critical": 60,
    }
    return table.get(severity, 0)

def risk_level(score: int) -> str:
    if score >= 70:
        return "critical"
    if score >= 40:
        return "high"
    if score >= 15:
        return "medium"
    return "low"

def release_id_from_path(path: Path) -> str:
    name = path.name
    for prefix in ("release-evidence-", "release-context-"):
        if name.startswith(prefix) and name.endswith(".json"):
            return name[len(prefix):-len(".json")]
    return path.stem

input_doc = load_json(input_path)
schema_version = input_doc.get("schemaVersion")

if schema_version == "release.evidence.bundle/v1alpha1":
    evidence = input_doc
    release_context_path = resolve_ref(as_dict(evidence.get("artifacts")).get("releaseContext"), input_path)
    release_context = load_json(release_context_path)
    source_kind = "release_evidence"
else:
    evidence = {}
    release_context_path = input_path
    release_context = input_doc
    source_kind = "release_context"

change_context = as_dict(release_context.get("changeContext"))
image_obj = as_dict(change_context.get("image"))

version = nullable_string(first_not_none(
    release_context.get("currentDesiredVersion"),
    release_context.get("version"),
    release_context.get("appVersion"),
    evidence.get("version"),
))

service = nullable_string(first_not_none(evidence.get("service"), release_context.get("service"), release_context.get("rollout")))
env = nullable_string(first_not_none(evidence.get("env"), release_context.get("env")))
namespace = nullable_string(release_context.get("namespace"))
rollout = nullable_string(release_context.get("rollout"))

commit = nullable_string(first_not_none(
    change_context.get("commit"),
    change_context.get("gitCommit"),
    release_context.get("commit"),
    evidence.get("commit"),
))

image_ref = nullable_string(first_not_none(
    image_obj.get("current"),
    image_obj.get("target"),
    image_obj.get("new"),
    image_obj.get("image"),
    change_context.get("image"),
    release_context.get("image"),
    evidence.get("image"),
))

image_digest = nullable_string(first_not_none(
    change_context.get("imageDigest"),
    image_obj.get("digest"),
    release_context.get("imageDigest"),
    evidence.get("imageDigest"),
))

image_info = parse_image_ref(image_ref)
if image_digest and not image_info.get("imageDigest"):
    image_info["imageDigest"] = image_digest
image_info["usesDigestReference"] = bool(image_info.get("imageDigest") and "@" in str(image_info.get("image") or ""))

gitops = load_gitops_manifest(gitops_manifest_path)

checks: list[dict[str, Any]] = []

if version:
    add_check(checks, "release_version_present", "PASS", "none", "Release version is present.", {"version": version})
else:
    add_check(checks, "release_version_present", "WARN", "medium", "Release version is missing.", {})

if commit:
    add_check(checks, "source_commit_present", "PASS", "none", "Source commit is present.", {"commit": commit})
else:
    add_check(checks, "source_commit_present", "WARN", "medium", "Source commit is missing; source traceability is incomplete.", {})

if image_info.get("image"):
    add_check(checks, "image_reference_present", "PASS", "none", "Image reference is present.", {"image": image_info.get("image")})
else:
    add_check(checks, "image_reference_present", "WARN", "high", "Image reference is missing.", {})

if image_info.get("imageDigest"):
    add_check(checks, "image_digest_present", "PASS", "none", "Image digest is present.", {"imageDigest": image_info.get("imageDigest")})
else:
    add_check(checks, "image_digest_present", "WARN", "medium", "Image digest is missing; image identity is tag-based only.", {})

image_tag = image_info.get("imageTag")
if image_info.get("usesMutableTag"):
    add_check(checks, "mutable_image_tag", "WARN", "high", "Image uses a mutable tag and requires human review.", {"imageTag": image_tag})
elif not image_tag and not image_info.get("imageDigest"):
    add_check(checks, "mutable_image_tag", "WARN", "high", "Image tag and digest are both missing.", {})
else:
    add_check(checks, "mutable_image_tag", "PASS", "none", "Image tag is not in the known mutable tag denylist.", {"imageTag": image_tag})

if gitops.get("manifestFound"):
    add_check(checks, "gitops_manifest_found", "PASS", "none", "GitOps rollout manifest was found.", {"manifest": gitops.get("manifest")})
else:
    add_check(checks, "gitops_manifest_found", "WARN", "low", "GitOps rollout manifest was not found.", {"manifest": gitops.get("manifest")})

if gitops.get("image"):
    add_check(checks, "gitops_image_present", "PASS", "none", "GitOps target image is present.", {"image": gitops.get("image")})
else:
    add_check(checks, "gitops_image_present", "WARN", "medium", "GitOps target image is missing or could not be parsed.", {})

gitops_release_tag = gitops.get("releaseTag") or gitops.get("imageTag")
if version and gitops_release_tag:
    if version == gitops_release_tag:
        add_check(checks, "gitops_version_matches_release", "PASS", "none", "Release version matches GitOps target tag.", {"version": version, "gitopsReleaseTag": gitops_release_tag})
    else:
        add_check(checks, "gitops_version_matches_release", "FAIL", "critical", "Release version does not match GitOps target tag.", {"version": version, "gitopsReleaseTag": gitops_release_tag})
elif version:
    add_check(checks, "gitops_version_matches_release", "WARN", "medium", "Release version exists but GitOps target tag could not be parsed.", {"version": version})
else:
    add_check(checks, "gitops_version_matches_release", "WARN", "medium", "Cannot compare release version with GitOps target tag.", {})

if image_tag and version:
    if image_tag == version:
        add_check(checks, "image_tag_matches_release_version", "PASS", "none", "Image tag matches release version.", {"imageTag": image_tag, "version": version})
    else:
        add_check(checks, "image_tag_matches_release_version", "WARN", "high", "Image tag does not match release version.", {"imageTag": image_tag, "version": version})
elif version:
    add_check(checks, "image_tag_matches_release_version", "WARN", "medium", "Release version exists but image tag could not be parsed.", {"version": version})

if version and commit and image_info.get("image"):
    add_check(checks, "release_traceability_complete", "PASS", "none", "Release version, commit, and image are all present.", {"version": version, "commit": commit, "image": image_info.get("image")})
else:
    add_check(checks, "release_traceability_complete", "WARN", "medium", "Release traceability is incomplete; version, commit, and image should all be present.", {"version": version, "commit": commit, "image": image_info.get("image")})

score = min(100, sum(risk_points(item["status"], item["severity"]) for item in checks))
blocking_reasons = [item["message"] for item in checks if item["status"] == "FAIL"]
warning_reasons = [item["message"] for item in checks if item["status"] == "WARN"]

if blocking_reasons:
    decision_value = "BLOCK"
elif score >= 40:
    decision_value = "REQUIRE_HUMAN_APPROVAL"
else:
    decision_value = "ALLOW"

release_id = nullable_string(first_not_none(
    evidence.get("releaseId"),
    release_context.get("releaseId"),
    version,
    release_id_from_path(input_path),
)) or release_id_from_path(input_path)

decision = {
    "schemaVersion": "supply.chain.decision/v1alpha1",
    "supplyChainDecisionId": "sc-" + release_id,
    "generatedBy": "build-supply-chain-decision.sh",
    "generatedAt": now(),
    "mode": "read_only_supply_chain_check",
    "source": {
        "input": str(input_path),
        "inputKind": source_kind,
        "releaseContext": str(release_context_path) if release_context_path else None,
        "releaseEvidence": str(input_path) if source_kind == "release_evidence" else None,
        "gitopsManifest": str(gitops_manifest_path) if gitops_manifest_path else None,
    },
    "release": {
        "releaseId": release_id,
        "service": service,
        "env": env,
        "namespace": namespace,
        "rollout": rollout,
        "version": version,
        "commit": commit,
    },
    "image": image_info,
    "gitops": gitops,
    "checks": checks,
    "decision": {
        "decision": decision_value,
        "requiresHumanApproval": decision_value in {"REQUIRE_HUMAN_APPROVAL", "BLOCK"},
        "allowed": decision_value != "BLOCK",
        "blockingReasons": blocking_reasons,
        "warningReasons": warning_reasons,
    },
    "risk": {
        "riskLevel": risk_level(score),
        "riskScore": score,
    },
    "guardrails": {
        "readOnly": True,
        "willExecute": False,
        "doesNotModifyKubernetes": True,
        "doesNotModifyGitOps": True,
        "doesNotBuildImages": True,
        "doesNotPushImages": True,
        "doesNotCommitOrPush": True,
    },
}

output_json.parent.mkdir(parents=True, exist_ok=True)
output_json.write_text(json.dumps(decision, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
shutil.copyfile(output_json, latest_json)

print(f"Supply chain decision generated: {output_json}")
print(f"Latest supply chain decision: {latest_json}")
print(json.dumps({
    "supplyChainDecisionId": decision["supplyChainDecisionId"],
    "releaseId": release_id,
    "version": version,
    "image": image_info.get("image"),
    "imageTag": image_info.get("imageTag"),
    "imageDigest": image_info.get("imageDigest"),
    "gitopsReleaseTag": gitops.get("releaseTag") or gitops.get("imageTag"),
    "decision": decision_value,
    "riskLevel": decision["risk"]["riskLevel"],
    "riskScore": score,
    "willExecute": decision["guardrails"]["willExecute"],
}, ensure_ascii=False, indent=2))
PY_SUPPLY_CHAIN

validate_generated_release_contract "$OUTPUT_JSON"

python3 - "$OUTPUT_JSON" <<'PY_SUPPLY_CHAIN_LINK'
import json
import sys
from pathlib import Path

decision_path = Path(sys.argv[1])
decision = json.loads(decision_path.read_text(encoding="utf-8-sig"))

source = decision.get("source") or {}
evidence_ref = source.get("releaseEvidence")

if not evidence_ref:
    print("WARN: supply-chain decision has no release evidence ref, skip linking", file=sys.stderr)
    raise SystemExit(0)

evidence_path = Path(str(evidence_ref))
candidates = []

if evidence_path.is_absolute():
    candidates.append(evidence_path)

candidates.append(decision_path.parent / evidence_path.name)
candidates.append(evidence_path)

resolved = None
for candidate in candidates:
    if candidate.exists() and candidate.is_file():
        resolved = candidate
        break

if not resolved:
    print(f"WARN: release evidence file not found, skip linking supply-chain decision: {evidence_ref}", file=sys.stderr)
    raise SystemExit(0)

evidence = json.loads(resolved.read_text(encoding="utf-8-sig"))

decision_obj = decision.get("decision") or {}
risk = decision.get("risk") or {}
image = decision.get("image") or {}
gitops = decision.get("gitops") or {}

artifacts = evidence.setdefault("artifacts", {})
artifacts["supplyChainDecision"] = str(decision_path)

evidence["supplyChainDecisionId"] = decision.get("supplyChainDecisionId")

decision_refs = evidence.setdefault("decisionRefs", {})
decision_refs["supplyChainDecision"] = {
    "supplyChainDecisionId": decision.get("supplyChainDecisionId"),
    "mode": decision.get("mode"),
    "decision": decision_obj.get("decision"),
    "requiresHumanApproval": decision_obj.get("requiresHumanApproval"),
    "allowed": decision_obj.get("allowed"),
    "riskLevel": risk.get("riskLevel"),
    "riskScore": risk.get("riskScore"),
    "image": image.get("image"),
    "imageTag": image.get("imageTag"),
    "imageDigest": image.get("imageDigest"),
    "gitopsManifest": gitops.get("manifest"),
    "gitopsReleaseTag": gitops.get("releaseTag") or gitops.get("imageTag"),
    "checkCount": len(decision.get("checks") or []),
    "blockingReasons": decision_obj.get("blockingReasons") or [],
    "warningReasons": decision_obj.get("warningReasons") or [],
    "willExecute": (decision.get("guardrails") or {}).get("willExecute"),
    "guardrails": decision.get("guardrails") or {},
}

resolved.write_text(json.dumps(evidence, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(f"Supply chain decision linked into release evidence: {resolved}")
PY_SUPPLY_CHAIN_LINK

cat "$OUTPUT_JSON"
