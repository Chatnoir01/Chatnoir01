from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]
MEASURE = PROJECT / "tools/city_machine/measure_road_registered_cell_overlap.py"


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
    assert payload["schema"] == "grand-bruxelles-road-registered-cell-overlap-measurement-v1"
    assert payload["road_source_sha256"] == "a96123a6098c2a94dcef2622b6ea099c831f426e1ebfeb28a2edda74675c2493"
    assert payload["road_source_license"] == "ODbL-1.0"
    assert payload["cell_crs"] == "EPSG:31370"
    assert payload["registered_cell_count"] >= 1
    assert payload["road_count"] == 140
    assert payload["road_cell_mapping_authorized"] is False
    assert payload["runtime_mount_authorized"] is False
    assert payload["jouable_promotion_authorized"] is False
    assert len(payload["semantic_sha256"]) == 64


def test_measurement_rejects_source_digest_drift(tmp_path: Path) -> None:
    road = json.loads((PROJECT / "data/osm/vertical_slice_01.game.json").read_text(encoding="utf-8"))
    road["roads"][0]["name"] = "tampered"
    modified = tmp_path / "roads.json"
    modified.write_text(json.dumps(road, separators=(",", ":")), encoding="utf-8")
    result = run_measure("--road-source", str(modified), "--output", str(tmp_path / "measurement.json"))
    assert result.returncode == 2, result.stdout + result.stderr
    assert "road source SHA-256 mismatch" in result.stdout


def test_measurement_never_authorizes_crosswalk(tmp_path: Path) -> None:
    output = tmp_path / "measurement.json"
    result = run_measure("--output", str(output))
    assert result.returncode == 0, result.stdout + result.stderr
    payload = json.loads(output.read_text(encoding="utf-8"))
    assert payload["road_cell_mapping_authorized"] is False
    assert payload["rendered_geometry_authorized"] is False
    assert payload["collision_authorized"] is False
    assert payload["safe_spawn_authorized"] is False
