import json
from pathlib import Path

STATUS = Path("grand-bruxelles-game/assets/characters/civilians/civ1/locomotion_source_status.json")
EXPECTED_BASE = "0d8a0cff0f7362aee359c0ea25ec3ba988640ed5"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"CIV1_LOCOMOTION_SOURCE_AUDIT_FAIL: {message}")


def main() -> None:
    data = json.loads(STATUS.read_text(encoding="utf-8"))
    require(data["format"] == "grand-bruxelles-civ1-locomotion-source-audit-v2", "format drift")
    require(data["base_main_sha"] == EXPECTED_BASE, "base main drift")
    require(data["production_authorized"] is False, "production must remain closed")
    require(data["retarget_authorized"] is False, "retarget must remain closed")
    require(data["activation_ready"] is False, "activation must remain closed")
    require(data["visual_approval_claimed"] is False, "visual approval must remain false")
    require(data["player_character_reuse_forbidden"] is True, "player reuse must stay forbidden")
    require(data["mixamo_forbidden"] is True, "Mixamo must stay forbidden")
    require(data["selected_source"] == "", "no source may be selected yet")
    require(data["blocker"] == "no_independently_licensed_exact_idle_walk_run_trio_verified_for_civ1", "blocker drift")

    by_id = {row["id"]: row for row in data["sources"]}
    require(set(by_id) == {
        "quaternius_universal_animation_library_standard_1_0",
        "kaykit_character_animations_1_2",
        "quaternius_ik_rigged_1_0",
    }, "source set drift")

    q = by_id["quaternius_universal_animation_library_standard_1_0"]
    require(q["license"] == "CC0-1.0", "Quaternius license drift")
    require(q["archive_sha256"] == "18ff1a7215f4852b320203e8aaf02a1578b5c8eef9027fbaedfcedc7b85a3ac2", "Quaternius archive drift")
    require(q["archive_size_bytes"] == 14541205, "Quaternius size drift")
    require(q["godot_4_7_1_preflight_demonstrated"] is True, "Quaternius Godot proof lost")
    require(q["source_animation_count"] == 46, "Quaternius animation count drift")
    require(q["exact_walk_candidates"] == ["Walk", "Walk_Formal"], "walk catalog drift")
    require(q["exact_run_candidates"] == [], "exact run must remain absent")
    require(q["review_only_run_candidates"] == ["Jog_Fwd", "Sprint"], "run review catalog drift")
    require(q["state"] == "BLOCKED_NO_EXACT_RUN", "Quaternius state drift")
    require(q["direct_adoption_allowed"] is False, "Quaternius direct adoption must remain blocked")
    require(q["semantic_alias_auto_promotion_allowed"] is False, "semantic alias autopromotion forbidden")

    kay = by_id["kaykit_character_animations_1_2"]
    require(kay["state"] == "REJECTED_NON_HUMANOID_FOR_CIV1_RETARGET", "KayKit rejection drift")
    require(kay["skeleton_bones"] == ["Body", "Head", "armLeft", "handSlotLeft", "armRight", "handSlotRight"], "KayKit skeleton drift")
    require(kay["direct_adoption_allowed"] is False, "KayKit must stay rejected")

    ik = by_id["quaternius_ik_rigged_1_0"]
    require(ik["license"] == "CC0-1.0", "IK candidate license drift")
    require(ik["declared_godot_compatibility"] == "4.6+", "IK declared compatibility drift")
    require(ik["upstream_commit_from_asset_download"] == "5c4dae72e49ad4e5959571e00a25d3d872cacba5", "IK upstream commit drift")
    require(ik["archive_sha256"] == "f868b316facd04d7686784b254f6f1bbcd7e14bc06f3ec70f92a3144dc462767", "IK archive SHA drift")
    require(ik["archive_size_bytes"] == 38687957, "IK archive size drift")
    require(ik["archive_cc0_text_matches"] == ["quaternius_ik_rigged_with_animations/LICENSE", "quaternius_ik_rigged_with_animations/README.md"], "IK archive CC0 evidence drift")
    require(ik["godot_4_7_1_demonstrated"] is True, "IK Godot 4.7.1 proof lost")
    require(ik["measured_loaded_scene_count"] == 5, "IK loaded scene count drift")
    require(ik["measured_load_failure_count"] == 1, "IK load failure count drift")
    require(ik["measured_skeleton_count"] == 5, "IK skeleton count drift")
    require(ik["measured_unique_bone_count"] == 65, "IK unique bone count drift")
    require(ik["measured_animation_player_count"] == 3, "IK AnimationPlayer count drift")
    require(ik["measured_mesh_instance_count"] == 15, "IK mesh count drift")
    require(ik["measured_skinned_mesh_count"] == 15, "IK skinned mesh count drift")
    require(ik["source_animation_count"] == 45, "IK animation catalog drift")
    require(ik["exact_idle_candidates"] == ["UAL1_Standard/Idle"], "IK exact idle drift")
    require(ik["exact_walk_candidates"] == ["UAL1_Standard/Walk"], "IK exact walk drift")
    require(ik["exact_run_candidates"] == [], "IK exact run must remain absent")
    require(ik["review_only_run_candidates"] == ["UAL1_Standard/Jog_Fwd", "UAL1_Standard/Sprint"], "IK review-only run drift")
    require(ik["exact_idle_walk_run_catalog_verified"] is True, "IK catalog characterization must stay proven")
    require(ik["state"] == "BLOCKED_NO_EXACT_RUN", "IK measured rejection drift")
    require(ik["characterization_workflow_run_id"] == 33353446737, "IK run identity drift")
    require(ik["characterization_artifact_id"] == 9744361128, "IK artifact identity drift")
    require(ik["characterization_artifact_zip_sha256"] == "711095546e1d9ebd024b03fbe7b33a852e918612667924e902d50ff317ab9b98", "IK artifact digest drift")
    require(ik["civ1_52_bone_retarget_verified"] is False, "IK CIV-1 retarget must remain unproven")
    require(ik["grounding_verified"] is False, "IK grounding must remain unproven")
    require(ik["foot_slide_verified"] is False, "IK foot-slide must remain unproven")
    require(ik["direct_adoption_allowed"] is False, "IK direct adoption must remain blocked")
    require(ik["semantic_alias_auto_promotion_allowed"] is False, "IK semantic alias autopromotion forbidden")

    print("CIV1_LOCOMOTION_SOURCE_AUDIT_OK")


if __name__ == "__main__":
    main()
