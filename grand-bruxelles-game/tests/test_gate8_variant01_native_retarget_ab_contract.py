#!/usr/bin/env python3
from __future__ import annotations
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data/qa/gate8_variant01_native_retarget_ab.json"
SCRIPT = ROOT / "game/tests/gate8_variant01_native_retarget_ab_test.gd"
WORKFLOW = ROOT.parent / ".github/workflows/grand-bruxelles-gate8-variant01-native-retarget-ab.yml"


def main() -> None:
    payload = json.loads(DATA.read_text(encoding="utf-8"))
    assert payload["format"] == "grand-bruxelles-gate8-variant01-native-retarget-ab-v1"
    assert payload["candidate_variant"] == 1
    assert payload["run_candidates"] == ["Jog_Fwd", "Sprint"]
    retarget = payload["retarget"]
    assert retarget["engine"] == "RetargetModifier3D"
    assert retarget["use_global_pose"] is False
    assert retarget["position_enabled"] is False
    assert retarget["rotation_enabled"] is True
    assert retarget["scale_enabled"] is False
    assert retarget["source_bone_names_unchanged"] is True
    assert retarget["source_animation_tracks_unchanged"] is True
    rails = payload["rails"]
    assert rails["run_alias_selected"] == ""
    assert rails["production_authorized"] is False
    assert rails["activation_ready"] is False
    assert rails["adoption_ready"] is False
    assert rails["runtime_population_changed"] is False
    assert rails["visual_approval_claimed"] is False
    script = SCRIPT.read_text(encoding="utf-8")
    assert "RetargetModifier3D.new()" in script
    assert "_rename_target_to_source_namespace" in script
    assert "set_position_enabled(false)" in script
    assert "set_rotation_enabled(true)" in script
    assert "set_scale_enabled(false)" in script
    assert "_source_skeleton.set_bone_name" not in script
    workflow = WORKFLOW.read_text(encoding="utf-8")
    assert "Godot_v4.7.1-stable_linux.x86_64" in workflow
    assert "1280x720" in workflow
    print("GATE8_VARIANT01_NATIVE_RETARGET_AB_CONTRACT_OK production_authorized=false runtime_population_changed=false")


if __name__ == "__main__":
    main()
