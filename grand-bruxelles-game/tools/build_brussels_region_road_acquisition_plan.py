#!/usr/bin/env python3
"""Build a deterministic 19-commune road acquisition plan for Brussels.

The plan measures only source-backed road registration evidence already present in the
readiness catalog. It never authorizes render/runtime/collision/spawn/jouable promotion.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any

SCHEMA = "grand-bruxelles-region-road-acquisition-plan-v1"
TARGET_SCHEMA = "grand-bruxelles-region-playability-target-v1"
CLOSED_KEYS = (
    "road_cell_mapping_authorized",
    "render_authorized",
    "collision_authorized",
    "runtime_mount_authorized",
    "safe_spawn_authorized",
    "jouable_authorized",
)


def canonical_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_json(value: Any) -> str:
    return hashlib.sha256(canonical_json(value).encode("utf-8")).hexdigest()


def load_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise SystemExit(f"BRUSSELS_REGION_ACQUISITION_FAIL: cannot load {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise SystemExit(f"BRUSSELS_REGION_ACQUISITION_FAIL: expected JSON object: {path}")
    return value


def validate_target(target: dict[str, Any]) -> list[dict[str, str]]:
    if target.get("schema") != TARGET_SCHEMA:
        raise SystemExit("BRUSSELS_REGION_ACQUISITION_FAIL: target schema drift")
    if target.get("completion_claimed") is not False:
        raise SystemExit("BRUSSELS_REGION_ACQUISITION_FAIL: target already claims completion")
    rows = target.get("required_municipalities")
    if not isinstance(rows, list) or len(rows) != 19:
        raise SystemExit("BRUSSELS_REGION_ACQUISITION_FAIL: target must contain exactly 19 municipalities")
    normalized: list[dict[str, str]] = []
    seen_nis: set[str] = set()
    seen_ids: set[str] = set()
    for raw in rows:
        if not isinstance(raw, dict):
            raise SystemExit("BRUSSELS_REGION_ACQUISITION_FAIL: malformed municipality row")
        nis = str(raw.get("niscode") or "")
        municipality_id = str(raw.get("id") or "")
        name = str(raw.get("name") or "")
        if not nis or not municipality_id or not name or nis in seen_nis or municipality_id in seen_ids:
            raise SystemExit("BRUSSELS_REGION_ACQUISITION_FAIL: municipality identity drift")
        seen_nis.add(nis)
        seen_ids.add(municipality_id)
        normalized.append({"niscode": nis, "id": municipality_id, "name": name})
    normalized.sort(key=lambda row: row["niscode"])
    return normalized


def validate_readiness(readiness: dict[str, Any]) -> list[dict[str, Any]]:
    auth = readiness.get("authorization") or {}
    for key in CLOSED_KEYS:
        if auth.get(key) is not False:
            raise SystemExit(f"BRUSSELS_REGION_ACQUISITION_FAIL: readiness opened {key}")
    destinations = readiness.get("destinations")
    if not isinstance(destinations, list):
        raise SystemExit("BRUSSELS_REGION_ACQUISITION_FAIL: readiness destinations missing")
    if int(readiness.get("destination_count", -1)) != len(destinations):
        raise SystemExit("BRUSSELS_REGION_ACQUISITION_FAIL: readiness destination accounting drift")
    return destinations


def municipality_niscodes(destination: dict[str, Any]) -> list[str]:
    direct = destination.get("municipality_niscodes")
    if isinstance(direct, list):
        values = sorted({str(value) for value in direct if str(value)})
        if values:
            return values
    municipalities = destination.get("municipalities")
    if not isinstance(municipalities, list):
        return []
    return sorted({str(row.get("niscode") or "") for row in municipalities if isinstance(row, dict) and row.get("niscode")})


def build_plan(target_path: Path, readiness_path: Path) -> dict[str, Any]:
    target = load_json(target_path)
    readiness = load_json(readiness_path)
    municipalities = validate_target(target)
    destinations = validate_readiness(readiness)

    evidence: dict[str, set[int]] = {row["niscode"]: set() for row in municipalities}
    unknown_niscodes: set[str] = set()
    for destination in destinations:
        if not isinstance(destination, dict):
            raise SystemExit("BRUSSELS_REGION_ACQUISITION_FAIL: malformed readiness destination")
        if destination.get("readiness") != "REGISTERED_NOT_RENDERED":
            continue
        road_id = destination.get("road_osm_id")
        if not isinstance(road_id, int) or road_id <= 0:
            raise SystemExit("BRUSSELS_REGION_ACQUISITION_FAIL: invalid registered road identity")
        for nis in municipality_niscodes(destination):
            if nis in evidence:
                evidence[nis].add(road_id)
            else:
                unknown_niscodes.add(nis)
    if unknown_niscodes:
        raise SystemExit(
            "BRUSSELS_REGION_ACQUISITION_FAIL: readiness references municipalities outside regional target: "
            + ",".join(sorted(unknown_niscodes))
        )

    rows: list[dict[str, Any]] = []
    for municipality in municipalities:
        ids = sorted(evidence[municipality["niscode"]])
        has_evidence = bool(ids)
        rows.append({
            **municipality,
            "registered_road_evidence_count": len(ids),
            "registered_road_osm_ids": ids,
            "source_registration_evidence_present": has_evidence,
            "acquisition_state": "EXPAND_REGISTERED_EVIDENCE" if has_evidence else "ACQUIRE_FIRST_REGISTERED_EVIDENCE",
            "playable_claimed": False,
        })

    missing = [row["niscode"] for row in rows if not row["source_registration_evidence_present"]]
    covered = [row["niscode"] for row in rows if row["source_registration_evidence_present"]]
    priority = sorted(
        rows,
        key=lambda row: (
            0 if row["acquisition_state"] == "ACQUIRE_FIRST_REGISTERED_EVIDENCE" else 1,
            row["registered_road_evidence_count"],
            row["niscode"],
        ),
    )

    payload: dict[str, Any] = {
        "schema": SCHEMA,
        "scope": "Brussels-Capital Region",
        "target_path": target_path.as_posix(),
        "target_sha256": sha256_bytes(target_path.read_bytes()),
        "readiness_path": readiness_path.as_posix(),
        "readiness_sha256": sha256_bytes(readiness_path.read_bytes()),
        "municipality_count": 19,
        "municipalities_with_registered_road_evidence": len(covered),
        "municipalities_without_registered_road_evidence": len(missing),
        "covered_niscodes": covered,
        "missing_niscodes": missing,
        "municipalities": rows,
        "acquisition_priority_niscodes": [row["niscode"] for row in priority],
        "regional_source_registration_complete": len(missing) == 0,
        "regional_playability_complete": False,
        "authorization": {
            "evidence_only": True,
            "source_registration_authorized": False,
            "road_cell_mapping_authorized": False,
            "render_authorized": False,
            "collision_authorized": False,
            "runtime_mount_authorized": False,
            "safe_spawn_authorized": False,
            "jouable_authorized": False,
        },
    }
    payload["plan_sha256"] = sha256_json(payload)
    return payload


def validate_plan(plan: dict[str, Any]) -> None:
    if plan.get("schema") != SCHEMA or int(plan.get("municipality_count", -1)) != 19:
        raise SystemExit("BRUSSELS_REGION_ACQUISITION_FAIL: plan schema/count drift")
    rows = plan.get("municipalities")
    if not isinstance(rows, list) or len(rows) != 19:
        raise SystemExit("BRUSSELS_REGION_ACQUISITION_FAIL: plan municipality accounting drift")
    covered = plan.get("covered_niscodes")
    missing = plan.get("missing_niscodes")
    if not isinstance(covered, list) or not isinstance(missing, list) or len(covered) + len(missing) != 19:
        raise SystemExit("BRUSSELS_REGION_ACQUISITION_FAIL: coverage accounting drift")
    if bool(plan.get("regional_source_registration_complete")) != (len(missing) == 0):
        raise SystemExit("BRUSSELS_REGION_ACQUISITION_FAIL: source completion drift")
    if plan.get("regional_playability_complete") is not False:
        raise SystemExit("BRUSSELS_REGION_ACQUISITION_FAIL: premature regional playability claim")
    auth = plan.get("authorization") or {}
    if auth.get("evidence_only") is not True or auth.get("source_registration_authorized") is not False:
        raise SystemExit("BRUSSELS_REGION_ACQUISITION_FAIL: evidence rail drift")
    for key in CLOSED_KEYS:
        if auth.get(key) is not False:
            raise SystemExit(f"BRUSSELS_REGION_ACQUISITION_FAIL: plan opened {key}")
    stored = str(plan.get("plan_sha256") or "")
    unsigned = dict(plan)
    unsigned.pop("plan_sha256", None)
    if stored != sha256_json(unsigned):
        raise SystemExit("BRUSSELS_REGION_ACQUISITION_FAIL: plan SHA drift")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--target", type=Path, default=Path("data/qa/brussels_region_playability_target.json"))
    parser.add_argument("--readiness", type=Path, default=Path("data/provenance/brussels_road_destination_readiness_catalog.json"))
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    plan = build_plan(args.target, args.readiness)
    validate_plan(plan)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(plan, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(
        "BRUSSELS_REGION_ACQUISITION_GREEN: "
        f"covered={plan['municipalities_with_registered_road_evidence']} "
        f"missing={plan['municipalities_without_registered_road_evidence']} "
        f"sha256={plan['plan_sha256']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
