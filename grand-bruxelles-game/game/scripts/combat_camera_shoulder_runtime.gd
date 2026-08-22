extends Node

# Late combat framing owner. GtaScaleCameraRuntime remains authoritative for
# distance/FOV/special presentations; this layer only increases the third-person
# shoulder offset while armed so the weapon and both hands are readable.

const ARMED_OFFSET := Vector3(0.68, 0.14, 0.0)
const AIM_OFFSET := Vector3(0.80, 0.18, 0.0)
const NORMAL_OFFSET := Vector3(0.34, 0.08, 0.0)
const MIN_THIRD_PERSON_DISTANCE_M := 0.80

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    process_priority = 1100
    set_process(true)

func _process(_delta: float) -> void:
    var scene := get_tree().current_scene
    if scene == null:
        return
    var player := scene.get_node_or_null("Player") as CharacterBody3D
    if player == null:
        return
    var spring_arm := player.get_node_or_null("CameraPivot/SpringArm3D") as SpringArm3D
    if spring_arm == null:
        return

    # Never interfere with source-backed witnesses or first-person locks.
    var owner := String(player.get_meta("gta_scale_camera_owner", ""))
    if owner == "special_presentation" or bool(player.get_meta("camera_view_locked_first_person", false)) or spring_arm.spring_length < MIN_THIRD_PERSON_DISTANCE_M:
        player.set_meta("combat_camera_shoulder_active", false)
        return

    var weapon_id := StringName(player.get_meta("combat_weapon_id", &""))
    var switching := bool(player.get_meta("combat_weapon_switching", false))
    var aiming := bool(player.get_meta("combat_weapon_aiming", false))
    var armed := weapon_id != &"" and not switching
    if aiming and armed:
        spring_arm.position = AIM_OFFSET
        player.set_meta("combat_camera_shoulder_profile", "aim")
    elif armed:
        spring_arm.position = ARMED_OFFSET
        player.set_meta("combat_camera_shoulder_profile", "carry")
    else:
        # Restore the normal third-person composition because this runtime runs
        # after the GTA camera arbiter every frame.
        spring_arm.position = NORMAL_OFFSET
        player.set_meta("combat_camera_shoulder_profile", "normal")
    player.set_meta("combat_camera_shoulder_active", armed)
    player.set_meta("combat_camera_shoulder_offset", spring_arm.position)
