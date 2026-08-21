#!/usr/bin/env python3
from __future__ import annotations

import copy
import importlib.util
import json
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
CELL = "bxl-e149000-n169000-s500"


def load(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


persist_mod = load("terrain_gate_persist_test", HERE / "persist_terrain_runtime_gate_measurement.py")
evidence_mod = persist_mod.evidence_mod
readiness_mod = evidence_mod.readiness_mod


def write(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def artifacts(root: Path) -> tuple[Path, Path, Path, Path, dict[str, str]]:
    cell = root / CELL
    terrain_path = cell / "terrain_lod_evidence.json"
    terrain_candidate_path = cell / "terrain_runtime_candidate.json"
    secondary_path = cell / "secondary_height_validation.json"
    runtime_path = root / "runtime" / CELL / "candidate.json"

    terrain = {
        "format": readiness_mod.TERRAIN_LOD_FORMAT,
        "cell_id": CELL,
        "crs": readiness_mod.CRS,
        "selection": {"selected_resolution_m": 2.0, "canonical_edge_alignment_required": True},
        "runtime_approved": False,
        "evidence_digest": "a" * 64,
    }
    terrain_candidate = {
        "format": readiness_mod.TERRAIN_CANDIDATE_FORMAT,
        "cell_id": CELL,
        "crs": readiness_mod.CRS,
        "spacing_m": 2.0,
        "topology": {
            "includes_all_four_canonical_cell_edges": True,
            "shared_edge_coordinates_are_exact": True,
        },
        "source": {"terrain_lod_evidence_digest": terrain["evidence_digest"]},
        "authorization": {
            "candidate_only": True,
            "terrain_runtime_authorized": False,
            "collision_authorized": False,
            "runtime_mount_authorized": False,
            "jouable_promotion_authorized": False,
        },
        "candidate_digest": "b" * 64,
    }
    secondary = {
        "format": readiness_mod.SECONDARY_FORMAT,
        "cell_id": CELL,
        "crs": readiness_mod.CRS,
        "secondary_validation_complete": True,
        "runtime_promotion_allowed": False,
        "validation_digest": "c" * 64,
    }
    runtime = {
        "format": readiness_mod.CANDIDATE_FORMAT,
        "cell_id": CELL,
        "sealed": {
            "production_discovery_eligible": False,
            "requires_explicit_validated_promotion": True,
        },
        "safety": {"runtime_mount_authorized": False, "collision_generated": False},
        "candidate_digest": "d" * 64,
    }
    write(terrain_path, terrain)
    write(terrain_candidate_path, terrain_candidate)
    write(secondary_path, secondary)
    write(runtime_path, runtime)
    _, bindings = evidence_mod._expected_bindings(terrain, terrain_candidate, secondary, runtime)
    return terrain_path, terrain_candidate_path, secondary_path, runtime_path, bindings


def bundle(bindings: dict[str, str], gate: str, status: str = "fixture", passed: bool = False) -> dict:
    row = {
        "cell_id": CELL,
        "gate": gate,
        "passed": passed,
        "status": status,
        "source": "deterministic_persistence_test_fixture",
        "metrics": {"fixture": True},
    }
    row["measurement_digest"] = evidence_mod._digest(row)
    result = {
        "format": evidence_mod.MEASUREMENT_FORMAT,
        "cell_id": CELL,
        "crs": readiness_mod.CRS,
        "bindings": copy.deepcopy(bindings),
        "gates": {gate: row},
        "policy": {"runtime_promotion_allowed": False},
    }
    result["measurement_bundle_digest"] = evidence_mod._digest(result)
    return result


def rehash(value: dict) -> dict:
    result = copy.deepcopy(value)
    result.pop("measurement_bundle_digest", None)
    result["measurement_bundle_digest"] = evidence_mod._digest(result)
    return result


def main() -> int:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        terrain, candidate, secondary, runtime, bindings = artifacts(root)
        measurement = root / "measurement.json"

        first = bundle(bindings, "streaming", "blocked_fixture", False)
        write(measurement, first)
        created = persist_mod.persist(terrain, candidate, secondary, runtime, measurement)
        target = terrain.parent / "terrain_streaming_gate_measurement.json"
        assert created["action"] == "created"
        assert target.is_file()
        assert json.loads(target.read_text()) == first

        discovered = evidence_mod.build(terrain, candidate, secondary, runtime, [])
        assert discovered["measured_gate_count"] == 1
        assert discovered["gates"]["streaming"]["status"] == "blocked_fixture"
        assert discovered["policy"]["persisted_measurement_files_checked"] == ["terrain_streaming_gate_measurement.json"]

        unchanged = persist_mod.persist(terrain, candidate, secondary, runtime, measurement)
        assert unchanged["action"] == "unchanged"

        fresh = bundle(bindings, "streaming", "remeasured_fixture", True)
        write(measurement, fresh)
        try:
            persist_mod.persist(terrain, candidate, secondary, runtime, measurement)
        except ValueError as exc:
            assert "explicit --replace-fresh" in str(exc)
        else:
            raise AssertionError("fresh conflicting measurement must require explicit replacement")
        replaced = persist_mod.persist(terrain, candidate, secondary, runtime, measurement, replace_fresh=True)
        assert replaced["action"] == "replaced_fresh_explicitly"
        assert json.loads(target.read_text()) == fresh

        stale_existing = copy.deepcopy(fresh)
        stale_existing["bindings"]["runtime_candidate_digest"] = "e" * 64
        stale_existing = rehash(stale_existing)
        write(target, stale_existing)
        replaced_stale = persist_mod.persist(terrain, candidate, secondary, runtime, measurement)
        assert replaced_stale["action"] == "replaced_stale"
        assert json.loads(target.read_text()) == fresh

        stale_input = copy.deepcopy(fresh)
        stale_input["bindings"]["runtime_candidate_digest"] = "e" * 64
        stale_input = rehash(stale_input)
        write(measurement, stale_input)
        try:
            persist_mod.persist(terrain, candidate, secondary, runtime, measurement)
        except ValueError as exc:
            assert "stale against exact cell artifacts" in str(exc)
        else:
            raise AssertionError("stale incoming measurement must fail closed")

        unsupported = bundle(bindings, "collisions", "fixture", True)
        write(measurement, unsupported)
        try:
            persist_mod.persist(terrain, candidate, secondary, runtime, measurement)
        except ValueError as exc:
            assert "not persistable" in str(exc)
        else:
            raise AssertionError("unsupported persisted gate must fail closed")

        multiple = bundle(bindings, "performance", "fixture", False)
        photo = bundle(bindings, "photo_match", "fixture", False)
        multiple["gates"].update(copy.deepcopy(photo["gates"]))
        multiple = rehash(multiple)
        write(measurement, multiple)
        try:
            persist_mod.persist(terrain, candidate, secondary, runtime, measurement)
        except ValueError as exc:
            assert "exactly one gate" in str(exc)
        else:
            raise AssertionError("multi-gate persisted bundle must fail closed")

        corrupt = copy.deepcopy(fresh)
        corrupt["gates"]["streaming"]["status"] = "tampered_without_row_rehash"
        corrupt = rehash(corrupt)
        write(target, corrupt)
        write(measurement, fresh)
        try:
            persist_mod.persist(terrain, candidate, secondary, runtime, measurement, replace_fresh=True)
        except ValueError as exc:
            assert "measurement digest mismatch: streaming" in str(exc)
        else:
            raise AssertionError("corrupted existing measurement must not be silently replaced")

        for gate, filename in persist_mod.PERSISTED_TARGETS.items():
            target_gate = terrain.parent / filename
            if target_gate.exists():
                target_gate.unlink()
            current = bundle(bindings, gate, f"{gate}_fixture", False)
            write(measurement, current)
            result = persist_mod.persist(terrain, candidate, secondary, runtime, measurement)
            assert result["gate"] == gate and result["action"] == "created"
            assert target_gate.is_file()

    print(
        "TERRAIN_GATE_MEASUREMENT_PERSIST_GUARDRAILS_OK exact_binding=true atomic=true "
        "idempotent=true stale_replaced=true fresh_conflict=blocked explicit_remeasurement=true "
        "corruption=rejected gates=streaming,performance,photo_match runtime_promotion=false"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
