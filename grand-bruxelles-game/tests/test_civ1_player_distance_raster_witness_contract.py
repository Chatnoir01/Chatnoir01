from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
WITNESS = HERE / "tools" / "godot_civ1_player_distance_raster_witness.gd"


def require(text: str, needle: str) -> None:
    assert needle in text, f"missing contract: {needle}"


def main() -> None:
    text = WITNESS.read_text(encoding="utf-8")
    require(text, 'const WIDTH := 1280')
    require(text, 'const HEIGHT := 720')
    require(text, 'const VERTICAL_FOV_DEG := 45.0')
    require(text, 'const PLAYER_DISTANCES_M := [2.0, 4.0, 8.0]')
    require(text, 'const TARGET_SAMPLES := [115, 116, 117, 118]')
    require(text, 'const MAIN_SCENE_PATH := "res://game/main.tscn"')
    require(text, 'const MAIN_GROUND_PATH := NodePath("Ground")')
    require(text, 'ground_copy.name="CanonicalMainGround"')
    require(text, 'camera.position=Vector3(float(distance_m),0.23+placement_y,0.0)')
    require(text, 'camera.look_at(Vector3(0.0,0.16+placement_y,0.0))')
    require(text, '"schema":"grand-bruxelles-civ1-player-distance-raster-v1"')
    require(text, '"actual_2_4_8m_rasters_present":captures.size()==TARGET_SAMPLES.size()*PLAYER_DISTANCES_M.size()')
    for claim in (
        '"perceptual_2_8m_claimed":false',
        '"planted_contact_claimed":false',
        '"animation_correction_authorized":false',
        '"runtime_authorized":false',
        '"visual_approval_claimed":false',
        '"player_view_claimed":false',
    ):
        require(text, claim)
    require(text, 'if max_pose_error>0.0001:')
    require(text, '"JETER_DYNAMIC_TECHNICAL_DRIFT"')
    require(text, 'civ1-distance-%sm-%03d.png')
    assert text.count('for distance_m in PLAYER_DISTANCES_M:') == 1
    print("CIV1_PLAYER_DISTANCE_RASTER_WITNESS_CONTRACT_OK")


if __name__ == "__main__":
    main()
