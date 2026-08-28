#!/usr/bin/env python3
"""Build the deterministic acquisition frontier for DISCOVERED road destinations.

This artifact answers only: which source-backed roads still need registration evidence,
and exactly which evidence classes are missing. It never assigns a cell or municipality.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
from typing import Any

FORMAT = "grand-bruxelles-road-acquisition-frontier-v1"
POLICY = "NO_INFERENCE_SOURCE_EVIDENCE_REQUIRED"
REQUIRED_EVIDENCE = [
    "exact_source_geometry_identity",
    "source_backed_epsg31370_cell_intersection",
    "locked_cell_manifest_identity",
    "explicit_municipality_provenance",
]
UPSTREAM_CLOSED_KEYS = (
    "render_authorized",
    "collision_authorized",
    "runtime_mount_authorized",
    "safe_spawn_authorized",
    "jouable_authorized",
)
FRONTIER_CLOSED_KEYS = (
    "source_registration_authorized",
    "road_cell_mapping_authorized",
    *UPSTREAM_CLOSED_KEYS,
)


def canonical_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def sha256_json(value: Any) -> str:
    return hashlib.sha256(canonical_json(value).encode("utf-8")).hexdigest()


def is_sha256(value: Any) -> bool:
    text = str(value or "").lower()
    return len(text) == 64 and all(ch in "0123456789abcdef" for ch in text)


def load_module(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise SystemExit(f"ROAD_ACQUISITION_FRONTIER_FAIL: cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def require_closed(mapping: dict[str, Any], keys: tuple[str, ...], label: str) -> None:
    for key in keys:
        if mapping.get(key) is not False:
            raise SystemExit(f"ROAD_ACQUISITION_FRONTIER_FAIL: {label} opened {key}")


def validate_source_documents(raw: Any, label: str) -> dict[str, str]:
    if not isinstance(raw, dict) or not raw:
        raise SystemExit(f"ROAD_ACQUISITION_FRONTIER_FAIL: missing {label} source documents")
    normalized: dict[str, str] = {}
    for raw_path, raw_digest in raw.items():
        path = str(raw_path or "")
        digest = str(raw_digest or "").lower()
        if not path or not is_sha256(digest):
            raise SystemExit(f"ROAD_ACQUISITION_FRONTIER_FAIL: invalid {label} source document {path!r}")
        normalized[path] = digest
    if list(normalized) != sorted(normalized):
        normalized = dict(sorted(normalized.items()))
    return normalized


def _build_frontier_unchecked(
    source_root: Path,
    readiness: Path,
    catalog_builder: Path,
    binding_builder_path: Path,
    municipality_audit_builder_path: Path,
) -> dict[str, Any]:
    binding_builder = load_module(binding_builder_path, "road_provenance_binding_frontier")
    binding = binding_builder.build_binding(source_root, readiness, catalog_builder)
    binding_builder.validate_binding(binding)
    require_closed(binding.get("authorization") or {}, UPSTREAM_CLOSED_KEYS, "upstream binding")

    audit_builder = load_module(municipality_audit_builder_path, "road_municipality_audit_frontier")
    audit = audit_builder.build_audit(source_root, readiness, catalog_builder, binding_builder_path)
    audit_builder.validate_audit(audit)
    require_closed(audit.get("authorization") or {}, UPSTREAM_CLOSED_KEYS, "upstream municipality audit")

    if audit.get("upstream_binding_sha256") != binding.get("binding_sha256"):
        raise SystemExit("ROAD_ACQUISITION_FRONTIER_FAIL: upstream binding/audit identity drift")

    source_documents = validate_source_documents(binding.get("source_document_sha256"), "upstream")
    discovered_ids = audit.get("discovered_unassigned_road_osm_ids")
    if not isinstance(discovered_ids, list):
        raise SystemExit("ROAD_ACQUISITION_FRONTIER_FAIL: missing discovered frontier")

    candidates: list[dict[str, Any]] = []
    for road_id in discovered_ids:
        row = (binding.get("entries") or {}).get(str(road_id))
        if not isinstance(row, dict) or row.get("state") != "DISCOVERED":
            raise SystemExit(f"ROAD_ACQUISITION_FRONTIER_FAIL: discovered source binding drift {road_id}")
        require_closed(row, UPSTREAM_CLOSED_KEYS, f"road {road_id}")
        if row.get("cell_id") is not None or row.get("municipalities") is not None:
            raise SystemExit(f"ROAD_ACQUISITION_FRONTIER_FAIL: discovered road already carries inferred assignment {road_id}")
        geometry_sha = str(row.get("source_geometry_sha256") or "").lower()
        source_paths = row.get("source_paths")
        if not is_sha256(geometry_sha):
            raise SystemExit(f"ROAD_ACQUISITION_FRONTIER_FAIL: missing source geometry identity {road_id}")
        if not isinstance(source_paths, list) or not source_paths or source_paths != sorted(set(source_paths)):
            raise SystemExit(f"ROAD_ACQUISITION_FRONTIER_FAIL: source path identity drift {road_id}")
        missing_paths = [path for path in source_paths if path not in source_documents]
        if missing_paths:
            raise SystemExit(f"ROAD_ACQUISITION_FRONTIER_FAIL: missing source document hash {road_id}: {missing_paths}")
        candidate_source_documents = {path: source_documents[path] for path in source_paths}
        candidates.append({
            "road_osm_id": int(road_id),
            "name": str(row.get("name") or ""),
            "state": "DISCOVERED",
            "source_paths": source_paths,
            "source_document_sha256": candidate_source_documents,
            "source_geometry_sha256": geometry_sha,
            "cell_id": None,
            "municipalities": None,
            "proposed_cell_id": None,
            "proposed_municipality_niscodes": None,
            "required_evidence": list(REQUIRED_EVIDENCE),
            "registration_ready": False,
        })

    candidates.sort(key=lambda item: item["road_osm_id"])
    payload: dict[str, Any] = {
        "format": FORMAT,
        "upstream_binding_sha256": binding["binding_sha256"],
        "upstream_municipality_audit_sha256": audit["audit_sha256"],
        "source_catalog_sha256": binding["source_catalog_sha256"],
        "readiness_catalog_semantic_sha256": binding["readiness_catalog_semantic_sha256"],
        "source_document_sha256": source_documents,
        "source_entry_count": int(binding["entry_count"]),
        "registered_not_rendered_count": int(binding["registered_not_rendered_count"]),
        "acquisition_candidate_count": len(candidates),
        "candidate_road_osm_ids": [row["road_osm_id"] for row in candidates],
        "candidates": candidates,
        "assignment_policy": POLICY,
        "automatic_registration_claimed": False,
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
    payload["frontier_sha256"] = sha256_json(payload)
    return payload


def validate_structure(frontier: dict[str, Any]) -> None:
    if frontier.get("format") != FORMAT:
        raise SystemExit("ROAD_ACQUISITION_FRONTIER_FAIL: format drift")
    for key in (
        "upstream_binding_sha256",
        "upstream_municipality_audit_sha256",
        "source_catalog_sha256",
        "readiness_catalog_semantic_sha256",
    ):
        if not is_sha256(frontier.get(key)):
            raise SystemExit(f"ROAD_ACQUISITION_FRONTIER_FAIL: invalid {key}")
    source_documents = validate_source_documents(frontier.get("source_document_sha256"), "frontier")
    if frontier.get("assignment_policy") != POLICY or frontier.get("automatic_registration_claimed") is not False:
        raise SystemExit("ROAD_ACQUISITION_FRONTIER_FAIL: assignment policy drift")

    candidates = frontier.get("candidates")
    if not isinstance(candidates, list) or len(candidates) != int(frontier.get("acquisition_candidate_count", -1)):
        raise SystemExit("ROAD_ACQUISITION_FRONTIER_FAIL: candidate accounting drift")
    ids = [row.get("road_osm_id") if isinstance(row, dict) else None for row in candidates]
    if ids != sorted(set(ids)) or any(not isinstance(value, int) or value <= 0 for value in ids):
        raise SystemExit("ROAD_ACQUISITION_FRONTIER_FAIL: candidate identity drift")
    if ids != frontier.get("candidate_road_osm_ids"):
        raise SystemExit("ROAD_ACQUISITION_FRONTIER_FAIL: candidate index drift")
    if int(frontier.get("registered_not_rendered_count", -1)) + len(candidates) != int(frontier.get("source_entry_count", -1)):
        raise SystemExit("ROAD_ACQUISITION_FRONTIER_FAIL: source accounting drift")

    for row in candidates:
        road_id = row["road_osm_id"]
        if row.get("state") != "DISCOVERED" or row.get("registration_ready") is not False:
            raise SystemExit(f"ROAD_ACQUISITION_FRONTIER_FAIL: candidate state drift {road_id}")
        if any(row.get(key) is not None for key in ("cell_id", "municipalities", "proposed_cell_id", "proposed_municipality_niscodes")):
            raise SystemExit(f"ROAD_ACQUISITION_FRONTIER_FAIL: inferred assignment {road_id}")
        if row.get("required_evidence") != REQUIRED_EVIDENCE:
            raise SystemExit(f"ROAD_ACQUISITION_FRONTIER_FAIL: evidence requirements drift {road_id}")
        if not is_sha256(row.get("source_geometry_sha256")):
            raise SystemExit(f"ROAD_ACQUISITION_FRONTIER_FAIL: source geometry identity drift {road_id}")
        source_paths = row.get("source_paths")
        if not isinstance(source_paths, list) or not source_paths or source_paths != sorted(set(source_paths)):
            raise SystemExit(f"ROAD_ACQUISITION_FRONTIER_FAIL: source path identity drift {road_id}")
        per_candidate = validate_source_documents(row.get("source_document_sha256"), f"candidate {road_id}")
        expected_documents = {path: source_documents[path] for path in source_paths if path in source_documents}
        if len(expected_documents) != len(source_paths) or per_candidate != expected_documents:
            raise SystemExit(f"ROAD_ACQUISITION_FRONTIER_FAIL: source document binding drift {road_id}")

    auth = frontier.get("authorization") or {}
    if auth.get("evidence_only") is not True:
        raise SystemExit("ROAD_ACQUISITION_FRONTIER_FAIL: evidence-only rail missing")
    require_closed(auth, FRONTIER_CLOSED_KEYS, "frontier")

    stored = str(frontier.get("frontier_sha256") or "").lower()
    unsigned = dict(frontier)
    unsigned.pop("frontier_sha256", None)
    if not is_sha256(stored) or stored != sha256_json(unsigned):
        raise SystemExit("ROAD_ACQUISITION_FRONTIER_FAIL: frontier sha drift")


def build_frontier(
    source_root: Path,
    readiness: Path,
    catalog_builder: Path,
    binding_builder_path: Path,
    municipality_audit_builder_path: Path,
) -> dict[str, Any]:
    frontier = _build_frontier_unchecked(
        source_root, readiness, catalog_builder, binding_builder_path, municipality_audit_builder_path
    )
    validate_structure(frontier)
    return frontier


def validate_frontier(
    frontier: dict[str, Any],
    source_root: Path,
    readiness: Path,
    catalog_builder: Path,
    binding_builder_path: Path,
    municipality_audit_builder_path: Path,
) -> None:
    validate_structure(frontier)
    expected = _build_frontier_unchecked(
        source_root, readiness, catalog_builder, binding_builder_path, municipality_audit_builder_path
    )
    if canonical_json(frontier) != canonical_json(expected):
        raise SystemExit("ROAD_ACQUISITION_FRONTIER_FAIL: source binding drift")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-root", type=Path, default=Path("data/osm"))
    parser.add_argument("--readiness", type=Path, default=Path("data/provenance/brussels_road_destination_readiness_catalog.json"))
    parser.add_argument("--catalog-builder", type=Path, default=Path("tools/build_road_destination_catalog.py"))
    parser.add_argument("--binding-builder", type=Path, default=Path("tools/build_road_destination_provenance_binding.py"))
    parser.add_argument("--municipality-audit-builder", type=Path, default=Path("tools/build_road_municipality_coverage_audit.py"))
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    frontier = build_frontier(
        args.source_root,
        args.readiness,
        args.catalog_builder,
        args.binding_builder,
        args.municipality_audit_builder,
    )
    validate_frontier(
        frontier,
        args.source_root,
        args.readiness,
        args.catalog_builder,
        args.binding_builder,
        args.municipality_audit_builder,
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(frontier, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(
        "ROAD_ACQUISITION_FRONTIER_GREEN: "
        f"candidates={frontier['acquisition_candidate_count']} "
        f"registered={frontier['registered_not_rendered_count']} sha256={frontier['frontier_sha256']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
