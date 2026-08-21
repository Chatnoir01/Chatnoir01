extends Node

## Player presentation guard for the production Grand Bruxelles scene.
## The world remains metre-authored. This runtime only normalizes the visible player
## and remaps the existing camera presets so the player no longer dominates facades.
##
## Camera authority, from strongest to weakest:
## 1. source-backed special presentations (Atomium / Ixelles),
## 2. active combat aiming,
## 3. normal GTA-scale gameplay composition.

const TARGET_PLAYER_VISUAL_HEIGHT_M := 1.78
const PLAYER_GROUND_LOCAL_Y := -0.90

const LEGACY_VIEW_DISTANCES: Array[float] = [4.9, 2.7, 7.2, 0.12]
const TUNED_VIEW_DISTANCES: Array[float] = [5.8, 3.4, 7.8, 0.12]
const TUNED_VIEW_FOVS: Array[float] = [72.0, 74.0, 66.0, 76.0]
const VIEW_NAMES: Array[String] = ["standard", "close", "wide", "first_person"]
const VIEW_MATCH_TOLERANCE_M := 0.035

const DEFAULT_THIRD_PERSON_PITCH_DEG := -7.0
const THIRD_PERSON_CAMERA_OFFSET := Vector3(0.34, 0.08, 0.0)
const FIRST_PERSON_CAMERA_OFFSET := Vector3.ZERO
const COMBAT_AIM_FOV_DEG := 61.0

const MIN_SOURCE_VISUAL_HEIGHT_M := 0.10
const MAX_SOURCE_VISUAL_HEIGHT_M := 20.0
const MIN_NORMALIZATION_SCALE := 0.05
const MAX_NORMALIZATION_SCALE := 8.0

var _player: CharacterBody3D
var _camera_pivot: Node3D
var _spring_arm: SpringArm3D
var _camera: Camera3D
var _normalized_character_id: int = 0


func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    # Combat and presentation runtimes can touch the rig during the same frame.
    # This arbiter runs late so the final rendered camera has one deterministic
    # owner instead of several systems fighting over FOV every frame.
    process_priority = 1000
    call_deferred("_bind_production_player")


func _process(_delta: float) -> void:
    if not _binding_is_valid():
        _bind_production_player()
        return
    _apply_camera_contract()
    _normalize_authored_player_if_needed()


func _binding_is_valid() -> bool:
    return (
        is_instance_valid(_player)
        and is_instance_valid(_camera_pivot)
        and is_instance_valid(_spring_arm)
        and is_instance_valid(_camera)
    )


func _bind_production_player() -> void:
    var scene := get_tree().current_scene
    if scene == null:
        return
    var candidate := scene.get_node_or_null("Player") as CharacterBody3D
    if candidate == null:
        return
    var pivot := candidate.get_node_or_null("CameraPivot") as Node3D
    var arm := candidate.get_node_or_null("CameraPivot/SpringArm3D") as SpringArm3D
    var view := candidate.get_node_or_null("CameraPivot/SpringArm3D/Camera3D") as Camera3D
    if pivot == null or arm == null or view == null:
        return

    if _player != candidate:
        _normalized_character_id = 0
    _player = candidate
    _camera_pivot = pivot
    _spring_arm = arm
    _camera = view
    _apply_camera_contract()
    _normalize_authored_player_if_needed()


func _view_index_for_distance(distance_m: float) -> int:
    for index: int in range(TUNED_VIEW_DISTANCES.size()):
        if absf(distance_m - TUNED_VIEW_DISTANCES[index]) <= VIEW_MATCH_TOLERANCE_M:
            return index
        if absf(distance_m - LEGACY_VIEW_DISTANCES[index]) <= VIEW_MATCH_TOLERANCE_M:
            return index
    return -1


func _is_legacy_distance(index: int, distance_m: float) -> bool:
    if index < 0 or index >= LEGACY_VIEW_DISTANCES.size():
        return false
    if is_equal_approx(LEGACY_VIEW_DISTANCES[index], TUNED_VIEW_DISTANCES[index]):
        return false
    return absf(distance_m - LEGACY_VIEW_DISTANCES[index]) <= VIEW_MATCH_TOLERANCE_M


func _atomium_presentation_is_active() -> bool:
    if not is_instance_valid(_player):
        return false
    if not _player.has_meta("atomium_direct_presentation_fov_degrees"):
        return false
    if not bool(_player.get_meta("atomium_direct_presentation_avatar_hidden", false)):
        return false
    # DirectSpawnPresentation hides the normal avatar while its source-backed
    # witness owns the view. Fast travel restores VisualUpgrade, so stale startup
    # metadata alone must never retain camera ownership after leaving Atomium.
    var visual_upgrade := _player.get_node_or_null("VisualUpgrade") as Node3D
    return visual_upgrade != null and not visual_upgrade.visible


func _atomium_presentation_fov() -> float:
    if not _atomium_presentation_is_active():
        return -1.0
    var requested := float(_player.get_meta("atomium_direct_presentation_fov_degrees", -1.0))
    if not is_finite(requested) or requested <= 1.0 or requested >= 179.0:
        return -1.0
    return requested


func _ixelles_first_person_is_active() -> bool:
    return is_instance_valid(_player) and bool(_player.get_meta("camera_view_locked_first_person", false))


func _combat_aim_is_active() -> bool:
    return is_instance_valid(_player) and bool(_player.get_meta("combat_weapon_aiming", false))


func _set_camera_owner(owner: String, profile: String, distance_m: float, fov_deg: float) -> void:
    if not is_instance_valid(_player):
        return
    _player.set_meta("gta_scale_camera_owner", owner)
    _player.set_meta("gta_scale_camera_profile", profile)
    _player.set_meta("gta_scale_camera_distance_m", distance_m)
    _player.set_meta("gta_scale_camera_fov_deg", fov_deg)


func _apply_camera_contract() -> void:
    if not _binding_is_valid():
        return

    # Highest priority: exact source-backed Atomium witness. Combat Arsenal has a
    # legacy per-frame FOV lerp, so merely yielding is not enough; the late arbiter
    # must restore the exact presentation value before rendering.
    var atomium_fov := _atomium_presentation_fov()
    if atomium_fov > 0.0:
        _camera.fov = atomium_fov
        _set_camera_owner("special_presentation", "atomium", _spring_arm.spring_length, atomium_fov)
        return

    # Ixelles deliberately locks first person. Keep that lock deterministic even
    # when another gameplay runtime attempts to write a default FOV in the frame.
    if _ixelles_first_person_is_active():
        _spring_arm.spring_length = TUNED_VIEW_DISTANCES[3]
        _camera.fov = TUNED_VIEW_FOVS[3]
        _camera.position = FIRST_PERSON_CAMERA_OFFSET
        _set_camera_owner("special_presentation", "ixelles_first_person", TUNED_VIEW_DISTANCES[3], TUNED_VIEW_FOVS[3])
        return

    var current_distance := _spring_arm.spring_length
    var index := _view_index_for_distance(current_distance)
    if index < 0:
        return

    var restoring_standard := index == 0 and _is_legacy_distance(index, current_distance)
    _spring_arm.spring_length = TUNED_VIEW_DISTANCES[index]
    _camera.position = FIRST_PERSON_CAMERA_OFFSET if index == 3 else THIRD_PERSON_CAMERA_OFFSET

    # Combat owns only the aimed FOV. When aiming stops, normal gameplay immediately
    # regains the tuned profile instead of drifting back to Combat Arsenal's old 69°.
    if _combat_aim_is_active():
        _camera.fov = COMBAT_AIM_FOV_DEG
        _set_camera_owner("combat_aim", VIEW_NAMES[index], TUNED_VIEW_DISTANCES[index], COMBAT_AIM_FOV_DEG)
    else:
        _camera.fov = TUNED_VIEW_FOVS[index]
        _set_camera_owner("gta_gameplay", VIEW_NAMES[index], TUNED_VIEW_DISTANCES[index], TUNED_VIEW_FOVS[index])

    if restoring_standard:
        _camera_pivot.rotation_degrees.x = DEFAULT_THIRD_PERSON_PITCH_DEG


func _normalize_authored_player_if_needed() -> void:
    if not is_instance_valid(_player):
        return
    var authored := _player.get_node_or_null("VisualUpgrade/AuthoredCharacter") as Node3D
    if authored == null:
        return
    var character_id := int(authored.get_instance_id())
    if character_id == _normalized_character_id:
        return

    var bounds := _measure_authored_local_bounds(authored)
    if not bool(bounds.get("found", false)):
        _player.set_meta("gta_scale_player_visual_normalized", false)
        _player.set_meta("gta_scale_player_visual_reason", "no_mesh_bounds")
        _normalized_character_id = character_id
        return

    var minimum: Vector3 = bounds["min"]
    var maximum: Vector3 = bounds["max"]
    var source_height := maximum.y - minimum.y
    if (
        not is_finite(source_height)
        or source_height < MIN_SOURCE_VISUAL_HEIGHT_M
        or source_height > MAX_SOURCE_VISUAL_HEIGHT_M
    ):
        _player.set_meta("gta_scale_player_visual_normalized", false)
        _player.set_meta("gta_scale_player_visual_reason", "source_height_out_of_bounds")
        _player.set_meta("gta_scale_player_visual_source_height_m", source_height)
        _normalized_character_id = character_id
        return

    var uniform_scale := TARGET_PLAYER_VISUAL_HEIGHT_M / source_height
    if uniform_scale < MIN_NORMALIZATION_SCALE or uniform_scale > MAX_NORMALIZATION_SCALE:
        _player.set_meta("gta_scale_player_visual_normalized", false)
        _player.set_meta("gta_scale_player_visual_reason", "normalization_scale_out_of_bounds")
        _player.set_meta("gta_scale_player_visual_source_height_m", source_height)
        _player.set_meta("gta_scale_player_visual_scale", uniform_scale)
        _normalized_character_id = character_id
        return

    authored.scale = Vector3.ONE * uniform_scale
    authored.position = Vector3(
        authored.position.x,
        PLAYER_GROUND_LOCAL_Y - minimum.y * uniform_scale,
        authored.position.z
    )

    _player.set_meta("gta_scale_player_visual_normalized", true)
    _player.set_meta("gta_scale_player_visual_reason", "uniform_height_normalization")
    _player.set_meta("gta_scale_player_visual_source_height_m", source_height)
    _player.set_meta("gta_scale_player_visual_scale", uniform_scale)
    _player.set_meta("gta_scale_player_visual_height_m", TARGET_PLAYER_VISUAL_HEIGHT_M)
    _player.set_meta("gta_scale_player_visual_ground_local_y", PLAYER_GROUND_LOCAL_Y)
    _normalized_character_id = character_id


func _measure_authored_local_bounds(authored: Node3D) -> Dictionary:
    var found := false
    var minimum := Vector3(INF, INF, INF)
    var maximum := Vector3(-INF, -INF, -INF)

    for candidate: Node in authored.find_children("*", "MeshInstance3D", true, false):
        var mesh_instance := candidate as MeshInstance3D
        if mesh_instance == null or mesh_instance.mesh == null:
            continue
        var aabb := mesh_instance.get_aabb()
        if aabb.size.length_squared() <= 0.0000001:
            continue
        for x_index: int in range(2):
            for y_index: int in range(2):
                for z_index: int in range(2):
                    var corner := aabb.position + Vector3(
                        aabb.size.x * float(x_index),
                        aabb.size.y * float(y_index),
                        aabb.size.z * float(z_index)
                    )
                    var root_local := authored.to_local(mesh_instance.to_global(corner))
                    minimum.x = minf(minimum.x, root_local.x)
                    minimum.y = minf(minimum.y, root_local.y)
                    minimum.z = minf(minimum.z, root_local.z)
                    maximum.x = maxf(maximum.x, root_local.x)
                    maximum.y = maxf(maximum.y, root_local.y)
                    maximum.z = maxf(maximum.z, root_local.z)
                    found = true

    return {
        "found": found,
        "min": minimum,
        "max": maximum,
    }
