#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import sqlite3
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


RESOURCE_SPECS = [
    {
        "object_type": "releaseEvidence",
        "glob": "release-evidence-*.json",
        "latest": "release-evidence-latest.json",
        "prefix": "release-evidence-",
        "id_key": None,
        "id_prefix": "re-",
    },
    {
        "object_type": "evidenceRecord",
        "glob": "evidence-record-*.json",
        "latest": "evidence-record-latest.json",
        "prefix": "evidence-record-",
        "id_key": "evidenceId",
        "id_prefix": "ev-",
    },
    {
        "object_type": "agentRun",
        "glob": "agent-run-*.json",
        "latest": "agent-run-latest.json",
        "prefix": "agent-run-",
        "id_key": "agentRunId",
        "id_prefix": "ar-",
    },
    {
        "object_type": "planRun",
        "glob": "plan-run-*.json",
        "latest": "plan-run-latest.json",
        "prefix": "plan-run-",
        "id_key": "planRunId",
        "id_prefix": "pr-",
    },
    {
        "object_type": "executionRequest",
        "glob": "execution-request-*.json",
        "latest": "execution-request-latest.json",
        "prefix": "execution-request-",
        "id_key": "executionRequestId",
        "id_prefix": "er-",
    },
    {
        "object_type": "supplyChainDecision",
        "glob": "supply-chain-decision-*.json",
        "latest": "supply-chain-decision-latest.json",
        "prefix": "supply-chain-decision-",
        "id_key": "supplyChainDecisionId",
        "id_prefix": "sc-",
    },
]


SCHEMA_SQL = """
PRAGMA journal_mode=WAL;

CREATE TABLE IF NOT EXISTS releases (
  release_id TEXT PRIMARY KEY,
  service TEXT,
  namespace TEXT,
  env TEXT,
  version TEXT,
  commit_sha TEXT,
  image TEXT,
  image_digest TEXT,
  release_result TEXT,
  policy_decision TEXT,
  final_action TEXT,
  risk_level TEXT,
  risk_score REAL,
  requires_human_approval INTEGER,
  generated_at TEXT,
  first_seen_at TEXT NOT NULL,
  last_seen_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS evidence_objects (
  object_pk TEXT PRIMARY KEY,
  object_type TEXT NOT NULL,
  object_id TEXT NOT NULL,
  release_id TEXT NOT NULL,
  schema_version TEXT,
  source_path TEXT NOT NULL,
  source_mtime TEXT,
  content_sha256 TEXT NOT NULL,
  generated_at TEXT,
  imported_at TEXT NOT NULL,
  summary_json TEXT NOT NULL,
  raw_json TEXT NOT NULL,
  FOREIGN KEY (release_id) REFERENCES releases(release_id)
);

CREATE INDEX IF NOT EXISTS idx_evidence_objects_release
  ON evidence_objects(release_id);

CREATE INDEX IF NOT EXISTS idx_evidence_objects_type_id
  ON evidence_objects(object_type, object_id);

CREATE UNIQUE INDEX IF NOT EXISTS idx_evidence_objects_source
  ON evidence_objects(source_path);

CREATE TABLE IF NOT EXISTS release_artifacts (
  release_id TEXT NOT NULL,
  artifact_kind TEXT NOT NULL,
  path TEXT NOT NULL,
  exists_flag INTEGER,
  content_type TEXT,
  size_bytes INTEGER,
  modified_at TEXT,
  source_object_pk TEXT,
  PRIMARY KEY (release_id, artifact_kind, path),
  FOREIGN KEY (release_id) REFERENCES releases(release_id),
  FOREIGN KEY (source_object_pk) REFERENCES evidence_objects(object_pk)
);

CREATE INDEX IF NOT EXISTS idx_release_artifacts_release
  ON release_artifacts(release_id);
"""


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def read_json(path: Path) -> dict[str, Any]:
    data = json.loads(path.read_text(encoding="utf-8-sig"))
    if not isinstance(data, dict):
        raise ValueError(f"JSON root must be an object: {path}")
    return data


def as_dict(value: Any) -> dict[str, Any]:
    return value if isinstance(value, dict) else {}


def as_number(value: Any) -> float | None:
    if value is None:
        return None
    try:
        return float(value)
    except Exception:
        return None


def as_bool_int(value: Any) -> int | None:
    if value is None:
        return None
    return 1 if bool(value) else 0


def first_non_empty(*values: Any) -> Any:
    for value in values:
        if value not in (None, ""):
            return value
    return None


def scalar_or_none(value: Any) -> str | None:
    if value is None:
        return None
    if isinstance(value, (dict, list, tuple, set)):
        return None
    text = str(value).strip()
    return text if text else None


def first_scalar(*values: Any) -> str | None:
    for value in values:
        scalar = scalar_or_none(value)
        if scalar is not None:
            return scalar
    return None


def file_mtime_iso(path: Path) -> str | None:
    try:
        return datetime.fromtimestamp(path.stat().st_mtime, timezone.utc).isoformat()
    except OSError:
        return None


def file_size(path: Path) -> int | None:
    try:
        return int(path.stat().st_size)
    except OSError:
        return None


def sha256_text(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def strip_suffix_from_name(path: Path, prefix: str) -> str:
    name = path.name
    if name.startswith(prefix) and name.endswith(".json"):
        return name[len(prefix):-len(".json")]
    return path.stem


def derive_release_id(data: dict[str, Any], path: Path, spec: dict[str, Any]) -> str:
    filename_suffix = strip_suffix_from_name(path, str(spec["prefix"]))

    # Report files are named by release timestamp. Some objects, especially
    # supply-chain decisions, may carry image/app version as nested releaseId.
    # For EvidenceStore grouping, the timestamp suffix is the stable release key.
    compact_suffix = filename_suffix.replace("-", "")
    if (
        len(filename_suffix) == 15
        and filename_suffix[8] == "-"
        and compact_suffix.isdigit()
    ):
        return filename_suffix

    release = as_dict(data.get("release"))
    source = as_dict(data.get("source"))

    release_id = first_non_empty(
        data.get("releaseId"),
        release.get("releaseId"),
        source.get("releaseId"),
    )

    if release_id:
        return str(release_id)

    return filename_suffix


def derive_object_id(
    data: dict[str, Any],
    path: Path,
    spec: dict[str, Any],
    release_id: str,
) -> str:
    id_key = spec.get("id_key")
    if id_key and data.get(str(id_key)):
        return str(data[str(id_key)])

    nested_candidates = [
        as_dict(data.get("agent")).get("agentRunId"),
        as_dict(data.get("plan")).get("planRunId"),
        as_dict(data.get("executionRequest")).get("executionRequestId"),
        as_dict(data.get("supplyChain")).get("supplyChainDecisionId"),
    ]

    for candidate in nested_candidates:
        if candidate:
            return str(candidate)

    if spec["object_type"] == "releaseEvidence":
        return f"re-{release_id}"

    return f"{spec['id_prefix']}{strip_suffix_from_name(path, str(spec['prefix']))}"


def extract_release_fields(data: dict[str, Any], release_id: str) -> dict[str, Any]:
    release = as_dict(data.get("release"))
    summary = as_dict(data.get("summary"))
    observation = as_dict(data.get("observation"))
    policy = as_dict(data.get("policy"))
    recommendation = as_dict(data.get("recommendation"))
    risk = as_dict(data.get("risk"))
    image = as_dict(data.get("image"))

    return {
        "release_id": release_id,
        "service": first_scalar(data.get("service"), release.get("service")),
        "namespace": first_scalar(data.get("namespace"), release.get("namespace")),
        "env": first_scalar(data.get("env"), release.get("env")),
        "version": first_scalar(data.get("version"), release.get("version")),
        "commit_sha": first_scalar(data.get("commit"), release.get("commit")),
        "image": first_scalar(image.get("image"), data.get("image")),
        "image_digest": first_scalar(
            data.get("imageDigest"),
            release.get("imageDigest"),
            image.get("imageDigest"),
        ),
        "release_result": first_scalar(
            data.get("releaseResult"),
            release.get("releaseResult"),
            observation.get("releaseResult"),
        ),
        "policy_decision": first_scalar(
            data.get("policyDecision"),
            release.get("policyDecision"),
            policy.get("policyDecision"),
        ),
        "final_action": first_scalar(
            data.get("finalAction"),
            release.get("recommendedAction"),
            recommendation.get("recommendedAction"),
        ),
        "risk_level": first_scalar(
            data.get("riskLevel"),
            summary.get("riskLevel"),
            observation.get("riskLevel"),
            risk.get("riskLevel"),
        ),
        "risk_score": as_number(first_non_empty(
            data.get("riskScore"),
            summary.get("riskScore"),
            observation.get("riskScore"),
            risk.get("riskScore"),
        )),
        "requires_human_approval": as_bool_int(first_non_empty(
            data.get("requiresHumanApproval"),
            release.get("requiresHumanApproval"),
            policy.get("requiresHumanApproval"),
        )),
        "generated_at": first_scalar(data.get("generatedAt"), release.get("generatedAt")),
    }


def compact_object_summary(object_type: str, data: dict[str, Any]) -> dict[str, Any]:
    release = as_dict(data.get("release"))
    summary = as_dict(data.get("summary"))
    decision = as_dict(data.get("decision"))
    request = as_dict(data.get("request"))
    plan = as_dict(data.get("plan"))
    recommendation = as_dict(data.get("recommendation"))
    risk = as_dict(data.get("risk"))

    return {
        "objectType": object_type,
        "schemaVersion": data.get("schemaVersion"),
        "generatedBy": data.get("generatedBy"),
        "generatedAt": data.get("generatedAt"),
        "releaseResult": first_non_empty(
            data.get("releaseResult"),
            release.get("releaseResult"),
            summary.get("releaseResult"),
        ),
        "policyDecision": first_non_empty(
            data.get("policyDecision"),
            release.get("policyDecision"),
        ),
        "finalAction": first_non_empty(
            data.get("finalAction"),
            release.get("recommendedAction"),
            recommendation.get("recommendedAction"),
        ),
        "riskLevel": first_non_empty(
            data.get("riskLevel"),
            summary.get("riskLevel"),
            risk.get("riskLevel"),
        ),
        "riskScore": first_non_empty(
            data.get("riskScore"),
            summary.get("riskScore"),
            risk.get("riskScore"),
        ),
        "requestedAction": request.get("requestedAction"),
        "requestStatus": request.get("requestStatus"),
        "decision": decision.get("decision"),
        "allowed": decision.get("allowed"),
        "willExecute": first_non_empty(
            as_dict(data.get("guardrails")).get("willExecute"),
            plan.get("willExecute"),
            request.get("willExecute"),
        ),
    }


def init_db(conn: sqlite3.Connection) -> None:
    conn.executescript(SCHEMA_SQL)
    conn.commit()


def upsert_release(conn: sqlite3.Connection, fields: dict[str, Any], seen_at: str) -> None:
    conn.execute(
        """
        INSERT INTO releases (
          release_id, service, namespace, env, version, commit_sha, image, image_digest,
          release_result, policy_decision, final_action, risk_level, risk_score,
          requires_human_approval, generated_at, first_seen_at, last_seen_at
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(release_id) DO UPDATE SET
          service = COALESCE(excluded.service, releases.service),
          namespace = COALESCE(excluded.namespace, releases.namespace),
          env = COALESCE(excluded.env, releases.env),
          version = COALESCE(excluded.version, releases.version),
          commit_sha = COALESCE(excluded.commit_sha, releases.commit_sha),
          image = COALESCE(excluded.image, releases.image),
          image_digest = COALESCE(excluded.image_digest, releases.image_digest),
          release_result = COALESCE(excluded.release_result, releases.release_result),
          policy_decision = COALESCE(excluded.policy_decision, releases.policy_decision),
          final_action = COALESCE(excluded.final_action, releases.final_action),
          risk_level = COALESCE(excluded.risk_level, releases.risk_level),
          risk_score = COALESCE(excluded.risk_score, releases.risk_score),
          requires_human_approval = COALESCE(excluded.requires_human_approval, releases.requires_human_approval),
          generated_at = COALESCE(excluded.generated_at, releases.generated_at),
          last_seen_at = excluded.last_seen_at
        """,
        (
            fields["release_id"],
            fields.get("service"),
            fields.get("namespace"),
            fields.get("env"),
            fields.get("version"),
            fields.get("commit_sha"),
            fields.get("image"),
            fields.get("image_digest"),
            fields.get("release_result"),
            fields.get("policy_decision"),
            fields.get("final_action"),
            fields.get("risk_level"),
            fields.get("risk_score"),
            fields.get("requires_human_approval"),
            fields.get("generated_at"),
            seen_at,
            seen_at,
        ),
    )


def insert_artifacts(
    conn: sqlite3.Connection,
    release_id: str,
    object_pk: str,
    data: dict[str, Any],
) -> int:
    count = 0

    containers = []
    if isinstance(data.get("artifacts"), dict):
        containers.append(("artifacts", as_dict(data.get("artifacts"))))
    if isinstance(data.get("links"), dict):
        containers.append(("links", as_dict(data.get("links"))))

    for _, container in containers:
        for artifact_kind, value in container.items():
            if value in (None, ""):
                continue

            exists_flag = None
            content_type = None
            size_bytes = None
            modified_at = None

            if isinstance(value, dict):
                path = value.get("path") or value.get("file")
                exists_flag = as_bool_int(value.get("exists"))
                content_type = value.get("contentType")
                size_bytes = value.get("sizeBytes")
                modified_at = value.get("modifiedAt")
            else:
                path = str(value)

            if not path:
                continue

            conn.execute(
                """
                INSERT OR REPLACE INTO release_artifacts (
                  release_id, artifact_kind, path, exists_flag,
                  content_type, size_bytes, modified_at, source_object_pk
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    release_id,
                    str(artifact_kind),
                    str(path),
                    exists_flag,
                    content_type,
                    size_bytes,
                    modified_at,
                    object_pk,
                ),
            )
            count += 1

    return count


def import_file(conn: sqlite3.Connection, path: Path, spec: dict[str, Any]) -> tuple[str, str]:
    raw_text = path.read_text(encoding="utf-8-sig")
    data = json.loads(raw_text)
    if not isinstance(data, dict):
        raise ValueError(f"JSON root must be object: {path}")

    imported_at = now_iso()
    object_type = str(spec["object_type"])
    release_id = derive_release_id(data, path, spec)
    object_id = derive_object_id(data, path, spec, release_id)
    object_pk = f"{object_type}:{release_id}:{object_id}"

    release_fields = extract_release_fields(data, release_id)
    upsert_release(conn, release_fields, imported_at)

    summary = compact_object_summary(object_type, data)

    conn.execute(
        """
        INSERT INTO evidence_objects (
          object_pk, object_type, object_id, release_id, schema_version,
          source_path, source_mtime, content_sha256, generated_at,
          imported_at, summary_json, raw_json
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(object_pk) DO UPDATE SET
          schema_version = excluded.schema_version,
          source_path = excluded.source_path,
          source_mtime = excluded.source_mtime,
          content_sha256 = excluded.content_sha256,
          generated_at = excluded.generated_at,
          imported_at = excluded.imported_at,
          summary_json = excluded.summary_json,
          raw_json = excluded.raw_json
        """,
        (
            object_pk,
            object_type,
            object_id,
            release_id,
            data.get("schemaVersion"),
            str(path),
            file_mtime_iso(path),
            sha256_text(raw_text),
            data.get("generatedAt"),
            imported_at,
            json.dumps(summary, ensure_ascii=False, sort_keys=True),
            json.dumps(data, ensure_ascii=False, sort_keys=True),
        ),
    )

    insert_artifacts(conn, release_id, object_pk, data)

    return release_id, object_type


def import_dir(conn: sqlite3.Connection, report_dir: Path) -> dict[str, Any]:
    if not report_dir.is_dir():
        raise SystemExit(f"ERROR: report dir does not exist: {report_dir}")

    init_db(conn)

    imported = 0
    skipped = 0
    by_type: dict[str, int] = {}
    release_ids: set[str] = set()

    for spec in RESOURCE_SPECS:
        latest_name = str(spec["latest"])
        for path in sorted(report_dir.glob(str(spec["glob"]))):
            if path.name == latest_name:
                skipped += 1
                continue
            try:
                release_id, object_type = import_file(conn, path, spec)
            except Exception as exc:
                print(f"WARN: failed to import {path}: {exc}", file=sys.stderr)
                skipped += 1
                continue

            imported += 1
            release_ids.add(release_id)
            by_type[object_type] = by_type.get(object_type, 0) + 1

    conn.commit()

    return {
        "schemaVersion": "evidence.store.import/v1alpha1",
        "reportDir": str(report_dir),
        "importedObjects": imported,
        "skippedObjects": skipped,
        "releaseCount": len(release_ids),
        "byType": dict(sorted(by_type.items())),
    }


def row_to_dict(row: sqlite3.Row | None) -> dict[str, Any] | None:
    if row is None:
        return None
    return {key: row[key] for key in row.keys()}


def parse_json_field(value: Any) -> dict[str, Any]:
    if value in (None, ""):
        return {}
    if isinstance(value, dict):
        return value
    try:
        data = json.loads(str(value))
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def normalize_release_row(row: sqlite3.Row | None) -> dict[str, Any] | None:
    item = row_to_dict(row)
    if item is None:
        return None

    if item.get("requires_human_approval") is not None:
        item["requires_human_approval"] = bool(item["requires_human_approval"])

    return item


def normalize_object_row(row: sqlite3.Row | None, include_raw: bool) -> dict[str, Any] | None:
    item = row_to_dict(row)
    if item is None:
        return None

    item["summary"] = parse_json_field(item.pop("summary_json", None))
    raw_json = item.pop("raw_json", None)

    if include_raw:
        item["raw"] = parse_json_field(raw_json)

    return item


def list_releases(
    conn: sqlite3.Connection,
    limit: int,
    service: str | None = None,
    env: str | None = None,
    release_result: str | None = None,
) -> dict[str, Any]:
    conn.row_factory = sqlite3.Row

    where = []
    params: list[Any] = []

    if service:
        where.append("r.service = ?")
        params.append(service)

    if env:
        where.append("r.env = ?")
        params.append(env)

    if release_result:
        where.append("r.release_result = ?")
        params.append(release_result)

    where_sql = ""
    if where:
        where_sql = "WHERE " + " AND ".join(where)

    safe_limit = max(1, min(int(limit), 500))

    rows = conn.execute(
        f"""
        SELECT
          r.*,
          COUNT(e.object_pk) AS object_count,
          MAX(e.imported_at) AS latest_object_imported_at
        FROM releases r
        LEFT JOIN evidence_objects e ON e.release_id = r.release_id
        {where_sql}
        GROUP BY r.release_id
        ORDER BY
          COALESCE(r.generated_at, r.last_seen_at, r.release_id) DESC,
          r.release_id DESC
        LIMIT ?
        """,
        (*params, safe_limit),
    ).fetchall()

    items = []
    for row in rows:
        item = normalize_release_row(row) or {}

        object_rows = conn.execute(
            """
            SELECT object_type, object_id
            FROM evidence_objects
            WHERE release_id = ?
            ORDER BY object_type, object_id
            """,
            (item.get("release_id"),),
        ).fetchall()

        item["object_types"] = sorted({object_row["object_type"] for object_row in object_rows})
        item["objects"] = [
            {
                "objectType": object_row["object_type"],
                "objectId": object_row["object_id"],
            }
            for object_row in object_rows
        ]
        items.append(item)

    return {
        "schemaVersion": "evidence.store.releaseList/v1alpha1",
        "generatedAt": now_iso(),
        "count": len(items),
        "limit": safe_limit,
        "filters": {
            "service": service,
            "env": env,
            "releaseResult": release_result,
        },
        "items": items,
    }


def get_object(
    conn: sqlite3.Connection,
    object_type: str,
    object_id: str,
    release_id: str | None,
    include_raw: bool,
) -> dict[str, Any]:
    conn.row_factory = sqlite3.Row

    where = [
        "object_type = ?",
        "object_id = ?",
    ]
    params: list[Any] = [object_type, object_id]

    if release_id:
        where.append("release_id = ?")
        params.append(release_id)

    row = conn.execute(
        f"""
        SELECT object_type, object_id, release_id, schema_version,
               source_path, source_mtime, content_sha256, generated_at,
               imported_at, summary_json, raw_json
        FROM evidence_objects
        WHERE {" AND ".join(where)}
        ORDER BY imported_at DESC, source_mtime DESC
        LIMIT 1
        """,
        tuple(params),
    ).fetchone()

    obj = normalize_object_row(row, include_raw)
    if obj is None:
        raise SystemExit(
            "ERROR: object not found: "
            f"objectType={object_type} objectId={object_id}"
            + (f" releaseId={release_id}" if release_id else "")
        )

    release = normalize_release_row(
        conn.execute(
            "SELECT * FROM releases WHERE release_id = ?",
            (obj["release_id"],),
        ).fetchone()
    )

    return {
        "schemaVersion": "evidence.store.object/v1alpha1",
        "generatedAt": now_iso(),
        "release": normalize_release_row(release),
        "object": obj,
    }


def query_release(conn: sqlite3.Connection, release_id: str, include_raw: bool) -> dict[str, Any]:
    conn.row_factory = sqlite3.Row

    release = row_to_dict(
        conn.execute(
            "SELECT * FROM releases WHERE release_id = ?",
            (release_id,),
        ).fetchone()
    )

    if release is None:
        raise SystemExit(f"ERROR: release not found: {release_id}")

    object_rows = conn.execute(
        """
        SELECT object_type, object_id, release_id, schema_version,
               source_path, source_mtime, content_sha256, generated_at,
               imported_at, summary_json, raw_json
        FROM evidence_objects
        WHERE release_id = ?
        ORDER BY object_type, object_id
        """,
        (release_id,),
    ).fetchall()

    objects = []
    for row in object_rows:
        item = normalize_object_row(row, include_raw)
        if item is not None:
            objects.append(item)

    artifact_rows = conn.execute(
        """
        SELECT artifact_kind, path, exists_flag, content_type, size_bytes,
               modified_at, source_object_pk
        FROM release_artifacts
        WHERE release_id = ?
        ORDER BY artifact_kind, path
        """,
        (release_id,),
    ).fetchall()

    artifacts = []
    for row in artifact_rows:
        item = row_to_dict(row) or {}
        if item.get("exists_flag") is not None:
            item["exists"] = bool(item.pop("exists_flag"))
        else:
            item.pop("exists_flag", None)
        artifacts.append(item)

    return {
        "schemaVersion": "evidence.store.release/v1alpha1",
        "generatedAt": now_iso(),
        "release": release,
        "objectCount": len(objects),
        "objects": objects,
        "artifactCount": len(artifacts),
        "artifacts": artifacts,
    }


def open_db(path: Path) -> sqlite3.Connection:
    path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(path))
    conn.row_factory = sqlite3.Row
    return conn


def main() -> int:
    parser = argparse.ArgumentParser(
        description="S Sentinel EvidenceStore SQLite utility."
    )
    sub = parser.add_subparsers(dest="command", required=True)

    init_parser = sub.add_parser("init-db", help="Initialize SQLite EvidenceStore DB.")
    init_parser.add_argument("--db", required=True)

    import_parser = sub.add_parser("import-dir", help="Import report JSON files into SQLite.")
    import_parser.add_argument("--db", required=True)
    import_parser.add_argument("--report-dir", required=True)

    list_parser = sub.add_parser("list-releases", help="List releases from SQLite.")
    list_parser.add_argument("--db", required=True)
    list_parser.add_argument("--limit", type=int, default=50)
    list_parser.add_argument("--service")
    list_parser.add_argument("--env")
    list_parser.add_argument("--release-result")

    query_parser = sub.add_parser("query-release", help="Query one release from SQLite.")
    query_parser.add_argument("--db", required=True)
    query_parser.add_argument("--release-id", required=True)
    query_parser.add_argument("--include-raw", action="store_true")

    object_parser = sub.add_parser("get-object", help="Get one evidence object from SQLite.")
    object_parser.add_argument("--db", required=True)
    object_parser.add_argument("--object-type", required=True)
    object_parser.add_argument("--object-id", required=True)
    object_parser.add_argument("--release-id")
    object_parser.add_argument("--include-raw", action="store_true")

    args = parser.parse_args()

    db_path = Path(args.db)

    with open_db(db_path) as conn:
        if args.command == "init-db":
            init_db(conn)
            print(json.dumps({
                "schemaVersion": "evidence.store.init/v1alpha1",
                "db": str(db_path),
                "status": "initialized",
            }, ensure_ascii=False, indent=2))
            return 0

        if args.command == "import-dir":
            result = import_dir(conn, Path(args.report_dir))
            result["db"] = str(db_path)
            print(json.dumps(result, ensure_ascii=False, indent=2))
            return 0

        if args.command == "list-releases":
            result = list_releases(
                conn,
                args.limit,
                service=args.service,
                env=args.env,
                release_result=args.release_result,
            )
            result["db"] = str(db_path)
            print(json.dumps(result, ensure_ascii=False, indent=2))
            return 0

        if args.command == "query-release":
            result = query_release(conn, args.release_id, args.include_raw)
            result["db"] = str(db_path)
            print(json.dumps(result, ensure_ascii=False, indent=2))
            return 0

        if args.command == "get-object":
            result = get_object(
                conn,
                args.object_type,
                args.object_id,
                args.release_id,
                args.include_raw,
            )
            result["db"] = str(db_path)
            print(json.dumps(result, ensure_ascii=False, indent=2))
            return 0

    return 1


if __name__ == "__main__":
    raise SystemExit(main())
