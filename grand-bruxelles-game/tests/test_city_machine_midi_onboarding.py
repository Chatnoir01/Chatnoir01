from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]
VALIDATOR = PROJECT / "tools/city_machine/validate_midi_onboarding_candidate.py"
CANDIDATE = PROJECT / "data/qa/city_machine/midi_onboarding_candidate.json"


def run_validator(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(VALIDATOR), *args],
        cwd=PROJECT,
        text=True,
        capture_output=True,
        check=False,
    )


def test_midi_normalized_layers_are_global_and_legacy_is_forbidden() -> None:
    result = run_validator()
    assert result.returncode == 0, result.stdout + result.stderr
    assert '"coordinate_frame_proven": true' in result.stdout
    assert '"runtime_translation_m": [' in result.stdout
    assert '"legacy_runtime_forbidden": true' in result.stdout
    assert "MIDI_ONBOARDING_CANDIDATE_OK" in result.stdout


def test_osm_road_frame_is_bridged_to_the_same_canonical_world_frame() -> None:
    result = run_validator()
    assert result.returncode == 0, result.stdout + result.stderr
    assert '"road_frame_bridge_proven": true' in result.stdout
    assert '"road_source_sha256": "a96123a6098c2a94dcef2622b6ea099c831f426e1ebfeb28a2edda74675c2493"' in result.stdout
    assert '"road_cell_mapping_authorized": false' in result.stdout
    assert '"lambert72_formula": "E=origin_easting_m+x;N=origin_northing_m-z"' in result.stdout


def test_midi_activation_stays_fail_closed_while_blockers_exist() -> None:
    result = run_validator("--require-activatable")
    assert result.returncode == 3, result.stdout + result.stderr
    assert "RUNTIME_GEOMETRY_MOUNT_NOT_REGISTERED" in result.stdout
    assert "ROAD_CELL_CROSSWALK_NOT_REVIEWED" in result.stdout


def test_nonzero_runtime_translation_is_rejected(tmp_path: Path) -> None:
    candidate = json.loads(CANDIDATE.read_text(encoding="utf-8"))
    candidate["coordinate_contract"]["runtime_translation_m"] = [532.0, 0.0, 361.0]
    modified = tmp_path / "candidate.json"
    modified.write_text(json.dumps(candidate), encoding="utf-8")
    result = run_validator("--candidate", str(modified))
    assert result.returncode == 2, result.stdout + result.stderr
    assert "zero runtime translation" in result.stdout


def test_legacy_aggregate_cannot_be_reintroduced(tmp_path: Path) -> None:
    candidate = json.loads(CANDIDATE.read_text(encoding="utf-8"))
    candidate["normalized_runtime_inputs"]["buildings"] = "data/urbis/midi/midi_runtime.game.json"
    modified = tmp_path / "candidate.json"
    modified.write_text(json.dumps(candidate), encoding="utf-8")
    result = run_validator("--candidate", str(modified))
    assert result.returncode == 2, result.stdout + result.stderr
    assert "legacy Midi aggregate" in result.stdout


def test_road_source_digest_drift_is_rejected(tmp_path: Path) -> None:
    candidate = json.loads(CANDIDATE.read_text(encoding="utf-8"))
    candidate["road_frame_bridge"]["road_source_sha256"] = "0" * 64
    modified = tmp_path / "candidate.json"
    modified.write_text(json.dumps(candidate), encoding="utf-8")
    result = run_validator("--candidate", str(modified))
    assert result.returncode == 2, result.stdout + result.stderr
    assert "road source SHA-256 mismatch" in result.stdout


def test_world_anchor_drift_is_rejected(tmp_path: Path) -> None:
    candidate = json.loads(CANDIDATE.read_text(encoding="utf-8"))
    candidate["road_frame_bridge"]["expected_midi_world_xz"] = [-667.5, 627.84]
    modified = tmp_path / "candidate.json"
    modified.write_text(json.dumps(candidate), encoding="utf-8")
    result = run_validator("--candidate", str(modified))
    assert result.returncode == 2, result.stdout + result.stderr
    assert "Midi world anchor does not match official world-frame evidence" in result.stdout


def test_bridge_cannot_authorize_road_cell_mapping(tmp_path: Path) -> None:
    candidate = json.loads(CANDIDATE.read_text(encoding="utf-8"))
    candidate["road_frame_bridge"]["road_cell_mapping_authorized"] = True
    modified = tmp_path / "candidate.json"
    modified.write_text(json.dumps(candidate), encoding="utf-8")
    result = run_validator("--candidate", str(modified))
    assert result.returncode == 2, result.stdout + result.stderr
    assert "road-cell mapping must remain review-gated" in result.stdout
