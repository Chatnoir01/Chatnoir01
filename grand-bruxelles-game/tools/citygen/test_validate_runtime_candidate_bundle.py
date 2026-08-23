#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("validate_runtime_candidate_bundle", HERE / "validate_runtime_candidate_bundle.py")
mod = importlib.util.module_from_spec(SPEC)
assert SPEC and SPEC.loader
SPEC.loader.exec_module(mod)


def write(path: Path, value) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, sort_keys=True) + "\n", encoding="utf-8")


with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    bundle = root / "bundle"
    source = root / "source"
    cell = "bxl-e149000-n169000-s500"

    source_payloads = {
        "manifest.json": {"format": "grand-bruxelles-urbis-source-cell-v1", "cell_id": cell, "crs": "EPSG:31370"},
        "raw/buildings.geojson": {"type": "FeatureCollection", "features": []},
        "raw/street_surfaces.geojson": {"type": "FeatureCollection", "features": []},
        "raw/street_axes.geojson": {"type": "FeatureCollection", "features": []},
        "raw/tram_network.geojson": {"type": "FeatureCollection", "features": []},
        "raw/train_network.geojson": {"type": "FeatureCollection", "features": []},
    }
    for rel, payload in source_payloads.items():
        write(source / rel, payload)

    auth = {
        "candidate_only": True,
        "runtime_mount_authorized": False,
        "collision_authorized": False,
        "terrain_runtime_authorized": False,
        "jouable_promotion_authorized": False,
        "mobility_runtime_authorized": False,
    }
    manifest = {
        "format": mod.CANDIDATE_BUILT_FORMAT,
        "cell_id": cell,
        "authorization": auth,
        "promotion": {
            "state": "qa_candidate_only",
            "production_discovery_eligible": False,
            "requires_explicit_validated_promotion": True,
        },
    }
    runtime_cell = {
        "format": mod.RUNTIME_CELL_FORMAT,
        "cell_id": cell,
        "authorization": auth,
        "buildings": [],
    }
    runtime_network = {
        "format": mod.RUNTIME_NETWORK_FORMAT,
        "cell_id": cell,
        "authorization": auth,
    }
    write(bundle / "manifest.json", manifest)
    write(bundle / "runtime" / "cell.game.json", runtime_cell)
    write(bundle / "runtime" / "network.game.json", runtime_network)

    candidate = {
        "format": mod.CANDIDATE_FORMAT,
        "cell_id": cell,
        "source_crs": "EPSG:31370",
        "input_sha256": {rel: mod._sha(source / rel) for rel in mod.REQUIRED_INPUTS},
        "output_sha256": {
            "manifest.json": mod._sha(bundle / "manifest.json"),
            "runtime/cell.game.json": mod._sha(bundle / "runtime" / "cell.game.json"),
            "runtime/network.game.json": mod._sha(bundle / "runtime" / "network.game.json"),
        },
        "safety": {
            "official_plan_geometry_only": True,
            "building_height_invented": False,
            "collision_generated": False,
            "runtime_mount_authorized": False,
            "jouable_promotion_authorized": False,
        },
    }
    candidate["candidate_digest"] = mod._digest(candidate)
    write(bundle / "candidate.json", candidate)

    valid = mod.validate(bundle, source)
    assert valid["status"] == "validated", valid["blockers"]
    assert valid["maturity_evidence_ready"] is True
    assert valid["promotion_ready"] is False
    assert valid["authorization"]["runtime_mount_authorized"] is False
    assert valid["authorization"]["jouable_promotion_authorized"] is False
    assert valid["next_gate"] == "attach_validated_runtime_candidate_evidence_to_cell_maturity_manifest"

    # Authoritative source drift must invalidate the candidate rather than silently
    # reusing an old bundle.
    write(source / "raw/street_surfaces.geojson", {"type": "FeatureCollection", "features": [{"id": "changed"}]})
    stale = mod.validate(bundle, source)
    assert stale["status"] == "blocked"
    assert stale["maturity_evidence_ready"] is False
    assert "stale_or_missing_source:raw/street_surfaces.geojson" in stale["blockers"]
    assert stale["promotion_ready"] is False

    # Restore source, then corrupt an output payload. Hash verification must catch it.
    write(source / "raw/street_surfaces.geojson", source_payloads["raw/street_surfaces.geojson"])
    runtime_network["unexpected"] = True
    write(bundle / "runtime" / "network.game.json", runtime_network)
    corrupt = mod.validate(bundle, source)
    assert corrupt["status"] == "blocked"
    assert "output_hash_mismatch:runtime/network.game.json" in corrupt["blockers"]
    assert corrupt["promotion_ready"] is False

print("VALIDATE_RUNTIME_CANDIDATE_BUNDLE_OK fresh=true stale_source_blocked=true output_tamper_blocked=true promotion_bypass=false")
