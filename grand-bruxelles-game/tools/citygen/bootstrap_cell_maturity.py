#!/usr/bin/env python3
"""Bootstrap a fail-closed maturity manifest from one authoritative CityGen source cell.

Only evidence already present in the source cell is promoted. Production maturity is
intentionally broader than runtime geometry: a Region-scale cell also needs source,
CRS, material/facade/clutter, mobility, verification, licensing and scalability proof.
The output is deterministic and safe to persist on the autonomous state branch; it
never mutates Godot runtime data.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any

FORMAT = "grand-bruxelles-cell-maturity-v1"
CRS = "EPSG:31370"
GATES = (
    "source_requirements",
    "crs",
    "runtime_geometry",
    "collisions",
    "streaming",
    "terrain",
    "heights",
    "materials",
    "facade",
    "clutter",
    "mobility",
    "verification",
    "license",
    "region_scalable",
    "photo_match",
    "performance",
)


def _read(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"expected JSON object: {path}")
    return value


def _digest(value: Any) -> str:
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")).hexdigest()


def _declared_source_file_specs(source: dict[str, Any]) -> list[tuple[str, dict[str, Any], str]]:
    """Return only explicit `layers[*].file` requirements in deterministic order."""
    layers = source.get("layers")
    if not isinstance(layers, dict):
        return []
    declared: list[tuple[str, dict[str, Any], str]] = []
    for layer_name, spec in sorted(layers.items()):
        if not isinstance(spec, dict):
            continue
        filename = spec.get("file")
        if not isinstance(filename, str) or not filename.strip():
            continue
        declared.append((str(layer_name), spec, filename.strip()))
    return declared


def missing_declared_source_files(source: dict[str, Any], cell_dir: Path) -> list[str]:
    """Return unsafe or absent explicitly declared source files without parsing payloads."""
    missing: list[str] = []
    for layer_name, _spec, declared in _declared_source_file_specs(source):
        relative = Path(declared)
        if relative.is_absolute() or ".." in relative.parts or not (cell_dir / relative).is_file():
            missing.append(f"{layer_name}:{declared}")
    return missing


def assess_source_requirements(source: dict[str, Any], cell_dir: Path) -> dict[str, Any]:
    """Assess the source-file contract explicitly declared by one cell manifest."""
    requirements: list[dict[str, Any]] = []
    blockers: list[str] = []
    for layer_name, spec, declared in _declared_source_file_specs(source):
        row: dict[str, Any] = {"layer": layer_name, "file": declared}
        relative = Path(declared)
        blocker_prefix = f"{layer_name}:{declared}"
        if relative.is_absolute() or ".." in relative.parts:
            row["status"] = "unsafe_path"
            blockers.append(f"unsafe_declared_source_file:{blocker_prefix}")
            requirements.append(row)
            continue
        source_path = cell_dir / relative
        if not source_path.is_file():
            row["status"] = "missing"
            blockers.append(f"missing_declared_source_file:{blocker_prefix}")
            requirements.append(row)
            continue
        try:
            payload = _read(source_path)
        except (OSError, ValueError, json.JSONDecodeError):
            row["status"] = "invalid_json"
            blockers.append(f"invalid_declared_source_file:{blocker_prefix}")
            requirements.append(row)
            continue

        row["content_digest"] = _digest(payload)
        if "features" in spec:
            declared_features = spec.get("features")
            row["declared_features"] = declared_features
            actual_features = payload.get("features")
            row["actual_features"] = len(actual_features) if isinstance(actual_features, list) else None
            if not isinstance(declared_features, int) or isinstance(declared_features, bool):
                row["status"] = "invalid_declared_feature_count"
                blockers.append(f"invalid_declared_feature_count:{blocker_prefix}")
                requirements.append(row)
                continue
            if not isinstance(actual_features, list):
                row["status"] = "features_not_list"
                blockers.append(f"source_features_not_list:{blocker_prefix}")
                requirements.append(row)
                continue
            if len(actual_features) != declared_features:
                row["status"] = "feature_count_mismatch"
                blockers.append(
                    f"declared_source_feature_count_mismatch:{blocker_prefix}:"
                    f"declared={declared_features}:actual={len(actual_features)}"
                )
                requirements.append(row)
                continue
        row["status"] = "validated"
        requirements.append(row)

    if not requirements:
        blockers.append("no_explicit_declared_source_files")
    complete = bool(requirements) and not blockers
    evidence = {
        "status": "validated" if complete else "evidence_pending",
        "complete": complete,
        "contract": "manifest.layers[*].file",
        "required_file_count": len(requirements),
        "requirements": requirements,
        "blockers": blockers,
    }
    evidence["requirements_digest"] = _digest(requirements)
    return evidence


def build(cell_dir: Path) -> dict[str, Any]:
    manifest_path = cell_dir / "manifest.json"
    buildings_path = cell_dir / "raw" / "buildings.geojson"
    if not manifest_path.exists():
        raise ValueError("authoritative source manifest missing")
    if not buildings_path.exists():
        raise ValueError("authoritative buildings source missing")

    source = _read(manifest_path)
    buildings = _read(buildings_path)
    cell_id = cell_dir.name
    if source.get("cell_id") != cell_id:
        raise ValueError("source cell identity mismatch")
    if source.get("crs") != CRS:
        raise ValueError("source cell CRS mismatch")
    bbox = source.get("bbox")
    if not isinstance(bbox, list) or len(bbox) != 4 or not all(isinstance(v, (int, float)) for v in bbox):
        raise ValueError("source cell bbox missing or invalid")
    if not (bbox[0] < bbox[2] and bbox[1] < bbox[3]) or min(bbox) < 10_000:
        raise ValueError("source cell bbox does not look like EPSG:31370")
    if buildings.get("type") != "FeatureCollection":
        raise ValueError("authoritative buildings source is not a FeatureCollection")

    layers = source.get("layers") or {}
    building_layer = layers.get("buildings") if isinstance(layers, dict) else None
    if not isinstance(building_layer, dict):
        raise ValueError("source manifest does not prove the buildings layer")
    declared_count = building_layer.get("features")
    actual_count = len(buildings.get("features") or [])
    if declared_count != actual_count:
        raise ValueError(f"building feature count mismatch manifest={declared_count} source={actual_count}")

    source_requirements = assess_source_requirements(source, cell_dir)
    invalid_ownership = int(building_layer.get("invalid_ownership_features", 0) or 0)
    authoritative_ready = invalid_ownership == 0
    source_gate_ready = bool(source_requirements["complete"] and authoritative_ready)
    source_requirements["gate_ready"] = source_gate_ready

    crs_evidence = {
        "status": "validated",
        "source_crs": CRS,
        "bbox": list(bbox),
        "contract": "manifest.crs + Lambert72-like positive ordered bbox",
        "gate_ready": True,
    }
    crs_evidence["evidence_digest"] = _digest(crs_evidence)

    verification_checks = {
        "authoritative_geometry_ready": authoritative_ready,
        "building_feature_count_matches": declared_count == actual_count,
        "canonical_ownership_valid": invalid_ownership == 0,
        "crs_contract_valid": True,
        "source_identity_valid": source.get("cell_id") == cell_id,
        "source_requirements_complete": bool(source_requirements["complete"]),
    }
    verification_blockers: list[str] = []
    if not verification_checks["source_requirements_complete"]:
        verification_blockers.append("source_requirements_incomplete")
    if not verification_checks["canonical_ownership_valid"]:
        verification_blockers.append("canonical_ownership_invalid")
    verification_ready = all(verification_checks.values()) and not verification_blockers
    verification_evidence = {
        "status": "validated" if verification_ready else "evidence_pending",
        "contract": "deterministic authoritative source bootstrap checks",
        "checks": verification_checks,
        "blockers": verification_blockers,
        "gate_ready": verification_ready,
    }
    verification_evidence["evidence_digest"] = _digest(verification_evidence)

    gates = {gate: False for gate in GATES}
    gates["source_requirements"] = source_gate_ready
    gates["crs"] = True
    gates["verification"] = verification_ready

    uncertainties = [
        "runtime geometry not generated or validated",
        "collision quality not validated",
        "streaming behavior not validated",
        "terrain evidence not acquired",
        "building height evidence not acquired",
        "shared materials not validated",
        "player-facing facade treatment not validated",
        "clutter baseline or explicit deferral not validated",
        "traffic/pedestrian branchability or absence rationale not validated",
        "asset/source licensing not validated for this cell",
        "hero-independent regional scalability not validated",
        "photo-match not evaluated for this cell",
        "streamed-cell performance not measured",
    ]
    if not verification_ready:
        uncertainties.insert(0, "automated deterministic source-verification witness is incomplete")
    if not source_gate_ready:
        uncertainties.insert(0, "explicitly declared source requirements are incomplete or invalid")
    if invalid_ownership:
        uncertainties.insert(0, "authoritative building source contains features with invalid canonical ownership")

    result = {
        "format": FORMAT,
        "cell_id": cell_id,
        "crs": CRS,
        "bbox": bbox,
        "maturity": {
            "state": "data_ready" if authoritative_ready else "quarantine",
            "gates": gates,
        },
        "provenance": {
            "source_records_present": True,
            "primary": "UrbIS WFS / Paradigm",
            "source_manifest_digest": _digest(source),
            "buildings_source_digest": _digest(buildings),
            "source_requirements_digest": _digest(source_requirements),
            "crs_evidence_digest": crs_evidence["evidence_digest"],
            "verification_evidence_digest": verification_evidence["evidence_digest"],
        },
        "source_requirements": source_requirements,
        "crs_evidence": crs_evidence,
        "verification_evidence": verification_evidence,
        "geometry": {
            "authoritative_geometry_ready": authoritative_ready,
            "source_manifest": f"data/urbis/remaining_brussels/cells/{cell_id}/manifest.json",
            "layers": ["buildings"],
            "building_feature_count": actual_count,
        },
        "terrain": {"status": "evidence_pending"},
        "heights": {"status": "evidence_pending"},
        "collisions": {"status": "not_validated"},
        "streaming": {"status": "not_validated"},
        "photo_match": {"status": "not_evaluated", "open_major_mismatches": None},
        "performance": {"status": "not_measured_as_streamed_cell", "budget_pass": False},
        "uncertainties": uncertainties,
    }
    result["maturity_digest"] = _digest(result)
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--cell-dir", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = build(args.cell_dir)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(
        "BOOTSTRAP_CELL_MATURITY_OK",
        result["cell_id"],
        result["maturity"]["state"],
        result["geometry"]["building_feature_count"],
        result["maturity_digest"],
    )


if __name__ == "__main__":
    main()
