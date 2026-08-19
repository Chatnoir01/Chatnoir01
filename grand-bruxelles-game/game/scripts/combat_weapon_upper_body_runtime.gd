extends Node

# Combat V2 LOT 2 — authored-player upper-body weapon stance.
# Targets are derived from the real shoulder bones, never from an assumed
# Player-root eye/chest height. This keeps the pose anatomical across rigs.

const SIGNATURE := "combat_weapon_upper_body_v3_shoulder_relative"
const RIGHT_TARGET_NAME := "CombatRightHandCarryTarget"
const LEFT_TARGET_NAME := "CombatLeftHandSupportTarget"
const RIGHT_IK_NAME := "CombatRightArmIK"
const LEFT_IK_NAME := "CombatLeftArmIK"
const SWAY_ROOT_NAME := "WeaponVisualV2SwayRoot"
const SUPPORT_SOCKET_NAME := "WeaponSupportGripSocket"
const TARGET_BLEND_SPEED := 13.0
const INFLUENCE_BLEND_SPEED := 7.5
const MAX_REACH_FACTOR := 0.94

var _pose_enabled := true
var _player: CharacterBody3D
var _skeleton: Skeleton3D
var _right_hand_index := -1
var _left_hand_index := -1
var _right_root_index := -1
var _left_root_index := -1
var _right_forearm_index := -1
var _left_forearm_index := -1
var _right_target: Node3D
var _left_target: Node3D
var _right_ik: SkeletonIK3D
var _left_ik: SkeletonIK3D
var _right_target_world := Vector3.INF
var _support_target_world := Vector3.INF

func _ready() -> void:
    process_priority = 200
    set_process(true)

func _process(delta: float) -> void:
    if not _ensure_bound():
        return
    _update_pose(delta)

func set_pose_enabled(enabled: bool) -> void:
    _pose_enabled = enabled
    if not enabled:
        _set_influence(0.0, 0.0, 1.0)
        _right_target_world = Vector3.INF
        _support_target_world = Vector3.INF
        if is_instance_valid(_player):
            _player.set_meta("combat_upper_body_pose_active", false)

func current_right_target_world() -> Vector3:
    return _right_target_world

func current_support_target_world() -> Vector3:
    return _support_target_world

func _ensure_bound() -> bool:
    if is_instance_valid(_player) and is_instance_valid(_skeleton) and is_instance_valid(_right_ik) and is_instance_valid(_left_ik) and is_instance_valid(_right_target) and is_instance_valid(_left_target):
        return true
    _clear_binding()
    var scene := get_tree().current_scene
    if scene == null:
        return false
    var player := scene.get_node_or_null("Player") as CharacterBody3D
    if player == null:
        return false
    var visual := player.get_node_or_null("VisualUpgrade")
    if visual == null or not visual.has_method("is_using_authored_character") or not bool(visual.call("is_using_authored_character")):
        return false
    var skeleton := _find_player_skeleton(visual)
    if skeleton == null:
        return false
    return _bind(player, skeleton)

func _bind(player: CharacterBody3D, skeleton: Skeleton3D) -> bool:
    var right_hand := _find_hand_bone(skeleton, true)
    var left_hand := _find_hand_bone(skeleton, false)
    if right_hand < 0 or left_hand < 0:
        return false
    var right_forearm := _resolve_forearm_bone(skeleton, right_hand)
    var left_forearm := _resolve_forearm_bone(skeleton, left_hand)
    if right_forearm < 0 or left_forearm < 0:
        return false
    var right_root := skeleton.get_bone_parent(right_forearm)
    var left_root := skeleton.get_bone_parent(left_forearm)
    if right_root < 0 or left_root < 0:
        return false

    _player = player
    _skeleton = skeleton
    _right_hand_index = right_hand
    _left_hand_index = left_hand
    _right_forearm_index = right_forearm
    _left_forearm_index = left_forearm
    _right_root_index = right_root
    _left_root_index = left_root

    _right_target = _make_target(player, RIGHT_TARGET_NAME)
    _left_target = _make_target(player, LEFT_TARGET_NAME)
    _right_ik = _make_arm_ik(skeleton, RIGHT_IK_NAME, right_root, right_hand, _right_target)
    _left_ik = _make_arm_ik(skeleton, LEFT_IK_NAME, left_root, left_hand, _left_target)
    if _right_ik == null or _left_ik == null:
        _clear_binding()
        return false

    player.set_meta("combat_upper_body_signature", SIGNATURE)
    player.set_meta("combat_upper_body_right_chain", _chain_names(skeleton, right_hand))
    player.set_meta("combat_upper_body_left_chain", _chain_names(skeleton, left_hand))
    player.set_meta("combat_upper_body_right_root", String(skeleton.get_bone_name(right_root)))
    player.set_meta("combat_upper_body_left_root", String(skeleton.get_bone_name(left_root)))
    player.set_meta("combat_upper_body_right_forearm", String(skeleton.get_bone_name(right_forearm)))
    player.set_meta("combat_upper_body_left_forearm", String(skeleton.get_bone_name(left_forearm)))
    return true

func _resolve_forearm_bone(skeleton: Skeleton3D, hand_index: int) -> int:
    var current := skeleton.get_bone_parent(hand_index)
    var fallback := current
    for _depth: int in range(5):
        if current < 0:
            break
        var compact := _normalized_bone_name(String(skeleton.get_bone_name(current)))
        if compact.contains("lowerarm") or compact.contains("forearm"):
            return current
        if compact.contains("upperarm"):
            break
        current = skeleton.get_bone_parent(current)
    if fallback >= 0:
        var fallback_name := _normalized_bone_name(String(skeleton.get_bone_name(fallback)))
        if fallback_name.contains("wrist"):
            var parent := skeleton.get_bone_parent(fallback)
            if parent >= 0:
                return parent
    return fallback

func _make_target(player: CharacterBody3D, target_name: String) -> Node3D:
    var existing := player.get_node_or_null(target_name) as Node3D
    if existing != null:
        return existing
    var target := Node3D.new()
    target.name = target_name
    player.add_child(target)
    target.global_transform = player.global_transform
    return target

func _make_arm_ik(skeleton: Skeleton3D, node_name: String, root_index: int, hand_index: int, target: Node3D) -> SkeletonIK3D:
    var existing := skeleton.get_node_or_null(node_name) as SkeletonIK3D
    if existing != null:
        existing.stop()
        existing.queue_free()
    var ik := SkeletonIK3D.new()
    ik.name = node_name
    ik.root_bone = skeleton.get_bone_name(root_index)
    ik.tip_bone = skeleton.get_bone_name(hand_index)
    ik.override_tip_basis = false
    ik.max_iterations = 18
    ik.min_distance = 0.006
    ik.influence = 0.0
    ik.use_magnet = true
    skeleton.add_child(ik)
    ik.target_node = ik.get_path_to(target)
    ik.start()
    return ik

func _update_pose(delta: float) -> void:
    if not _pose_enabled or not is_instance_valid(_player) or not is_instance_valid(_skeleton):
        _set_influence(0.0, 0.0, delta)
        return
    var weapon_id := StringName(_player.get_meta("combat_weapon_id", &""))
    if weapon_id == &"":
        _set_influence(0.0, 0.0, delta)
        _right_target_world = Vector3.INF
        _support_target_world = Vector3.INF
        _player.set_meta("combat_upper_body_pose_active", false)
        return

    var aiming := bool(_player.get_meta("combat_weapon_aiming", false))
    var reloading := bool(_player.get_meta("combat_weapon_reloading", false))
    var desired_right := _resolve_right_target(weapon_id, aiming)
    var desired_left := _resolve_support_target(weapon_id, desired_right)
    desired_right = _clamp_target_to_arm(_right_root_index, _right_hand_index, desired_right)
    desired_left = _clamp_target_to_arm(_left_root_index, _left_hand_index, desired_left)

    if _right_target_world == Vector3.INF:
        _right_target_world = desired_right
    else:
        _right_target_world = _right_target_world.lerp(desired_right, clampf(delta * TARGET_BLEND_SPEED, 0.0, 1.0))
    if _support_target_world == Vector3.INF:
        _support_target_world = desired_left
    else:
        _support_target_world = _support_target_world.lerp(desired_left, clampf(delta * TARGET_BLEND_SPEED, 0.0, 1.0))

    _right_target.global_position = _right_target_world
    _left_target.global_position = _support_target_world
    _update_magnets(aiming)

    var right_influence := 0.96 if aiming else 0.86
    var left_influence := 0.97 if aiming else 0.90
    if reloading:
        right_influence = 0.66
        left_influence = 0.24
    _set_influence(right_influence, left_influence, delta)

    _player.set_meta("combat_upper_body_pose_active", true)
    _player.set_meta("combat_upper_body_right_target_world", _right_target_world)
    _player.set_meta("combat_upper_body_support_target_world", _support_target_world)
    _player.set_meta("combat_upper_body_aiming", aiming)
    _player.set_meta("combat_upper_body_target_frame", "shoulder_relative")

func _horizontal_frame() -> Dictionary:
    var forward := -_player.global_transform.basis.z
    var camera := _player.get_viewport().get_camera_3d()
    if camera != null:
        forward = -camera.global_transform.basis.z
    forward.y = 0.0
    if forward.length_squared() < 0.0001:
        forward = -_player.global_transform.basis.z
        forward.y = 0.0
    forward = forward.normalized()
    var right := forward.cross(Vector3.UP).normalized()
    return {"forward": forward, "right": right}

func _resolve_right_target(weapon_id: StringName, aiming: bool) -> Vector3:
    var frame := _horizontal_frame()
    var forward: Vector3 = frame.get("forward", Vector3.FORWARD)
    var right: Vector3 = frame.get("right", Vector3.RIGHT)
    var shoulder := _bone_world_position(_right_root_index)
    var offset := shoulder_relative_offset(weapon_id, aiming)
    return shoulder + right * offset.x + Vector3.UP * offset.y + forward * offset.z

func _resolve_support_target(weapon_id: StringName, right_world: Vector3) -> Vector3:
    var holder := _player.get_node_or_null("CombatWeaponVisual") as Node3D
    if holder != null:
        var support_socket := holder.find_child(SUPPORT_SOCKET_NAME, true, false) as Node3D
        if support_socket != null:
            return support_socket.global_position
        var sway_root := holder.find_child(SWAY_ROOT_NAME, true, false) as Node3D
        if sway_root != null:
            return sway_root.global_transform * support_grip_local(weapon_id)
        return holder.global_transform * support_grip_local(weapon_id)

    var frame := _horizontal_frame()
    var forward: Vector3 = frame.get("forward", Vector3.FORWARD)
    var right: Vector3 = frame.get("right", Vector3.RIGHT)
    var fallback := support_offset_from_right(weapon_id)
    return right_world + right * fallback.x + Vector3.UP * fallback.y + forward * fallback.z

func _clamp_target_to_arm(root_index: int, hand_index: int, target_world: Vector3) -> Vector3:
    var root_world := _bone_world_position(root_index)
    var reach := _arm_chain_reach(root_index, hand_index)
    if reach <= 0.05:
        return target_world
    var delta := target_world - root_world
    var max_reach := reach * MAX_REACH_FACTOR
    if delta.length() <= max_reach:
        return target_world
    return root_world + delta.normalized() * max_reach

func _arm_chain_reach(root_index: int, hand_index: int) -> float:
    var reach := 0.0
    var current := hand_index
    var guard := 0
    while current >= 0 and current != root_index and guard < 8:
        var parent := _skeleton.get_bone_parent(current)
        if parent < 0:
            break
        reach += _bone_world_position(parent).distance_to(_bone_world_position(current))
        current = parent
        guard += 1
    return reach

func _update_magnets(aiming: bool) -> void:
    if not is_instance_valid(_right_ik) or not is_instance_valid(_left_ik):
        return
    var frame := _horizontal_frame()
    var forward: Vector3 = frame.get("forward", Vector3.FORWARD)
    var right: Vector3 = frame.get("right", Vector3.RIGHT)
    var forward_m := 0.13 if aiming else 0.08
    var down_m := 0.13 if aiming else 0.18
    var right_world := _bone_world_position(_right_root_index) + right * 0.25 + forward * forward_m - Vector3.UP * down_m
    var left_world := _bone_world_position(_left_root_index) - right * 0.25 + forward * forward_m - Vector3.UP * down_m
    var inverse := _skeleton.global_transform.affine_inverse()
    _right_ik.magnet = inverse * right_world
    _left_ik.magnet = inverse * left_world

func _set_influence(right_value: float, left_value: float, delta: float) -> void:
    if is_instance_valid(_right_ik):
        var right_step := maxf(delta, 0.0) * INFLUENCE_BLEND_SPEED
        _right_ik.influence = move_toward(_right_ik.influence, right_value, right_step)
    if is_instance_valid(_left_ik):
        var left_step := maxf(delta, 0.0) * INFLUENCE_BLEND_SPEED
        _left_ik.influence = move_toward(_left_ik.influence, left_value, left_step)

func _bone_world_position(index: int) -> Vector3:
    return (_skeleton.global_transform * _skeleton.get_bone_global_pose(index)).origin

func _find_player_skeleton(node: Node) -> Skeleton3D:
    if node is Skeleton3D:
        var skeleton := node as Skeleton3D
        if _find_hand_bone(skeleton, true) >= 0 and _find_hand_bone(skeleton, false) >= 0:
            return skeleton
    for child: Node in node.get_children():
        var found := _find_player_skeleton(child)
        if found != null:
            return found
    return null

func _find_hand_bone(skeleton: Skeleton3D, right_side: bool) -> int:
    if skeleton == null:
        return -1
    for bone_index: int in range(skeleton.get_bone_count()):
        var bone_name := String(skeleton.get_bone_name(bone_index))
        if right_side and is_right_hand_name(bone_name):
            return bone_index
        if not right_side and is_left_hand_name(bone_name):
            return bone_index
    return -1

static func _normalized_bone_name(value: String) -> String:
    var compact := value.to_lower()
    for token: String in [":", "_", "-", ".", " "]:
        compact = compact.replace(token, "")
    return compact

static func is_right_hand_name(value: String) -> bool:
    var compact := _normalized_bone_name(value)
    return compact.ends_with("righthand") or compact.ends_with("handr") or compact == "rhand"

static func is_left_hand_name(value: String) -> bool:
    var compact := _normalized_bone_name(value)
    return compact.ends_with("lefthand") or compact.ends_with("handl") or compact == "lhand"

# x = screen/player-right, y = up, z = camera/player-forward.
# Values are intentionally shoulder-relative and therefore small.
static func shoulder_relative_offset(weapon_id: StringName, aiming: bool) -> Vector3:
    if aiming:
        match weapon_id:
            &"bx9":
                return Vector3(0.06, -0.10, 0.38)
            &"cbr4":
                return Vector3(0.05, -0.11, 0.42)
            &"sct8":
                return Vector3(0.05, -0.13, 0.40)
            _:
                return Vector3(0.05, -0.11, 0.40)
    match weapon_id:
        &"bx9":
            return Vector3(0.11, -0.24, 0.25)
        &"cbr4":
            return Vector3(0.09, -0.20, 0.34)
        &"sct8":
            return Vector3(0.09, -0.22, 0.33)
        _:
            return Vector3(0.09, -0.21, 0.32)

static func support_grip_local(weapon_id: StringName) -> Vector3:
    match weapon_id:
        &"bx9":
            return Vector3(-0.02, -0.10, -0.16)
        &"cbr4":
            return Vector3(0.0, -0.01, -0.69)
        &"sct8":
            return Vector3(0.0, -0.03, -0.67)
        _:
            return Vector3.ZERO

# x = right, y = up, z = forward relative to the right-hand target.
static func support_offset_from_right(weapon_id: StringName) -> Vector3:
    match weapon_id:
        &"bx9":
            return Vector3(-0.17, 0.01, 0.12)
        &"cbr4":
            return Vector3(-0.20, 0.01, 0.30)
        &"sct8":
            return Vector3(-0.21, 0.00, 0.29)
        _:
            return Vector3(-0.19, 0.01, 0.25)

func _chain_names(skeleton: Skeleton3D, tip_index: int) -> Array[String]:
    var result: Array[String] = []
    var current := tip_index
    for _depth: int in range(6):
        if current < 0:
            break
        result.append(String(skeleton.get_bone_name(current)))
        current = skeleton.get_bone_parent(current)
    return result

func _clear_binding() -> void:
    _player = null
    _skeleton = null
    _right_hand_index = -1
    _left_hand_index = -1
    _right_root_index = -1
    _left_root_index = -1
    _right_forearm_index = -1
    _left_forearm_index = -1
    _right_target = null
    _left_target = null
    _right_ik = null
    _left_ik = null
    _right_target_world = Vector3.INF
    _support_target_world = Vector3.INF