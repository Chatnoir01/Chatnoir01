from __future__ import annotations

import json

import pytest

from tools.city_machine import validate_spatial_crosswalk_origin_evidence as validator


@pytest.mark.parametrize(
    ("section", "shadow_key", "expected_message"),
    [
        ("coordinate_contract", "shadow_origin_easting_m", "Midi coordinate_contract schema drift"),
        ("road_frame_bridge", "shadow_road_source_sha256", "Midi road_frame_bridge schema drift"),
    ],
)
def test_primary_origin_evidence_validator_rejects_shadow_midi_bridge_fields(
    tmp_path, monkeypatch, section: str, shadow_key: str, expected_message: str
):
    midi = json.loads(validator.MIDI_CANDIDATE_PATH.read_text(encoding="utf-8"))
    midi[section][shadow_key] = "shadow"

    candidate = tmp_path / "midi-onboarding-candidate.json"
    candidate.write_text(json.dumps(midi), encoding="utf-8")
    monkeypatch.setattr(validator, "MIDI_CANDIDATE_PATH", candidate)

    with pytest.raises(ValueError, match=expected_message):
        validator.validate()
