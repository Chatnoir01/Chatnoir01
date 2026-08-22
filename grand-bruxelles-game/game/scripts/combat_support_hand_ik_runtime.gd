extends Node

# Production two-handed carry pose for long weapons.
# The authored rig has no dedicated clavicle bones, so the torso remains under
# authored animation control. A right-arm TwoBoneIK3D first recenters the weapon
# into a compact low-ready carry pose. Once that modifier has actually solved,
# the canonical weapon owner is refreshed from the solved right hand and only
# then is the visible support grip resolved for the left-arm TwoBoneIK3D.
# This ordering prevents the support hand from chasing a one-frame-stale weapon.

const ACTIVE_WEAPONS: Array[StringName] = [&"cbr4", &"sct8", &"crossbow"]
const SUPPORT_SOCKET_NAME := "WeaponSupportGripSocket"
const SIGNATURE := "combat_two_hand_pose_v10_reachable_crossbow_foregrip"
const MAX_BIND_ATTEMPTS := 480
const LOCK_EPSILON_M := 0.09

# Keep the carry hand in front of the chest instead of near the authored head.
# The shorter forward reach also leaves solver margin while idle animation moves
# the shoulders, so a pose that locks once remains locked after stabilization.
const CARRY_TARGET_LOCAL := {
    &"cbr4": Vector3(0.18, -0.24, -0.12),
    &"sct8": Vector3(0.18, -0.25, -0.11),
    &"crossbow": Vector3(0.15, -0.10, -0.18),
}
const CROSSBOW_SUPPORT_LOCAL := Vector3(-0.10, -0.02, -0.20)
const RIGHT_POLE_LOCAL := Vector3(0.42, -0.18, 0.08)
const LEFT_POLE_LOCAL := Vector3(-0.42, -0.18, 0.08)

var _player: CharacterBody3D = null
var _skeleton: Skeleton3D = null
var _carry_ik: TwoBoneIK3D = null
var _support_ik: TwoBoneIK3D = null
var _carry_target: Node3D = null
var _carry_pole: Node3D = null
var _support_target: Node3D = null
var _support_pole: Node3D = null

var _right_hand_bone := -1
var _right_wrist_bone := -1
var _right_lower_bone := -1
var _right_upper_bone := -1
var _left_hand_bone := -1
var _left_wrist_bone := -1
var _left_lower_bone := -1
var _left_upper_bone := -1
var _bind_attempts := 0
var _active_weapon_id: StringName = &""
var _support_target_ready := false

func _ready() -> void:
    process_priority = 210
    set_process(true)

func _process(_delta: float) -> void:
    if not _ensure_bound():
        return

    var weapon_id := StringName(_player.get_meta("combat_weapon_id", &""))
    var switching := bool(_player.get_meta("combat_weapon_switching", false))
    var animation_ready := _authored_animation_is_active(_player)
    var desired_active := weapon_id in ACTIVE_WEAPONS and not switching and animation_ready
    if not desired_active:
        _active_weapon_id = &""
        _support_target_ready = false
        _set_active(false, weapon_id, "inactive_mode")
        return

    if weapon_id != _active_weapon_id:
        _active_weapon_id = weapon_id
        _support_target_ready = false
        if _support_ik != null:
            _support_ik.active = false

    var basis := _player.global_transform.basis.orthonormalized()
    var right_shoulder := _bone_world_position(_right_upper_bone)
    var left_shoulder := _bone_world_position(_left_upper_bone)
    var shoulder_mid := (right_shoulder + left_shoulder) * 0.5

    var carry_local: Vector3 = CARRY_TARGET_LOCAL.get(weapon_id, CARRY_TARGET_LOCAL[&"cbr4"])
    var desired_right_hand := shoulder_mid + basis * carry_local
    var right_wrist := _bone_world_position(_right_wrist_bone)
    var right_hand := _bone_world_position(_right_hand_bone)
    var right_wrist_to_hand := right_hand - right_wrist
    var desired_right_wrist := desired_right_hand - right_wrist_to_hand
    _carry_target.global_position = desired_right_wrist
    _carry_pole.global_position = right_shoulder + basis * RIGHT_POLE_LOCAL

    _player.set_meta("combat_carry_shoulder_mid_world", shoulder_mid)
    _player.set_meta("combat_carry_right_shoulder_world", right_shoulder)
    _player.set_meta("combat_support_ik_shoulder_world", left_shoulder)
    _player.set_meta("combat_carry_ik_pre_hand_world", right_hand)
    _player.set_meta("combat_carry_ik_desired_hand_world", desired_right_hand)
    _player.set_meta("combat_carry_ik_target_world", _carry_target.global_position)
    _player.set_meta("combat_carry_target_local", carry_local)
    _player.set_meta("combat_carry_ik_lengths", _arm_lengths(
        _right_upper_bone,
        _right_lower_bone,
        _right_wrist_bone,
        _right_hand_bone,
        desired_right_hand
    ))
    _player.set_meta("combat_support_ik_weapon_id", weapon_id)
    _player.set_meta("combat_support_ik_reason", "awaiting_post_carry_weapon_refresh")

    _carry_ik.active = true
    # Keep the left solver enabled only after a support target has been derived
    # from a weapon remounted on the solved right hand. If Godot emits the carry
    # callback after the support modifier in a frame, this state persists and
    # the left solver consumes the corrected target on the next frame.
    _support_ik.active = _support_target_ready
    _player.set_meta("combat_carry_ik_active", true)
    _player.set_meta("combat_support_ik_active", _support_target_ready)

func _ensure_bound() -> bool:
    var current := _current_player()
    if current == null:
        _clear_binding()
        return false
    if current != _player:
        _clear_binding()
        _player = current
    if is_instance_valid(_skeleton) and is_instance_valid(_carry_ik) and is_instance_valid(_support_ik):
        return true
    if _bind_attempts >= MAX_BIND_ATTEMPTS:
        return false
    _bind_attempts += 1

    var visual := _player.get_node_or_null("VisualUpgrade")
    if visual == null:
        return false
    var skeleton := _find_two_hand_skeleton(visual)
    if skeleton == null:
        return false

    var right_hand := _find_hand_bone(skeleton, false)
    var left_hand := _find_hand_bone(skeleton, true)
    var right_chain := _resolve_arm_chain(skeleton, right_hand, false)
    var left_chain := _resolve_arm_chain(skeleton, left_hand, true)
    _player.set_meta("combat_carry_ik_bind_chain", _ancestor_chain(skeleton, right_hand, 7))
    _player.set_meta("combat_support_ik_bind_chain", _ancestor_chain(skeleton, left_hand, 7))
    if right_chain.is_empty() or left_chain.is_empty():
        _player.set_meta("combat_support_ik_reason", "contiguous_arm_chain_unresolved")
        return false

    _skeleton = skeleton
    _right_hand_bone = right_hand
    _right_wrist_bone = int(right_chain["wrist"])
    _right_lower_bone = int(right_chain["lower"])
    _right_upper_bone = int(right_chain["upper"])
    _left_hand_bone = left_hand
    _left_wrist_bone = int(left_chain["wrist"])
    _left_lower_bone = int(left_chain["lower"])
    _left_upper_bone = int(left_chain["upper"])

    _carry_target = _make_target("CombatCarryHandTarget")
    _carry_pole = _make_target("CombatCarryElbowPole")
    _support_target = _make_target("CombatSupportHandTarget")
    _support_pole = _make_target("CombatSupportElbowPole")

    _carry_ik = _make_two_bone_ik(
        "CombatCarryHandIK",
        _right_upper_bone,
        _right_lower_bone,
        _right_wrist_bone,
        _carry_target,
        _carry_pole
    )
    _support_ik = _make_two_bone_ik(
        "CombatSupportHandIK",
        _left_upper_bone,
        _left_lower_bone,
        _left_wrist_bone,
        _support_target,
        _support_pole
    )
    _carry_ik.modification_processed.connect(_on_carry_ik_processed)
    _support_ik.modification_processed.connect(_on_support_ik_processed)

    _player.set_meta("combat_two_hand_pose_signature", SIGNATURE)
    _player.set_meta("combat_carry_ik_solver", "TwoBoneIK3D")
    _player.set_meta("combat_support_ik_solver", "TwoBoneIK3D")
    _player.set_meta("combat_carry_ik_bones", _bone_contract(_right_upper_bone, _right_lower_bone, _right_wrist_bone, _right_hand_bone))
    _player.set_meta("combat_support_ik_bones", _bone_contract(_left_upper_bone, _left_lower_bone, _left_wrist_bone, _left_hand_bone))
    return true

func _make_target(node_name: String) -> Node3D:
    var node := Node3D.new()
    node.name = node_name
    _skeleton.add_child(node)
    return node

func _make_two_bone_ik(node_name: String, upper: int, lower: int, wrist: int, target: Node3D, pole: Node3D) -> TwoBoneIK3D:
    var ik := TwoBoneIK3D.new()
    ik.name = node_name
    ik.setting_count = 1
    _skeleton.add_child(ik)
    ik.set_root_bone_name(0, String(_skeleton.get_bone_name(upper)))
    ik.set_middle_bone_name(0, String(_skeleton.get_bone_name(lower)))
    ik.set_end_bone_name(0, String(_skeleton.get_bone_name(wrist)))
    ik.set_target_node(0, ik.get_path_to(target))
    ik.set_pole_node(0, ik.get_path_to(pole))
    ik.influence = 1.0
    ik.active = false
    return ik

func _resolve_arm_chain(skeleton: Skeleton3D, hand: int, left: bool) -> Dictionary:
    if hand < 0:
        return {}
    var wrist := skeleton.get_bone_parent(hand)
    var lower := skeleton.get_bone_parent(wrist) if wrist >= 0 else -1
    var upper := skeleton.get_bone_parent(lower) if lower >= 0 else -1
    if wrist < 0 or lower < 0 or upper < 0:
        return {}
    if not _bone_has_semantic(skeleton, wrist, "wrist"):
        return {}
    if not _bone_has_semantic(skeleton, lower, "lowerarm"):
        return {}
    if not _bone_has_semantic(skeleton, upper, "upperarm"):
        return {}
    if _bone_is_left(skeleton, upper) != left:
        return {}
    return {"upper": upper, "lower": lower, "wrist": wrist}

func _refresh_weapon_after_carry(weapon_id: StringName) -> bool:
    if _player == null:
        return false

    if weapon_id == &"cbr4" or weapon_id == &"sct8":
        var holder := _player.get_node_or_null("CombatWeaponVisual") as Node3D
        if holder == null:
            return false
        var visual_owner := get_node_or_null("/root/CombatWeaponVisualUpgradeRuntime")
        var orientation_owner := get_node_or_null("/root/CombatWeaponHandOrientationRuntime")
        if visual_owner == null or orientation_owner == null:
            return false
        if not visual_owner.has_method("mount_weapon_to_hand") or not orientation_owner.has_method("orient_weapon_from_player"):
            return false
        var mounted := bool(visual_owner.call("mount_weapon_to_hand", holder, _player, weapon_id))
        var oriented := bool(orientation_owner.call("orient_weapon_from_player", holder, _player, weapon_id))
        _player.set_meta("combat_support_weapon_post_carry_refresh", mounted and oriented)
        _player.set_meta("combat_support_weapon_post_carry_refresh_source", "procedural")
        return mounted and oriented

    if weapon_id == &"crossbow":
        var native_owner := get_node_or_null("/root/CombatNativeWeaponPresentationRuntime")
        if native_owner == null or not native_owner.has_method("refresh_crossbow_from_current_hand"):
            return false
        var refreshed := bool(native_owner.call("refresh_crossbow_from_current_hand", _player))
        _player.set_meta("combat_support_weapon_post_carry_refresh", refreshed)
        _player.set_meta("combat_support_weapon_post_carry_refresh_source", "native_crossbow")
        return refreshed

    return false

func _resolve_support_target(player: CharacterBody3D, weapon_id: StringName) -> Dictionary:
    if weapon_id == &"cbr4" or weapon_id == &"sct8":
        var holder := player.get_node_or_null("CombatWeaponVisual") as Node3D
        if holder == null:
            return {"found": false}
        var support := holder.find_child(SUPPORT_SOCKET_NAME, true, false) as Node3D
        if support == null:
            return {"found": false}
        player.set_meta("combat_support_socket_local", support.position)
        player.set_meta("combat_support_socket_world", support.global_position)
        return {"found": true, "position": support.global_position, "source": "post_carry_support_socket"}

    if weapon_id == &"crossbow":
        var crossbow := player.find_child("2H_Crossbow", true, false) as Node3D
        if crossbow == null or not crossbow.visible:
            return {"found": false}
        # Keep the support palm on the visible inner foregrip/receiver area. The
        # old z=-0.30 target sat beyond the authored left-arm reach once the bow
        # orientation was corrected to follow the right hand.
        var target_world := crossbow.global_transform * CROSSBOW_SUPPORT_LOCAL
        player.set_meta("combat_support_socket_local", CROSSBOW_SUPPORT_LOCAL)
        player.set_meta("combat_support_socket_world", target_world)
        return {"found": true, "position": target_world, "source": "post_carry_crossbow_foregrip"}
    return {"found": false}

func _update_support_target_after_carry(weapon_id: StringName) -> bool:
    if not _refresh_weapon_after_carry(weapon_id):
        _support_target_ready = false
        _support_ik.active = false
        _player.set_meta("combat_support_ik_reason", "post_carry_weapon_refresh_failed")
        return false

    var support_result := _resolve_support_target(_player, weapon_id)
    if not bool(support_result.get("found", false)):
        _support_target_ready = false
        _support_ik.active = false
        _player.set_meta("combat_support_ik_reason", "post_carry_support_target_unavailable")
        return false

    var basis := _player.global_transform.basis.orthonormalized()
    var left_shoulder := _bone_world_position(_left_upper_bone)
    var left_wrist := _bone_world_position(_left_wrist_bone)
    var left_hand := _bone_world_position(_left_hand_bone)
    var desired_left_hand: Vector3 = support_result.get("position", _support_target.global_position)
    var left_wrist_to_hand := left_hand - left_wrist
    var desired_left_wrist := desired_left_hand - left_wrist_to_hand
    _support_target.global_position = desired_left_wrist
    _support_pole.global_position = left_shoulder + basis * LEFT_POLE_LOCAL

    _player.set_meta("combat_support_ik_pre_hand_world", left_hand)
    _player.set_meta("combat_support_ik_desired_hand_world", desired_left_hand)
    _player.set_meta("combat_support_ik_target_world", _support_target.global_position)
    _player.set_meta("combat_support_ik_lengths", _arm_lengths(
        _left_upper_bone,
        _left_lower_bone,
        _left_wrist_bone,
        _left_hand_bone,
        desired_left_hand
    ))
    _player.set_meta("combat_support_ik_target_source", String(support_result.get("source", "")))
    _player.set_meta("combat_support_ik_reason", "post_carry_support_target_ready")
    _support_target_ready = true
    _support_ik.active = true
    _player.set_meta("combat_support_ik_active", true)
    return true

func _on_carry_ik_processed() -> void:
    if _player == null or _skeleton == null or _active_weapon_id == &"":
        return
    var right_hand := _bone_world_position(_right_hand_bone)
    var desired_right_hand: Vector3 = _player.get_meta("combat_carry_ik_desired_hand_world", right_hand)
    var gap := right_hand.distance_to(desired_right_hand)
    _player.set_meta("combat_carry_ik_post_hand_world", right_hand)
    _player.set_meta("combat_carry_hand_gap_m", gap)
    _player.set_meta("combat_carry_ik_locked", gap <= LOCK_EPSILON_M)
    _update_support_target_after_carry(_active_weapon_id)

func _on_support_ik_processed() -> void:
    if _player == null or _skeleton == null or _active_weapon_id == &"":
        return
    var left_hand := _bone_world_position(_left_hand_bone)
    var desired_left_hand: Vector3 = _player.get_meta("combat_support_ik_desired_hand_world", left_hand)
    var gap := left_hand.distance_to(desired_left_hand)
    _player.set_meta("combat_support_ik_post_hand_world", left_hand)
    _player.set_meta("combat_support_hand_gap_m", gap)
    _player.set_meta("combat_support_ik_locked", gap <= LOCK_EPSILON_M)

func _set_active(active: bool, weapon_id: StringName, reason: String) -> void:
    if _carry_ik != null:
        _carry_ik.active = active
    if _support_ik != null:
        _support_ik.active = active and _support_target_ready
    if _player != null:
        _player.set_meta("combat_carry_ik_active", active)
        _player.set_meta("combat_support_ik_active", active and _support_target_ready)
        _player.set_meta("combat_carry_ik_locked", false)
        _player.set_meta("combat_support_ik_locked", false)
        _player.set_meta("combat_support_ik_weapon_id", weapon_id)
        _player.set_meta("combat_support_ik_reason", reason)

func _authored_animation_is_active(player: CharacterBody3D) -> bool:
    if bool(player.get_meta("combat_animation_frozen", false)):
        return false
    var visual := player.get_node_or_null("VisualUpgrade")
    if visual == null:
        return false
    return visual.find_child("Skeleton3D", true, false) != null

func _find_two_hand_skeleton(root: Node) -> Skeleton3D:
    if root is Skeleton3D:
        return root
    for child: Node in root.get_children():
        var found := _find_two_hand_skeleton(child)
        if found != null:
            return found
    return null

func _find_hand_bone(skeleton: Skeleton3D, left: bool) -> int:
    for i: int in range(skeleton.get_bone_count()):
        var normalized := _normalize_bone_name(String(skeleton.get_bone_name(i)))
        if normalized == ("handl" if left else "handr"):
            return i
    for i: int in range(skeleton.get_bone_count()):
        var normalized := _normalize_bone_name(String(skeleton.get_bone_name(i)))
        if normalized.contains("hand") and _bone_is_left(skeleton, i) == left:
            return i
    return -1

func _bone_contract(upper: int, lower: int, wrist: int, hand: int) -> Dictionary:
    return {
        "root": String(_skeleton.get_bone_name(upper)),
        "middle": String(_skeleton.get_bone_name(lower)),
        "end": String(_skeleton.get_bone_name(wrist)),
        "hand": String(_skeleton.get_bone_name(hand)),
    }

func _arm_lengths(upper: int, lower: int, wrist: int, hand: int, target_hand: Vector3) -> Dictionary:
    var upper_pos := _bone_world_position(upper)
    var lower_pos := _bone_world_position(lower)
    var wrist_pos := _bone_world_position(wrist)
    var hand_pos := _bone_world_position(hand)
    var upper_len := upper_pos.distance_to(lower_pos)
    var lower_len := lower_pos.distance_to(wrist_pos)
    var hand_len := wrist_pos.distance_to(hand_pos)
    var full_reach := upper_len + lower_len + hand_len
    var target_distance := upper_pos.distance_to(target_hand)
    return {
        "upper": upper_len,
        "lower": lower_len,
        "wrist_to_hand": hand_len,
        "full_hand_reach": full_reach,
        "hand_target_distance": target_distance,
        "hand_target_reachable": target_distance <= full_reach + 0.001,
    }

func _bone_world_position(bone_idx: int) -> Vector3:
    if _skeleton == null or bone_idx < 0:
        return Vector3.ZERO
    return _skeleton.global_transform * _skeleton.get_bone_global_pose(bone_idx).origin

func _normalize_bone_name(value: String) -> String:
    var out := value.to_lower()
    for token: String in ["mixamorig", "_", ".", "-", ":", " "]:
        out = out.replace(token, "")
    return out

func _bone_has_semantic(skeleton: Skeleton3D, bone_idx: int, semantic: String) -> bool:
    if bone_idx < 0:
        return false
    return _normalize_bone_name(String(skeleton.get_bone_name(bone_idx))).contains(semantic)

func _bone_is_left(skeleton: Skeleton3D, bone_idx: int) -> bool:
    var raw := String(skeleton.get_bone_name(bone_idx)).to_lower()
    var normalized := _normalize_bone_name(raw)
    if raw.ends_with(".l") or raw.ends_with("_l") or raw.ends_with("-l") or raw.ends_with(":l"):
        return true
    if raw.ends_with(".r") or raw.ends_with("_r") or raw.ends_with("-r") or raw.ends_with(":r"):
        return false
    return normalized.contains("left") or normalized.ends_with("l")

func _ancestor_chain(skeleton: Skeleton3D, start: int, depth: int) -> Array[String]:
    var chain: Array[String] = []
    var cursor := start
    for _step: int in range(depth):
        if cursor < 0:
            break
        chain.append(String(skeleton.get_bone_name(cursor)))
        cursor = skeleton.get_bone_parent(cursor)
    return chain

func _current_player() -> CharacterBody3D:
    var scene := get_tree().current_scene
    if scene == null:
        return null
    return scene.get_node_or_null("Player") as CharacterBody3D

func _clear_binding() -> void:
    if is_instance_valid(_carry_ik):
        _carry_ik.queue_free()
    if is_instance_valid(_support_ik):
        _support_ik.queue_free()
    if is_instance_valid(_carry_target):
        _carry_target.queue_free()
    if is_instance_valid(_carry_pole):
        _carry_pole.queue_free()
    if is_instance_valid(_support_target):
        _support_target.queue_free()
    if is_instance_valid(_support_pole):
        _support_pole.queue_free()
    _skeleton = null
    _carry_ik = null
    _support_ik = null
    _carry_target = null
    _carry_pole = null
    _support_target = null
    _support_pole = null
    _right_hand_bone = -1
    _right_wrist_bone = -1
    _right_lower_bone = -1
    _right_upper_bone = -1
    _left_hand_bone = -1
    _left_wrist_bone = -1
    _left_lower_bone = -1
    _left_upper_bone = -1
    _bind_attempts = 0
    _active_weapon_id = &""
    _support_target_ready = false
    if _player != null:
        _player.set_meta("combat_carry_ik_active", false)
        _player.set_meta("combat_support_ik_active", false)
    _player = null
