import json
from pathlib import Path

STATUS = Path("grand-bruxelles-game/assets/characters/civilians/civ1/locomotion_source_status.json")
EXPECTED_BASE = "b91ddc2b761ec0f2370556693eb983a83120a2dc"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"CIV1_LOCOMOTION_SOURCE_AUDIT_FAIL: {message}")


def main() -> None:
    data = json.loads(STATUS.read_text(encoding="utf-8"))
    require(data["format"] == "grand-bruxelles-civ1-locomotion-source-audit-v1", "format drift")
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
    require(ik["state"] == "AUDIT_REQUIRED_BEFORE_USE", "IK candidate must remain audit-only")
    require(ik["godot_4_7_1_demonstrated"] is False, "IK Godot 4.7.1 must not be claimed")
    require(ik["exact_idle_walk_run_catalog_verified"] is False, "IK locomotion catalog must not be claimed")
    require(ik["civ1_52_bone_retarget_verified"] is False, "IK CIV-1 retarget must not be claimed")
    require(ik["direct_adoption_allowed"] is False, "IK direct adoption must remain blocked")

    print("CIV1_LOCOMOTION_SOURCE_AUDIT_OK")


if __name__ == "__main__":
    main()
