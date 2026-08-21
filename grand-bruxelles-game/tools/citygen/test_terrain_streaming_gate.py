#!/usr/bin/env python3
from __future__ import annotations

import argparse
import copy
import importlib.util
import json
import shutil
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
CELL = "bxl-e149000-n169000-s500"
BBOX = [149000.0, 169000.0, 149500.0, 169500.0]
LAYERS = {
    "buildings": ("urbisvector:Buildings", "raw/buildings.geojson"),
    "street_surfaces": ("urbisvector:StreetSurfaces", "raw/street_surfaces.geojson"),
    "street_axes": ("urbisvector:StreetAxes", "raw/street_axes.geojson"),
    "tram_network": ("urbisvector:TramNetwork", "raw/tram_network.geojson"),
    "train_network": ("urbisvector:TrainNetwork", "raw/train_network.geojson"),
}


def load(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


compiler = load("streaming_runtime_compiler", HERE / "build_runtime_candidate_bundle.py")
sealer = load("streaming_runtime_sealer", HERE / "seal_runtime_candidate_bundle.py")
readiness = load("streaming_readiness", HERE / "build_terrain_runtime_readiness.py")
streaming = load("terrain_streaming_gate_test", HERE / "terrain_streaming_gate.py")


def write(path: Path, payload: dict, compact: bool = False) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    text = json.dumps(payload, separators=(",", ":")) if compact else json.dumps(payload, indent=2, sort_keys=True)
    path.write_text(text + "\n", encoding="utf-8")


def feature(fid: str, geometry: dict, **props) -> dict:
    return {"type": "Feature", "properties": {"INSPIRE_ID": fid, **props}, "geometry": geometry}


def polygon(points: list[list[float]]) -> dict:
    return {"type": "Polygon", "coordinates": [[*points, points[0]]]}


def line(points: list[list[float]]) -> dict:
    return {"type": "LineString", "coordinates": points}


def collection(layer_name: str, features: list[dict]) -> dict:
    return {
        "type": "FeatureCollection",
        "features": features,
        "numberReturned": len(features),
        "grand_bruxelles_source": {
            "authority": "Paradigm / Brussels-Capital Region",
            "service": "fixture://official-source-contract",
            "layer": layer_name,
            "crs": "EPSG:31370",
            "bbox": BBOX,
            "cell_id": CELL,
            "ownership": "fixture",
        },
    }


def write_source(root: Path) -> Path:
    cell = root / CELL
    docs = {
        "buildings": collection(LAYERS["buildings"][0], [
            feature("building-1", polygon([[149020,169020],[149060,169020],[149060,169060],[149020,169060]]), AREA=1600),
            feature("building-2", polygon([[149100,169030],[149130,169030],[149130,169065],[149100,169065]]), AREA=1050),
        ]),
        "street_surfaces": collection(LAYERS["street_surfaces"][0], [
            feature("surface-1", polygon([[149000,169080],[149150,169080],[149150,169120],[149000,169120]]), AREA=6000, TYPE="S", LVL=0, STRNAMEFRE="Rue Test", STRNAMEDUT="Teststraat"),
            feature("surface-2", polygon([[149160,169080],[149260,169080],[149260,169120],[149160,169120]]), AREA=4000, TYPE="SW", LVL=0),
        ]),
        "street_axes": collection(LAYERS["street_axes"][0], [feature("street-1", line([[149000,169100],[149500,169100]]), TYPE="S")]),
        "tram_network": collection(LAYERS["tram_network"][0], []),
        "train_network": collection(LAYERS["train_network"][0], []),
    }
    manifest_layers = {}
    for logical, (wfs_name, relative) in LAYERS.items():
        write(cell / relative, docs[logical], compact=True)
        manifest_layers[logical] = {"wfs_name": wfs_name, "features": len(docs[logical]["features"]), "file": relative}
    write(cell / "manifest.json", {
        "format": "grand-bruxelles-urbis-source-cell-v1",
        "cell_id": CELL,
        "crs": "EPSG:31370",
        "bbox": BBOX,
        "layers": manifest_layers,
        "promotion": "source_only_no_runtime_mutation",
    })
    return cell


def make_supporting_evidence(root: Path, runtime_digest: str) -> tuple[Path, Path, Path, Path]:
    terrain = {
        "format": readiness.TERRAIN_LOD_FORMAT,
        "cell_id": CELL,
        "crs": readiness.CRS,
        "selection": {"selected_resolution_m": 2.0, "canonical_edge_alignment_required": True},
        "runtime_approved": False,
        "evidence_digest": "a" * 64,
    }
    terrain_candidate = {
        "format": readiness.TERRAIN_CANDIDATE_FORMAT,
        "cell_id": CELL,
        "crs": readiness.CRS,
        "spacing_m": 2.0,
        "authorization": {
            "candidate_only": True,
            "terrain_runtime_authorized": False,
            "collision_authorized": False,
            "runtime_mount_authorized": False,
            "jouable_promotion_authorized": False,
        },
        "topology": {"includes_all_four_canonical_cell_edges": True, "shared_edge_coordinates_are_exact": True},
        "source": {"terrain_lod_evidence_digest": "a" * 64},
        "candidate_digest": "d" * 64,
    }
    secondary = {
        "format": readiness.SECONDARY_FORMAT,
        "cell_id": CELL,
        "crs": readiness.CRS,
        "secondary_validation_complete": True,
        "runtime_promotion_allowed": False,
        "validation_digest": "b" * 64,
    }
    paths = (root / "terrain.json", root / "terrain_candidate.json", root / "secondary.json", root / "candidate.json")
    for path, payload in zip(paths[:3], (terrain, terrain_candidate, secondary)):
        write(path, payload)
    return paths


def build_sealed_candidate(source_root: Path, candidate_dir: Path) -> dict:
    cell_dir = write_source(source_root)
    compiler.build(cell_dir, candidate_dir)
    sealed = sealer.seal(candidate_dir)
    assert sealed["sealed"]["production_discovery_eligible"] is False
    assert sealed["safety"]["runtime_mount_authorized"] is False
    return sealed


def synthetic_result(probe: dict, passed: bool = True) -> dict:
    good = passed
    return {
        "format": streaming.RESULT_FORMAT,
        "cell_id": probe["cell_id"],
        "probe_digest": probe["probe_digest"],
        "engine_version": streaming.ENGINE_VERSION,
        "passed": passed,
        "status": "passed_generic_candidate_prefetch_unload_cache" if passed else "failed_generic_candidate_prefetch_unload_cache",
        "metrics": {
            "descriptor_registered": good,
            "predictive_prefetch_outside_load_radius": good,
            "first_load_completed": good,
            "runtime_cell_id_match": good,
            "street_surface_count_match": good,
            "building_accounting_match": good,
            "first_unload_completed": good,
            "second_load_completed": good,
            "warm_cache_reused": good,
            "final_unload_completed": good,
            "production_index_used_false": True,
            "collision_claimed_false": True,
            "backend_load_count": 2 if good else 1,
            "backend_unload_count": 2 if good else 0,
            "backend_failed_load_count": 0,
            "collision_enable_count": 0,
            "duplicate_activation_attempts": 0,
            "cache_hits": 1 if good else 0,
            "cache_misses": 1,
            "cache_entries": 1,
            "cache_referenced_entries": 0,
            "first_cache_misses": 1,
            "second_cache_hits": 1 if good else 0,
            "first_stream_total_ms": 12,
            "first_stream_max_phase_ms": 4,
        },
    }


def run_guardrails(emit_fixture_root: Path | None, emit_probe_root: Path | None, resource_root: str | None) -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        source_root = root / "source"
        local_candidate = root / "candidate" / CELL
        sealed = build_sealed_candidate(source_root, local_candidate)
        support_root = root / "support"
        terrain_path, terrain_candidate_path, secondary_path, runtime_candidate_path = make_supporting_evidence(support_root, sealed["candidate_digest"])
        shutil.copy2(local_candidate / "candidate.json", runtime_candidate_path)
        probe = streaming.prepare(
            terrain_path, terrain_candidate_path, secondary_path, runtime_candidate_path,
            local_candidate, f"res://.qa_streaming_fixture/{CELL}",
        )
        assert probe["policy"]["production_runtime_index_used"] is False
        assert probe["policy"]["production_runtime_index_mutated"] is False
        assert probe["expected"] == {"buildings": 2, "street_surfaces": 2, "street_segments": 1}

        probe_path = root / "probe.json"
        write(probe_path, probe)
        result_path = root / "result.json"
        write(result_path, synthetic_result(probe, True))
        bundle = streaming.finalize(probe_path, result_path)
        row = bundle["gates"]["streaming"]
        assert row["passed"] is True
        assert row["status"] == "passed_godot_4_7_1_generic_candidate_streaming"
        assert all(row["metrics"]["contract_checks"].values())
        assert bundle["policy"]["runtime_promotion_allowed"] is False

        failed_path = root / "failed.json"
        write(failed_path, synthetic_result(probe, False))
        failed_bundle = streaming.finalize(probe_path, failed_path)
        assert failed_bundle["gates"]["streaming"]["passed"] is False

        stale = synthetic_result(probe, True)
        stale["probe_digest"] = "e" * 64
        stale_path = root / "stale.json"
        write(stale_path, stale)
        try:
            streaming.finalize(probe_path, stale_path)
        except ValueError as exc:
            assert "stale against exact probe" in str(exc)
        else:
            raise AssertionError("stale streaming result must fail closed")

        tampered = copy.deepcopy(probe)
        tampered["world_center"][0] += 1.0
        tampered_path = root / "tampered.json"
        write(tampered_path, tampered)
        try:
            streaming.finalize(tampered_path, result_path)
        except ValueError as exc:
            assert "probe digest mismatch" in str(exc)
        else:
            raise AssertionError("tampered streaming probe must fail closed")

        broken_candidate = root / "broken" / CELL
        shutil.copytree(local_candidate, broken_candidate)
        (broken_candidate / "runtime" / "cell.game.json").write_text("{}\n", encoding="utf-8")
        try:
            streaming.prepare(terrain_path, terrain_candidate_path, secondary_path, runtime_candidate_path, broken_candidate, f"res://.qa_streaming_fixture/{CELL}")
        except ValueError as exc:
            assert "payload hash drift" in str(exc)
        else:
            raise AssertionError("mutated candidate runtime payload must fail closed")

        if emit_fixture_root is not None or emit_probe_root is not None:
            if emit_fixture_root is None or emit_probe_root is None or resource_root is None:
                raise AssertionError("fixture/probe/resource root must be supplied together")
            target_candidate = emit_fixture_root / CELL
            if target_candidate.exists():
                shutil.rmtree(target_candidate)
            target_candidate.parent.mkdir(parents=True, exist_ok=True)
            shutil.copytree(local_candidate, target_candidate)
            emit_probe_root.mkdir(parents=True, exist_ok=True)
            emitted_probe = streaming.prepare(
                terrain_path, terrain_candidate_path, secondary_path, runtime_candidate_path,
                target_candidate, f"{resource_root.rstrip('/')}/{CELL}",
            )
            write(emit_probe_root / f"{CELL}.json", emitted_probe)

    print(
        "TERRAIN_STREAMING_GATE_GUARDRAILS_OK compiler=true sealed=true exact_hashes=true "
        "production_index=false negative_measurement=persisted stale=rejected tamper=rejected "
        "candidate_payload_drift=rejected runtime_promotion=false"
    )


def verify_results(probe_root: Path, result_root: Path, measurement_root: Path | None) -> None:
    probes = sorted(probe_root.glob("*.json"))
    if not probes:
        raise AssertionError("no streaming probes")
    passed = 0
    for probe_path in probes:
        result_path = result_root / probe_path.name
        if not result_path.is_file():
            raise AssertionError(f"missing Godot streaming result: {probe_path.name}")
        bundle = streaming.finalize(probe_path, result_path)
        row = bundle["gates"]["streaming"]
        assert row["passed"] is True, row
        assert all(row["metrics"]["contract_checks"].values())
        passed += 1
        if measurement_root is not None:
            write(measurement_root / probe_path.name, bundle)
    print(f"TERRAIN_STREAMING_GODOT_RESULT_VERIFIED probes={len(probes)} passed={passed} engine=4.7.1 production_index=false runtime_promotion=false")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--emit-fixture-root", type=Path)
    parser.add_argument("--emit-probe-root", type=Path)
    parser.add_argument("--fixture-resource-root")
    parser.add_argument("--verify-probe-root", type=Path)
    parser.add_argument("--godot-result-root", type=Path)
    parser.add_argument("--measurement-root", type=Path)
    args = parser.parse_args()
    run_guardrails(args.emit_fixture_root, args.emit_probe_root, args.fixture_resource_root)
    if args.verify_probe_root is not None or args.godot_result_root is not None:
        if args.verify_probe_root is None or args.godot_result_root is None:
            raise SystemExit("--verify-probe-root and --godot-result-root must be supplied together")
        verify_results(args.verify_probe_root, args.godot_result_root, args.measurement_root)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
