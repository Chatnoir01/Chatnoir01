from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]
VALIDATE = PROJECT / "tools/city_machine/validate_midi_runtime_index_frame.py"
MEASURE = PROJECT / "tools/city_machine/measure_runtime_index_road_registered_cell_overlap.py"
ROAD_SOURCE = PROJECT / "data/osm/vertical_slice_01.game.json"


def run(path: Path, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run([sys.executable, str(path), *args], cwd=PROJECT, text=True, capture_output=True, check=False)


def test_runtime_index_bound_frame_is_green_and_fail_closed() -> None:
    result = run(VALIDATE)
    assert result.returncode == 0, result.stdout + result.stderr
    payload = json.loads(result.stdout.split("\nMIDI_RUNTIME_INDEX_FRAME_GREEN")[0])
    assert payload["runtime_index_bound"] is True
    assert payload["raw_road_count"] == 140
    assert payload["indexed_road_count"] == 139
    assert payload["rejected_drivable_road_count"] == 1
    assert payload["road_source_sha256"] == "899bc73ee0eea3623d7cc45455a542c1704039ef0239c13c33b3c74b4a241398"
    assert payload["road_cell_mapping_authorized"] is False
    assert payload["jouable_promotion_authorized"] is False


def test_runtime_index_eligibility_matches_catalog_rule() -> None:
    source = json.loads(ROAD_SOURCE.read_text(encoding="utf-8"))
    rejected = [
        road for road in source["roads"]
        if road.get("drivable") is True and not str(road.get("name", "")).strip()
    ]
    assert len(rejected) == 1
    assert rejected[0]["osm_id"] == 1094016546
    assert len(rejected[0]["points"]) >= 2


def test_runtime_index_bound_frame_stays_non_activatable() -> None:
    result = run(VALIDATE, "--require-activatable")
    assert result.returncode == 3, result.stdout + result.stderr
    assert "ROAD_CELL_CROSSWALK_NOT_REVIEWED" in result.stdout


def test_current_overlap_measurement_is_deterministic(tmp_path: Path) -> None:
    first = tmp_path / "a.json"
    second = tmp_path / "b.json"
    first_run = run(MEASURE, "--output", str(first))
    second_run = run(MEASURE, "--output", str(second))
    assert first_run.returncode == second_run.returncode == 0, first_run.stdout + first_run.stderr + second_run.stdout + second_run.stderr
    assert first.read_bytes() == second.read_bytes()
    payload = json.loads(first.read_text(encoding="utf-8"))
    assert payload["schema"] == "grand-bruxelles-road-registered-cell-overlap-measurement-v2"
    assert payload["raw_road_count"] == 140
    assert payload["rejected_drivable_road_count"] == 1
    assert payload["road_count"] == 139
    assert payload["runtime_descriptor_road_count"] == 139
    assert payload["road_point_count"] == 752
    assert payload["road_runtime_catalog_sha256"] == "7290b8272623e0cd5905224c8696d74a3015b1db9aab00ef19d1cf7676dea59f"
    assert payload["road_cell_mapping_authorized"] is False
    assert payload["runtime_mount_authorized"] is False
    assert payload["rendered_geometry_authorized"] is False
    assert payload["collision_authorized"] is False
    assert payload["safe_spawn_authorized"] is False
    assert payload["jouable_promotion_authorized"] is False
