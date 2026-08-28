#!/usr/bin/env python3
from __future__ import annotations

import json
import tempfile
from pathlib import Path

from build_road_destination_readiness_catalog import build_catalog


def write(path: Path, payload: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def fixture(root: Path) -> tuple[Path, Path, Path, Path, Path]:
    roads = root / "data/osm/roads.json"
    runtime = root / "data/runtime/index.json"
    cells = root / "data/provenance/cells.json"
    crosswalk = root / "data/provenance/crosswalk.json"
    manifests = root / "data/cell_manifests"

    write(roads, {
        "format": "grand-bruxelles-osm-v1",
        "source": "OpenStreetMap contributors via Overpass API",
        "license": "ODbL-1.0",
        "roads": [
            {"osm_id": 11, "name": "Road Eleven", "class": "residential", "drivable": True, "points": [[1.0, 2.0], [3.0, 4.0]]},
            {"osm_id": 22, "name": "Road Twenty Two", "class": "service", "drivable": True, "points": [[5.0, 6.0], [7.0, 8.0]]},
        ],
    })
    import hashlib
    road_sha = hashlib.sha256(roads.read_bytes()).hexdigest()
    write(runtime, {
        "format": "grand-bruxelles-road-runtime-index-v1",
        "catalog_sha256": "a" * 64,
        "source_lookup_only": True,
        "authorization": {
            "source_lookup_only": True,
            "render_authorized": False,
            "collision_authorized": False,
            "runtime_mount_authorized": False,
            "safe_spawn_authorized": False,
            "jouable_authorized": False,
        },
        "documents": [{"path": "data/osm/roads.json", "sha256": road_sha, "road_ids": [11, 22]}],
    })
    write(manifests / "cell-a.json", {
        "cell_id": "cell-a",
        "bbox": [100.0, 200.0, 600.0, 700.0],
        "crs": "EPSG:31370",
        "maturity": {"state": "data_ready", "gates": {"runtime_geometry": False, "streaming": False, "terrain": False, "heights": False, "collisions": False, "photo_match": False, "performance": False}},
        "provenance": {"primary": "UrbIS WFS / Paradigm", "license": "CC0-1.0", "municipality_niscode": "21004", "municipality_id": "https://example.test/municipality/21004", "municipality_coverage_ratio": 1.0},
    })
    manifest_sha = hashlib.sha256((manifests / "cell-a.json").read_bytes()).hexdigest()
    write(cells, {
        "schema": "grand-bruxelles-registered-cell-manifest-index-v1",
        "semantic_sha256": "b" * 64,
        "registered_cell_count": 1,
        "entries": [{
            "cell_id": "cell-a", "bbox": [100.0, 200.0, 600.0, 700.0], "crs": "EPSG:31370",
            "evidence_only": True, "maturity_state": "data_ready", "manifest_path": "data/cell_manifests/cell-a.json",
            "manifest_sha256": manifest_sha, "runtime_mount_authorized": False, "rendered_geometry_authorized": False,
            "collision_authorized": False, "safe_spawn_authorized": False, "jouable_promotion_authorized": False,
        }],
        "runtime_directory_scan_authorized": False, "road_crosswalk_authorized": False,
        "runtime_mount_authorized": False, "rendered_geometry_authorized": False, "collision_authorized": False,
        "safe_spawn_authorized": False, "jouable_promotion_authorized": False,
    })
    write(crosswalk, {
        "schema": "grand-bruxelles-road-registered-cell-crosswalk-v1",
        "semantic_sha256": "c" * 64,
        "registered_cell_index_semantic_sha256": "b" * 64,
        "road_semantic_sha256": "d" * 64,
        "mapped_road_count": 1,
        "mapped_cell_count": 1,
        "rows": [{
            "road_osm_id": 11, "cell_id": "cell-a", "grid_cell_id": "E100_N200", "mapping_evidence_only": True,
            "road_cell_mapping_authorized": False, "runtime_mount_authorized": False, "rendered_geometry_authorized": False,
            "collision_authorized": False, "safe_spawn_authorized": False, "jouable_promotion_authorized": False,
        }],
        "road_cell_mapping_authorized": False, "runtime_directory_scan_authorized": False,
        "runtime_mount_authorized": False, "rendered_geometry_authorized": False, "collision_authorized": False,
        "safe_spawn_authorized": False, "jouable_promotion_authorized": False,
    })
    return roads, runtime, cells, crosswalk, manifests


def test_green() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        roads, runtime, cells, crosswalk, manifests = fixture(root)
        catalog = build_catalog(root, runtime, cells, crosswalk)
        assert catalog["schema"] == "grand-bruxelles-road-destination-readiness-catalog-v1"
        assert catalog["destination_count"] == 1
        row = catalog["destinations"][0]
        assert row["destination_id"] == "road-11"
        assert row["road_osm_id"] == 11
        assert row["road_name"] == "Road Eleven"
        assert row["road_class"] == "residential"
        assert row["source_path"] == "data/osm/roads.json"
        assert row["cell_id"] == "cell-a"
        assert row["cell_bbox"] == [100.0, 200.0, 600.0, 700.0]
        assert row["municipality_niscodes"] == ["21004"]
        assert row["readiness"] == "REGISTERED_NOT_RENDERED"
        assert row["render_authorized"] is False
        assert row["collision_authorized"] is False
        assert row["runtime_mount_authorized"] is False
        assert row["safe_spawn_authorized"] is False
        assert row["jouable_authorized"] is False
        assert "migration_state" not in catalog


def test_corrected_frame_wrapper_is_derived_from_locked_contract() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        roads, runtime, cells, crosswalk, manifests = fixture(root)
        crosswalk_payload = json.loads(crosswalk.read_text())
        crosswalk_payload["destination_readiness"] = "CORRECTED_FRAME_ROAD_CELL_CROSSWALK_EVIDENCE_ONLY"
        crosswalk_payload["corrected_frame_source_sha256"] = json.loads(runtime.read_text())["documents"][0]["sha256"]
        crosswalk_payload["excluded_multicell_road_ids"] = [22]
        write(crosswalk, crosswalk_payload)

        write(root / "data/qa/corrected_frame_destination_production_apply.contract.json", {
            "schema": "grand-bruxelles-corrected-frame-destination-production-apply-v1",
            "status": "LOCKED_STAGED_PAIR_EVIDENCE_ONLY_V2",
            "source": {
                "road_source_sha256": crosswalk_payload["corrected_frame_source_sha256"],
                "readiness_semantic_sha256": "e" * 64,
            },
            "expected": {
                "mapping_count": 1,
                "destination_count": 1,
                "mapped_cell_count": 1,
                "multicell_hold_ids": [22],
            },
            "authorization": {
                "production_write_authorized": False,
                "production_frame_update_authorized": False,
                "road_cell_mapping_authorized": False,
                "runtime_probe_authorized": False,
                "runtime_mount_authorized": False,
                "render_authorized": False,
                "collision_authorized": False,
                "safe_spawn_authorized": False,
                "jouable_authorized": False,
            },
        })
        catalog = build_catalog(root, runtime, cells, crosswalk)
        assert catalog["corrected_frame_source_sha256"] == crosswalk_payload["corrected_frame_source_sha256"]
        assert catalog["corrected_frame_candidate_semantic_sha256"] == "e" * 64
        assert catalog["migration_state"] == "CORRECTED_FRAME_REGISTERED_NOT_RENDERED"

        contract = json.loads((root / "data/qa/corrected_frame_destination_production_apply.contract.json").read_text())
        contract["authorization"]["runtime_probe_authorized"] = True
        write(root / "data/qa/corrected_frame_destination_production_apply.contract.json", contract)
        try:
            build_catalog(root, runtime, cells, crosswalk)
        except RuntimeError as exc:
            assert "authorization" in str(exc).lower()
        else:
            raise AssertionError("corrected-frame authorization drift must fail closed")


def test_reject_runtime_authorization() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        roads, runtime, cells, crosswalk, manifests = fixture(root)
        payload = json.loads(runtime.read_text())
        payload["authorization"]["render_authorized"] = True
        write(runtime, payload)
        try:
            build_catalog(root, runtime, cells, crosswalk)
        except RuntimeError as exc:
            assert "authorization" in str(exc).lower()
        else:
            raise AssertionError("runtime authorization drift must fail closed")


def test_runtime_probe_contract() -> None:
    repo_root = Path(__file__).resolve().parents[2]
    probe = repo_root / "game/tests/road_destination_readiness_runtime_probe.gd"
    if not probe.is_file():
        raise AssertionError("runtime readiness probe missing")
    text = probe.read_text(encoding="utf-8")
    required = [
        'const CATALOG_PATH := "res://data/provenance/brussels_road_destination_readiness_catalog.json"',
        'const RESOLVER_SCRIPT := preload("res://game/scripts/automatic_road_direct_spawn.gd")',
        'resolver.apply_to_player(player, osm_id)',
        '"rendered": rendered',
        '"resolver_applied": applied',
        '"ground_ready": ground_ready',
        '"source_sightline_clear": sightline_clear',
        '"playability_claimed": false',
        '"jouable_authorized": false',
        'ROAD_DESTINATION_RUNTIME_PROBE_OK',
    ]
    for marker in required:
        assert marker in text, marker
    forbidden = [
        'set("jouable_authorized", true)',
        'set("safe_spawn_authorized", true)',
        'set("render_authorized", true)',
    ]
    for marker in forbidden:
        assert marker not in text, marker


def main() -> None:
    test_green()
    test_corrected_frame_wrapper_is_derived_from_locked_contract()
    test_reject_runtime_authorization()
    test_runtime_probe_contract()
    print("ROAD_DESTINATION_READINESS_CATALOG_TESTS_GREEN")


if __name__ == "__main__":
    main()
