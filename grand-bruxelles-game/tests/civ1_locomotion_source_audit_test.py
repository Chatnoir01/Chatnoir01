import json
from pathlib import Path

STATUS = Path("grand-bruxelles-game/assets/characters/civilians/civ1/locomotion_source_status.json")
EXPECTED_BASE = "054ce0b2c7a31a5b3a6bc222fe15d7f5b98c6dc0"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"CIV1_LOCOMOTION_SOURCE_AUDIT_FAIL: {message}")


def main() -> None:
    data = json.loads(STATUS.read_text(encoding="utf-8"))
    require(data["format"] == "grand-bruxelles-civ1-locomotion-source-audit-v3", "format drift")
    require(data["base_main_sha"] == EXPECTED_BASE, "base main drift")
    require(data["production_authorized"] is False, "production must remain closed")
    require(data["retarget_authorized"] is False, "retarget must remain closed")
    require(data["activation_ready"] is False, "activation must remain closed")
    require(data["visual_approval_claimed"] is False, "visual approval must remain false")
    require(data["player_character_reuse_forbidden"] is True, "player reuse must stay forbidden")
    require(data["mixamo_forbidden"] is True, "Mixamo must stay forbidden")
    require(data["selected_source"] == "", "no source may be selected yet")
    require(data["selected_run_alias"] == "", "no run alias may be selected yet")
    require(data["blocker"] == "run_semantic_candidate_requires_kinematic_foot_contact_review_before_civ1_retarget", "blocker drift")

    by_id = {row["id"]: row for row in data["sources"]}
    require(set(by_id) == {
        "quaternius_universal_animation_library_standard_1_0",
        "kaykit_character_animations_1_2",
        "quaternius_ik_rigged_1_0",
    }, "source set drift")

    q = by_id["quaternius_universal_animation_library_standard_1_0"]
    require(q["license"] == "CC0-1.0", "Quaternius license drift")
    require(q["archive_sha256"] == "18ff1a7215f4852b320203e8aaf02a1578b5c8eef9027fbaedfcedc7b85a3ac2", "Quaternius archive drift")
    require(q["exact_run_candidates"] == [], "exact run must remain absent")
    require(q["semantic_alias_auto_promotion_allowed"] is False, "semantic alias autopromotion forbidden")

    kay = by_id["kaykit_character_animations_1_2"]
    require(kay["state"] == "REJECTED_NON_HUMANOID_FOR_CIV1_RETARGET", "KayKit rejection drift")
    require(kay["direct_adoption_allowed"] is False, "KayKit must stay rejected")

    ik = by_id["quaternius_ik_rigged_1_0"]
    require(ik["license"] == "CC0-1.0", "IK candidate license drift")
    require(ik["archive_sha256"] == "f868b316facd04d7686784b254f6f1bbcd7e14bc06f3ec70f92a3144dc462767", "IK archive SHA drift")
    require(ik["archive_size_bytes"] == 38687957, "IK archive size drift")
    require(ik["godot_4_7_1_demonstrated"] is True, "IK Godot 4.7.1 proof lost")
    require(ik["source_animation_count"] == 45, "IK animation catalog drift")
    require(ik["exact_idle_candidates"] == ["UAL1_Standard/Idle"], "IK exact idle drift")
    require(ik["exact_walk_candidates"] == ["UAL1_Standard/Walk"], "IK exact walk drift")
    require(ik["exact_run_candidates"] == [], "IK exact run must remain absent")
    require(ik["review_only_run_candidates"] == ["UAL1_Standard/Jog_Fwd", "UAL1_Standard/Sprint"], "IK review-only run drift")
    require(ik["state"] == "BLOCKED_NO_EXACT_RUN", "IK measured rejection drift")
    require(ik["characterization_workflow_run_id"] == 33355673996, "fresh IK run identity drift")
    require(ik["characterization_artifact_id"] == 9745046876, "fresh IK artifact identity drift")
    require(ik["characterization_artifact_zip_sha256"] == "aa39d527aa326b39583a99b2d47601bea5d659fadfc3ff283c3481414a60098f", "fresh IK artifact digest drift")

    review = ik["semantic_review"]
    require(review["format"] == "grand-bruxelles-civ1-run-semantic-review-v1", "semantic review format drift")
    require(review["godot_version"] == "4.7.1 stable", "semantic review Godot drift")
    walk = review["walk_reference"]
    jog = review["jog_fwd"]
    sprint = review["sprint"]
    require(walk == {"name": "UAL1_Standard/Walk", "length_seconds": 1.33333337306976, "loop_mode": 1, "track_count": 59}, "walk metrics drift")
    require(jog == {"name": "UAL1_Standard/Jog_Fwd", "length_seconds": 0.933333337306976, "loop_mode": 1, "track_count": 59}, "jog metrics drift")
    require(sprint == {"name": "UAL1_Standard/Sprint", "length_seconds": 0.666666686534882, "loop_mode": 1, "track_count": 59}, "sprint metrics drift")
    require(abs(review["duration_ratio_jog_to_walk"] - 0.6999999786913403) < 1e-12, "jog/walk duration ratio drift")
    require(abs(review["duration_ratio_sprint_to_walk"] - 0.5) < 1e-12, "sprint/walk duration ratio drift")
    require(review["structural_metrics_match"] is True, "candidate structural parity drift")
    require(review["semantic_selection"] == "", "duration-only evidence must not select a run alias")
    require(review["selection_state"] == "BLOCKED_NEEDS_KINEMATIC_FOOT_CONTACT_REVIEW", "semantic review state drift")
    require(set(review["required_next_measurements"]) == {
        "root_motion_or_hips_displacement",
        "foot_contact_timing",
        "contact_foot_slide_speed",
        "civ1_52_bone_retarget_integrity",
    }, "required kinematic measurements drift")

    require(ik["civ1_52_bone_retarget_verified"] is False, "IK CIV-1 retarget must remain unproven")
    require(ik["grounding_verified"] is False, "IK grounding must remain unproven")
    require(ik["foot_slide_verified"] is False, "IK foot-slide must remain unproven")
    require(ik["direct_adoption_allowed"] is False, "IK direct adoption must remain blocked")
    require(ik["semantic_alias_auto_promotion_allowed"] is False, "IK semantic alias autopromotion forbidden")

    print("CIV1_LOCOMOTION_SOURCE_AUDIT_OK: run_semantic_review=measured duration_only_selection=blocked")


if __name__ == "__main__":
    main()
