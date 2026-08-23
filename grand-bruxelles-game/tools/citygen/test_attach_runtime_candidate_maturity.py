#!/usr/bin/env python3
from __future__ import annotations

import copy
import hashlib
import importlib.util
import json
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("attach_runtime_maturity", HERE / "attach_runtime_candidate_maturity.py")
mod = importlib.util.module_from_spec(SPEC)
assert SPEC and SPEC.loader
SPEC.loader.exec_module(mod)

CELL = "bxl-e143000-n167000-s500"


def write_json(path: Path, value) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def make_fixture(root: Path):
    source = root / "source"
    write_json(source / "manifest.json", {"format": "grand-bruxelles-urbis-source-cell-v1", "cell_id": CELL, "crs": "EPSG:31370"})
    for name in ("buildings", "street_axes", "street_surfaces", "train_network", "tram_network"):
        write_json(source / "raw" / f"{name}.geojson", {"type": "FeatureCollection", "features": [], "cell_id": CELL, "layer": name})
    hashes = {
        "manifest.json": sha(source / "manifest.json"),
        **{f"raw/{name}.geojson": sha(source / "raw" / f"{name}.geojson") for name in ("buildings", "street_axes", "street_surfaces", "train_network", "tram_network")},
    }

    maturity = {
        "format": mod.MATURITY_FORMAT,
        "cell_id": CELL,
        "crs": "EPSG:31370",
        "maturity": {
            "state": "data_ready",
            "gates": {
                "source_requirements": True,
                "crs": True,
                "runtime_geometry": False,
                "collisions": False,
                "streaming": False,
                "terrain": False,
                "heights": False,
                "materials": False,
                "facade": False,
                "clutter": False,
                "mobility": False,
                "verification": True,
                "license": False,
                "region_scalable": False,
                "photo_match": False,
                "performance": False,
            },
        },
        "uncertainties": [mod.RUNTIME_UNCERTAINTY, "collision quality not validated"],
        "collisions": {"status": "not_validated"},
        "terrain": {"status": "evidence_pending"},
        "performance": {"status": "not_measured_as_streamed_cell", "budget_pass": False},
    }
    maturity["maturity_digest"] = mod._digest(maturity)
    write_json(root / "maturity.json", maturity)

    candidate = {
        "format": mod.CANDIDATE_FORMAT,
        "cell_id": CELL,
        "input_sha256": hashes,
        "output_sha256": {
            "manifest.json": "out-manifest",
            "runtime/cell.game.json": "out-cell",
            "runtime/network.game.json": "out-network",
        },
        "source_crs": "EPSG:31370",
        "stats": {"buildings": 0, "street_surfaces": 0, "street_segments": 0},
        "safety": {
            "official_plan_geometry_only": True,
            "building_height_invented": False,
            "collision_generated": False,
            "runtime_mount_authorized": False,
            "jouable_promotion_authorized": False,
        },
        "sealed": {
            "root_manifest_format": mod.CANDIDATE_ROOT_FORMAT,
            "production_manifest_format": "grand-bruxelles-urbis-built-cell-v1",
            "production_discovery_eligible": False,
            "requires_explicit_validated_promotion": True,
        },
        "next_gate": "validate_runtime_candidate_then_attach_maturity_evidence_before_promotion",
    }
    candidate["candidate_digest"] = mod._digest(candidate)
    write_json(root / "candidate.json", candidate)

    validation = {
        "format": mod.VALIDATION_FORMAT,
        "cell_id": CELL,
        "status": "validated",
        "blockers": [],
        "candidate_digest": candidate["candidate_digest"],
        "source_hashes_current": hashes,
        "maturity_evidence_ready": True,
        "promotion_ready": False,
        "authorization": {
            "candidate_only": True,
            "runtime_mount_authorized": False,
            "jouable_promotion_authorized": False,
        },
        "next_gate": "attach_validated_runtime_candidate_evidence_to_cell_maturity_manifest",
        "validation_digest": "validation-digest-fixture",
    }
    write_json(root / "validation.json", validation)
    return source, maturity, candidate, validation


with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    source, maturity, candidate, validation = make_fixture(root)
    baseline_gates = copy.deepcopy(maturity["maturity"]["gates"])

    result = mod.attach(root / "maturity.json", root / "validation.json", root / "candidate.json", source / "manifest.json")
    assert result["maturity"]["gates"]["runtime_geometry"] is True
    for gate, value in baseline_gates.items():
        if gate != "runtime_geometry":
            assert result["maturity"]["gates"][gate] is value, gate
    assert result["maturity"]["state"] == "data_ready"
    assert mod.RUNTIME_UNCERTAINTY not in result["uncertainties"]
    assert "collision quality not validated" in result["uncertainties"]
    evidence = result["runtime_geometry_evidence"]
    assert evidence["gate_ready"] is True
    assert evidence["runtime_mount_authorized"] is False
    assert evidence["jouable_promotion_authorized"] is False
    assert evidence["collision_authorized"] is False
    assert evidence["terrain_runtime_authorized"] is False

    write_json(root / "maturity-attached.json", result)
    again = mod.attach(root / "maturity-attached.json", root / "validation.json", root / "candidate.json", source / "manifest.json")
    assert again == result, "attachment must be byte-stable/idempotent after canonical JSON write"

    stale_validation = copy.deepcopy(validation)
    stale_validation["source_hashes_current"]["manifest.json"] = "0" * 64
    write_json(root / "validation-stale.json", stale_validation)
    try:
        mod.attach(root / "maturity.json", root / "validation-stale.json", root / "candidate.json", source / "manifest.json")
    except ValueError as exc:
        assert "input hashes differ" in str(exc) or "source drift" in str(exc)
    else:
        raise AssertionError("stale source evidence must fail closed")

    blocked = copy.deepcopy(validation)
    blocked["status"] = "blocked"
    write_json(root / "validation-blocked.json", blocked)
    try:
        mod.attach(root / "maturity.json", root / "validation-blocked.json", root / "candidate.json", source / "manifest.json")
    except ValueError as exc:
        assert "not validated" in str(exc)
    else:
        raise AssertionError("blocked validation must fail closed")

    unsafe = copy.deepcopy(candidate)
    unsafe["safety"]["runtime_mount_authorized"] = True
    unsafe.pop("candidate_digest", None)
    unsafe["candidate_digest"] = mod._digest(unsafe)
    unsafe_validation = copy.deepcopy(validation)
    unsafe_validation["candidate_digest"] = unsafe["candidate_digest"]
    write_json(root / "candidate-unsafe.json", unsafe)
    write_json(root / "validation-unsafe.json", unsafe_validation)
    try:
        mod.attach(root / "maturity.json", root / "validation-unsafe.json", root / "candidate-unsafe.json", source / "manifest.json")
    except ValueError as exc:
        assert "runtime_mount_authorized" in str(exc)
    else:
        raise AssertionError("runtime authorization bypass must fail closed")

    promotion = copy.deepcopy(validation)
    promotion["promotion_ready"] = True
    write_json(root / "validation-promotion.json", promotion)
    try:
        mod.attach(root / "maturity.json", root / "validation-promotion.json", root / "candidate.json", source / "manifest.json")
    except ValueError as exc:
        assert "promotion_ready" in str(exc)
    else:
        raise AssertionError("promotion-ready evidence must not auto-attach")

print("RUNTIME_MATURITY_ATTACHMENT_TEST_OK runtime_geometry=true other_gates_unchanged=true state=data_ready stale_rejected=true unsafe_rejected=true promotion_bypass=false idempotent=true")
