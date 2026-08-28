#!/usr/bin/env python3
"""Build deterministic municipality coverage evidence for automatic road destinations.

This audit consumes the existing source/provenance binding. It measures only what is
already registered. DISCOVERED roads remain explicitly municipality-unassigned until
source-backed cell/municipality evidence exists. No runtime authorization is produced.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
from typing import Any

FORMAT = "grand-bruxelles-road-municipality-coverage-audit-v1"


def canonical_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def sha256_json(value: Any) -> str:
    return hashlib.sha256(canonical_json(value).encode("utf-8")).hexdigest()


def is_sha256(value: Any) -> bool:
    text = str(value or "").lower()
    return len(text) == 64 and all(ch in "0123456789abcdef" for ch in text)


def load_binding_builder(path: Path):
    spec = importlib.util.spec_from_file_location("road_provenance_binding", path)
    if spec is None or spec.loader is None:
        raise SystemExit("ROAD_MUNICIPALITY_AUDIT_FAIL: cannot load provenance binding builder")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def require_closed(mapping: dict[str, Any], label: str) -> None:
    for key in ("render_authorized", "collision_authorized", "runtime_mount_authorized", "safe_spawn_authorized", "jouable_authorized"):
        if mapping.get(key) is not False:
            raise SystemExit(f"ROAD_MUNICIPALITY_AUDIT_FAIL: {label} opened {key}")


def build_audit(source_root: Path, readiness: Path, catalog_builder: Path, binding_builder_path: Path) -> dict[str, Any]:
    binding_builder = load_binding_builder(binding_builder_path)
    binding = binding_builder.build_binding(source_root, readiness, catalog_builder)
    binding_builder.validate_binding(binding)
    if not is_sha256(binding.get("binding_sha256")):
        raise SystemExit("ROAD_MUNICIPALITY_AUDIT_FAIL: missing upstream binding identity")
    require_closed(binding.get("authorization") or {}, "upstream binding")

    municipalities: dict[str, dict[str, Any]] = {}
    discovered_unassigned: list[int] = []
    registered_ids: list[int] = []

    entries = binding.get("entries") or {}
    for raw_id, row in entries.items():
        road_id = int(raw_id)
        state = row.get("state")
        require_closed(row, f"road {road_id}")
        if state == "DISCOVERED":
            if row.get("municipalities") is not None or row.get("cell_id") is not None:
                raise SystemExit(f"ROAD_MUNICIPALITY_AUDIT_FAIL: discovered road carries inferred municipality/cell {road_id}")
            discovered_unassigned.append(road_id)
            continue
        if state != "REGISTERED_NOT_RENDERED":
            raise SystemExit(f"ROAD_MUNICIPALITY_AUDIT_FAIL: unknown state {road_id}")
        registered_ids.append(road_id)
        cell_id = str(row.get("cell_id") or "")
        cell_manifest_path = str(row.get("cell_manifest_path") or "")
        cell_manifest_sha = str(row.get("cell_manifest_sha256") or "").lower()
        if not cell_id or not cell_manifest_path.startswith("data/cell_manifests/") or not is_sha256(cell_manifest_sha):
            raise SystemExit(f"ROAD_MUNICIPALITY_AUDIT_FAIL: registered cell provenance incomplete {road_id}")
        raw_municipalities = row.get("municipalities")
        if not isinstance(raw_municipalities, list) or not raw_municipalities:
            raise SystemExit(f"ROAD_MUNICIPALITY_AUDIT_FAIL: registered municipality provenance missing {road_id}")
        ratio_sum = 0.0
        for municipality in raw_municipalities:
            nis = str(municipality.get("niscode") or "")
            inspire = str(municipality.get("inspire_id") or "")
            ratio = float(municipality.get("coverage_ratio"))
            if not nis or not inspire or not (0.0 < ratio <= 1.0):
                raise SystemExit(f"ROAD_MUNICIPALITY_AUDIT_FAIL: invalid municipality evidence {road_id}")
            ratio_sum += ratio
            bucket = municipalities.setdefault(nis, {
                "niscode": nis,
                "inspire_ids": set(),
                "road_osm_ids": set(),
                "cell_ids": set(),
                "cell_manifest_paths": set(),
                "cell_manifest_sha256": set(),
                "weighted_road_coverage": 0.0,
            })
            bucket["inspire_ids"].add(inspire)
            bucket["road_osm_ids"].add(road_id)
            bucket["cell_ids"].add(cell_id)
            bucket["cell_manifest_paths"].add(cell_manifest_path)
            bucket["cell_manifest_sha256"].add(cell_manifest_sha)
            bucket["weighted_road_coverage"] += ratio
        if abs(ratio_sum - 1.0) > 1e-9:
            raise SystemExit(f"ROAD_MUNICIPALITY_AUDIT_FAIL: municipality ratio drift {road_id}")

    municipality_rows = []
    for nis in sorted(municipalities):
        bucket = municipalities[nis]
        municipality_rows.append({
            "niscode": nis,
            "inspire_ids": sorted(bucket["inspire_ids"]),
            "registered_road_count": len(bucket["road_osm_ids"]),
            "registered_road_osm_ids": sorted(bucket["road_osm_ids"]),
            "cell_count": len(bucket["cell_ids"]),
            "cell_ids": sorted(bucket["cell_ids"]),
            "cell_manifest_paths": sorted(bucket["cell_manifest_paths"]),
            "cell_manifest_sha256": sorted(bucket["cell_manifest_sha256"]),
            "weighted_road_coverage": round(float(bucket["weighted_road_coverage"]), 12),
            "readiness": "REGISTERED_NOT_RENDERED",
        })

    payload: dict[str, Any] = {
        "format": FORMAT,
        "upstream_binding_sha256": binding["binding_sha256"],
        "source_catalog_sha256": binding["source_catalog_sha256"],
        "readiness_catalog_semantic_sha256": binding["readiness_catalog_semantic_sha256"],
        "source_document_sha256": binding["source_document_sha256"],
        "source_entry_count": int(binding["entry_count"]),
        "registered_not_rendered_count": len(registered_ids),
        "discovered_unassigned_count": len(discovered_unassigned),
        "discovered_unassigned_road_osm_ids": sorted(discovered_unassigned),
        "municipality_count_with_registered_evidence": len(municipality_rows),
        "municipality_niscodes": [row["niscode"] for row in municipality_rows],
        "municipalities": municipality_rows,
        "coverage_scope": "registered-evidence-only",
        "automatic_19_commune_completion_claimed": False,
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
    payload["audit_sha256"] = sha256_json(payload)
    return payload


def validate_audit(audit: dict[str, Any]) -> None:
    if audit.get("format") != FORMAT:
        raise SystemExit("ROAD_MUNICIPALITY_AUDIT_FAIL: format drift")
    for key in ("upstream_binding_sha256", "source_catalog_sha256", "readiness_catalog_semantic_sha256"):
        if not is_sha256(audit.get(key)):
            raise SystemExit(f"ROAD_MUNICIPALITY_AUDIT_FAIL: invalid {key}")
    if audit.get("coverage_scope") != "registered-evidence-only" or audit.get("automatic_19_commune_completion_claimed") is not False:
        raise SystemExit("ROAD_MUNICIPALITY_AUDIT_FAIL: coverage claim drift")
    municipalities = audit.get("municipalities")
    if not isinstance(municipalities, list) or len(municipalities) != int(audit.get("municipality_count_with_registered_evidence", -1)):
        raise SystemExit("ROAD_MUNICIPALITY_AUDIT_FAIL: municipality accounting drift")
    if [row.get("niscode") for row in municipalities] != audit.get("municipality_niscodes"):
        raise SystemExit("ROAD_MUNICIPALITY_AUDIT_FAIL: municipality index drift")
    seen_nis: set[str] = set()
    for row in municipalities:
        if not isinstance(row, dict):
            raise SystemExit("ROAD_MUNICIPALITY_AUDIT_FAIL: malformed municipality row")
        nis = str(row.get("niscode") or "")
        if not nis or nis in seen_nis:
            raise SystemExit("ROAD_MUNICIPALITY_AUDIT_FAIL: municipality identity drift")
        seen_nis.add(nis)
        if row.get("readiness") != "REGISTERED_NOT_RENDERED":
            raise SystemExit(f"ROAD_MUNICIPALITY_AUDIT_FAIL: municipality readiness drift {nis}")
        road_ids = row.get("registered_road_osm_ids")
        if not isinstance(road_ids, list) or road_ids != sorted(set(road_ids)) or int(row.get("registered_road_count", -1)) != len(road_ids):
            raise SystemExit(f"ROAD_MUNICIPALITY_AUDIT_FAIL: municipality road accounting drift {nis}")
        cell_ids = row.get("cell_ids")
        if not isinstance(cell_ids, list) or not cell_ids or cell_ids != sorted(set(cell_ids)) or int(row.get("cell_count", -1)) != len(cell_ids):
            raise SystemExit(f"ROAD_MUNICIPALITY_AUDIT_FAIL: municipality cell accounting drift {nis}")
        inspire_ids = row.get("inspire_ids")
        if not isinstance(inspire_ids, list) or not inspire_ids or inspire_ids != sorted(set(inspire_ids)) or any(not str(value) for value in inspire_ids):
            raise SystemExit(f"ROAD_MUNICIPALITY_AUDIT_FAIL: municipality INSPIRE identity drift {nis}")
        manifest_paths = row.get("cell_manifest_paths")
        if not isinstance(manifest_paths, list) or not manifest_paths or manifest_paths != sorted(set(manifest_paths)) or any(not str(path).startswith("data/cell_manifests/") for path in manifest_paths):
            raise SystemExit(f"ROAD_MUNICIPALITY_AUDIT_FAIL: municipality manifest path drift {nis}")
        manifest_shas = row.get("cell_manifest_sha256")
        if not isinstance(manifest_shas, list) or not manifest_shas or manifest_shas != sorted(set(manifest_shas)) or any(not is_sha256(value) for value in manifest_shas):
            raise SystemExit(f"ROAD_MUNICIPALITY_AUDIT_FAIL: municipality manifest sha drift {nis}")
        try:
            weighted = float(row.get("weighted_road_coverage"))
        except (TypeError, ValueError) as exc:
            raise SystemExit(f"ROAD_MUNICIPALITY_AUDIT_FAIL: municipality weighted coverage drift {nis}") from exc
        if weighted <= 0.0 or weighted > float(len(road_ids)):
            raise SystemExit(f"ROAD_MUNICIPALITY_AUDIT_FAIL: municipality weighted coverage drift {nis}")
    if int(audit.get("registered_not_rendered_count", -1)) + int(audit.get("discovered_unassigned_count", -1)) != int(audit.get("source_entry_count", -1)):
        raise SystemExit("ROAD_MUNICIPALITY_AUDIT_FAIL: source state accounting drift")
    auth = audit.get("authorization") or {}
    if auth.get("evidence_only") is not True or auth.get("source_registration_authorized") is not False or auth.get("road_cell_mapping_authorized") is not False:
        raise SystemExit("ROAD_MUNICIPALITY_AUDIT_FAIL: evidence rails drift")
    require_closed(auth, "audit")
    stored = str(audit.get("audit_sha256") or "").lower()
    unsigned = dict(audit)
    unsigned.pop("audit_sha256", None)
    if not is_sha256(stored) or stored != sha256_json(unsigned):
        raise SystemExit("ROAD_MUNICIPALITY_AUDIT_FAIL: audit sha drift")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-root", type=Path, default=Path("data/osm"))
    parser.add_argument("--readiness", type=Path, default=Path("data/provenance/brussels_road_destination_readiness_catalog.json"))
    parser.add_argument("--catalog-builder", type=Path, default=Path("tools/build_road_destination_catalog.py"))
    parser.add_argument("--binding-builder", type=Path, default=Path("tools/build_road_destination_provenance_binding.py"))
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    audit = build_audit(args.source_root, args.readiness, args.catalog_builder, args.binding_builder)
    validate_audit(audit)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(audit, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"ROAD_MUNICIPALITY_AUDIT_GREEN: entries={audit['source_entry_count']} registered={audit['registered_not_rendered_count']} discovered_unassigned={audit['discovered_unassigned_count']} municipalities={audit['municipality_count_with_registered_evidence']} sha256={audit['audit_sha256']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
