from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]
MEASURE = PROJECT / "tools/city_machine/measure_road_registered_cell_overlap.py"
LOCK = PROJECT / "data/qa/city_machine/road_registered_cell_overlap_measurement.json"
ROAD_INDEX = PROJECT / "data/runtime/road_destination_runtime_index.json"
CURRENT_SOURCE_SHA256 = "899bc73ee0eea3623d7cc45455a542c1704039ef0239c13c33b3c74b4a241398"
CURRENT_CATALOG_SHA256 = "7290b8272623e0cd5905224c8696d74a3015b1db9aab00ef19d1cf7676dea59f"
EXPECTED_BBOX = [
    147023.79522791933,
    168637.98314926197,
    148125.81622791933,
    170433.92214926198,
]


def run_measure(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(MEASURE), *args],
        cwd=PROJECT,
        text=True,
        capture_output=True,
        check=False,
    )


def test_measurement_is_source_only_and_deterministic(tmp_path: Path) -> None:
    output = tmp_path / "measurement.json"
    result = run_measure("--output", str(output))
    assert result.returncode == 0, result.stdout + result.stderr
    payload = json.loads(output.read_text(encoding="utf-8"))
    assert payload["schema"] == "grand-bruxelles-road-registered-cell-overlap-measurement-v2"
    assert payload["road_runtime_index"] == "data/runtime/road_destination_runtime_index.json"
    assert payload["road_runtime_index_format"] == "grand-bruxelles-road-runtime-index-v1"
    assert payload["road_runtime_catalog_sha256"] == CURRENT_CATALOG_SHA256
    assert payload["road_source_sha256"] == CURRENT_SOURCE_SHA256
    assert payload["road_source_license"] == "ODbL-1.0"
    assert payload["cell_crs"] == "EPSG:31370"
    assert payload["registered_cell_count"] == 1
    assert payload["road_count"] == 140
    assert payload["road_point_count"] == 754
    assert payload["road_lambert72_bbox"] == EXPECTED_BBOX
    assert payload["overlapping_road_count"] == 0
    assert payload["overlaps"] == []
    assert len(payload["semantic_sha256"]) == 64
    assert payload["road_cell_mapping_authorized"] is False
    assert payload["runtime_mount_authorized"] is False
    assert payload["rendered_geometry_authorized"] is False
    assert payload["collision_authorized"] is False
    assert payload["safe_spawn_authorized"] is False
    assert payload["jouable_promotion_authorized"] is False


def test_measurement_matches_persisted_lock_byte_for_byte(tmp_path: Path) -> None:
    output = tmp_path / "measurement.json"
    result = run_measure("--output", str(output))
    assert result.returncode == 0, result.stdout + result.stderr
    assert LOCK.is_file()
    assert output.read_bytes() == LOCK.read_bytes()


def test_measurement_rejects_source_digest_drift(tmp_path: Path) -> None:
    road = json.loads((PROJECT / "data/osm/vertical_slice_01.game.json").read_text(encoding="utf-8"))
    road["roads"][0]["name"] = "tampered"
    modified = tmp_path / "roads.json"
    modified.write_text(json.dumps(road, separators=(",", ":")), encoding="utf-8")
    result = run_measure("--road-source", str(modified), "--output", str(tmp_path / "measurement.json"))
    assert result.returncode == 2, result.stdout + result.stderr
    assert "road source SHA-256 mismatch" in result.stdout


def test_measurement_rejects_open_runtime_index_authorization(tmp_path: Path) -> None:
    index = json.loads(ROAD_INDEX.read_text(encoding="utf-8"))
    index["authorization"]["safe_spawn_authorized"] = True
    modified = tmp_path / "road-index.json"
    modified.write_text(json.dumps(index), encoding="utf-8")
    result = run_measure("--road-index", str(modified), "--output", str(tmp_path / "measurement.json"))
    assert result.returncode == 2, result.stdout + result.stderr
    assert "runtime road index authorization rail opened" in result.stdout


def test_measurement_never_authorizes_crosswalk(tmp_path: Path) -> None:
    output = tmp_path / "measurement.json"
    result = run_measure("--output", str(output))
    assert result.returncode == 0, result.stdout + result.stderr
    payload = json.loads(output.read_text(encoding="utf-8"))
    for key in (
        "road_cell_mapping_authorized",
        "runtime_mount_authorized",
        "rendered_geometry_authorized",
        "collision_authorized",
        "safe_spawn_authorized",
        "jouable_promotion_authorized",
    ):
        assert payload[key] is False, key
