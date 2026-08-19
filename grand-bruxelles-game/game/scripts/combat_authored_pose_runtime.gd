extends Node

# Additive combat posing for the authored player skeleton.
# Runs after locomotion animation evaluation and before the weapon hand-lock layer.

const SIGNATURE := "combat_authored_pose_v1"
const ACTION_META := "combat_action_lock_until_ms"
const MOVE_META := "combat_move_id"
const WEAPON_META := "combat_weapon_id"
const SHOT_META := "combat_weapon_last_shot_ms"

var _melee_start_ms := -1
var _melee_until_ms := -1
var _melee_move: Dictionary = {}
var _shot_seen_ms := -1
var _shot_kick_until_ms := -1
var _bound_player_id := 0
var _skeleton: Skeleton3D = null
var _bones: Dictionary = {}

func _ready() -> void:
    process_priority = 50
    set_process(true)

func request_melee_pose(player: CharacterBody3D, move: Dictionary) -> void:
    if player == null or not is_instance_valid(player):
        return
    var now := Time.get_ticks_msec()
    var total_ms := int(round((float(move.get("windup_s", 0.07)) + float(move.get("active_s", 0.09)) + float(move.get("recover_s", 0.20))) * 1000.0))
    _melee_start_ms = now
    _melee_until_ms = now + maxi(total_ms, 180)
    _melee_move = move.duplicate(true)
    player.set_meta("combat_pose_signature", SIGNATURE)
    player.set_meta("combat_pose_move_id", move.get("id", &""))
    player.set_meta("combat_pose_until_ms", _melee_until_ms)

func request_shot_pose(player: CharacterBody3D, weapon_id: StringName) -> void:
    if player == null or not is_instance_valid(player):
        return
    var now := Time.get_ticks_msec()
    _shot_kick_until_ms = now + shot_kick_duration_ms(weapon_id)
    player.set_meta("combat_pose_last_shot_weapon", weapon_id)

func _process(_delta: float) -> void:
    var player := _current_player()
    if player == null:
        _clear_binding()
        return
    if not _ensure_skeleton(player):
        return

    var now := Time.get_ticks_msec()
    var last_shot := int(player.get_meta(SHOT_META, -1))
    if last_shot >= 0 and last_shot != _shot_seen_ms:
        _shot_seen_ms = last_shot
        request_shot_pose(player, StringName(player.get_meta(WEAPON_META, &"")))

    if now <= _melee_until_ms and not _melee_move.is_empty():
        _apply_melee_pose(player, now)
        return

    var weapon_id := StringName(player.get_meta(WEAPON_META, &""))
    if weapon_id != &"":
        _apply_weapon_pose(player, weapon_id, now)

func _ensure_skeleton(player: CharacterBody3D) -> bool:
    if _bound_player_id == player.get_instance_id() and is_instance_valid(_skeleton):
        return true
    _bound_player_id = player.get_instance_id()
    _skeleton = null
    _bones.clear()
    var visual := player.get_node_or_null("VisualUpgrade")
    if visual == null:
        return false
    _skeleton = _find_skeleton(visual)
    if _skeleton == null:
        return false
    _resolve_bones()
    player.set_meta("combat_pose_skeleton", _skeleton.name)
    player.set_meta("combat_pose_resolved_bones", _bones.size())
    return true

func _find_skeleton(node: Node) -> Skeleton3D:
    if node is Skeleton3D:
        return node as Skeleton3D
    for child: Node in node.get_children():
        var found := _find_skeleton(child)
        if found != null:
            return found
    return null

func _resolve_bones() -> void:
    if _skeleton == null:
        return
    for bone_index: int in range(_skeleton.get_bone_count()):
        var raw := String(_skeleton.get_bone_name(bone_index))
        var compact := _compact(raw)
        var role := _role_for_bone(compact)
        if role != &"" and not _bones.has(role):
            _bones[role] = bone_index

func _role_for_bone(compact: String) -> StringName:
    if _matches_side_part(compact, "hand", true):
        return &"right_hand"
    if _matches_side_part(compact, "hand", false):
        return &"left_hand"
    if _matches_any(compact, ["forearmr", "lowerarmr", "rightforearm", "rightlowerarm"]):
        return &"right_forearm"
    if _matches_any(compact, ["forearml", "lowerarml", "leftforearm", "leftlowerarm"]):
        return &"left_forearm"
    if _matches_any(compact, ["upperarmr", "rightupperarm", "armupperr"]):
        return &"right_upper_arm"
    if _matches_any(compact, ["upperarml", "leftupperarm", "armupperl"]):
        return &"left_upper_arm"
    if _matches_any(compact, ["thighr", "uplegr", "upperlegr", "rightthigh", "rightupleg"]):
        return &"right_thigh"
    if _matches_any(compact, ["thighl", "uplegl", "upperlegl", "leftthigh", "leftupleg"]):
        return &"left_thigh"
    if _matches_any(compact, ["spine2", "spine3", "chest", "upperchest"]):
        return &"chest"
    return &""

func _matches_side_part(compact: String, part: String, right: bool) -> bool:
    if not compact.contains(part):
        return false
    if right:
        return compact.ends_with("r") or compact.contains("right%s" % part) or compact.contains("%sright" % part)
    return compact.ends_with("l") or compact.contains("left%s" % part) or compact.contains("%sleft" % part)

func _matches_any(compact: String, values: Array[String]) -> bool:
    for value: String in values:
        if compact == value or compact.ends_with(value):
            return true
    return false

func _compact(value: String) -> String:
    var compact := value.to_lower()
    for token: String in [":", "_", "-", ".", " "]:
        compact = compact.replace(token, "")
    return compact

func _apply_melee_pose(player: CharacterBody3D, now: int) -> void:
    var duration := maxi(1, _melee_until_ms - _melee_start_ms)
    var t := clampf(float(now - _melee_start_ms) / float(duration), 0.0, 1.0)
    var weight := _strike_envelope(t)
    var move_id := StringName(_melee_move.get("id", player.get_meta(MOVE_META, &"")))
    var profile := melee_pose_profile(move_id)
    _apply_profile(profile, weight)
    player.set_meta("combat_pose_phase", t)
    player.set_meta("combat_pose_weight", weight)

func _apply_weapon_pose(player: CharacterBody3D, weapon_id: StringName, now: int) -> void:
    var aiming := bool(player.get_meta("combat_weapon_aiming", false))
    var profile := weapon_pose_profile(weapon_id, aiming)
    _apply_profile(profile, 1.0)
    if now <= _shot_kick_until_ms:
        var kick_profile := shot_pose_profile(weapon_id)
        var kick_weight := clampf(float(_shot_kick_until_ms - now) / float(maxi(1, shot_kick_duration_ms(weapon_id))), 0.0, 1.0)
        _apply_profile(kick_profile, kick_weight)
    player.set_meta("combat_pose_weapon_id", weapon_id)
    player.set_meta("combat_pose_aiming", aiming)

func _apply_profile(profile: Dictionary, weight: float) -> void:
    if _skeleton == null or weight <= 0.001:
        return
    for raw_role: Variant in profile.keys():
        var role := StringName(raw_role)
        if not _bones.has(role):
            continue
        var degrees: Vector3 = profile[role]
        _apply_bone_offset(int(_bones[role]), degrees, weight)

func _apply_bone_offset(bone_index: int, degrees: Vector3, weight: float) -> void:
    if _skeleton == null or bone_index < 0:
        return
    var pose := _skeleton.get_bone_global_pose(bone_index)
    var offset := Basis.from_euler(Vector3(deg_to_rad(degrees.x), deg_to_rad(degrees.y), deg_to_rad(degrees.z)))
    var target := Transform3D(pose.basis * offset, pose.origin)
    _skeleton.set_bone_global_pose_override(bone_index, target, clampf(weight, 0.0, 1.0), false)

func _strike_envelope(t: float) -> float:
    if t < 0.24:
        return lerpf(0.0, 0.36, t / 0.24)
    if t < 0.56:
        return lerpf(0.36, 1.0, (t - 0.24) / 0.32)
    return lerpf(1.0, 0.0, (t - 0.56) / 0.44)

func _current_player() -> CharacterBody3D:
    var scene := get_tree().current_scene
    if scene == null:
        return null
    return scene.get_node_or_null("Player") as CharacterBody3D

func _clear_binding() -> void:
    _bound_player_id = 0
    _skeleton = null
    _bones.clear()

static func shot_kick_duration_ms(weapon_id: StringName) -> int:
    match weapon_id:
        &"sct8":
            return 145
        &"bx9":
            return 90
        _:
            return 105

static func weapon_pose_profile(weapon_id: StringName, aiming: bool) -> Dictionary:
    var aim_bonus := -10.0 if aiming else 0.0
    match weapon_id:
        &"bx9":
            return {
                &"right_upper_arm": Vector3(-42.0 + aim_bonus, -8.0, -8.0),
                &"right_forearm": Vector3(-28.0, 2.0, -4.0),
                &"left_upper_arm": Vector3(-34.0 + aim_bonus, 10.0, 8.0),
                &"left_forearm": Vector3(-38.0, -3.0, 7.0),
                &"chest": Vector3(-4.0, -5.0, 0.0),
            }
        &"cbr4", &"sct8":
            return {
                &"right_upper_arm": Vector3(-52.0 + aim_bonus, -10.0, -9.0),
                &"right_forearm": Vector3(-34.0, 1.0, -4.0),
                &"left_upper_arm": Vector3(-56.0 + aim_bonus, 18.0, 12.0),
                &"left_forearm": Vector3(-45.0, -8.0, 12.0),
                &"chest": Vector3(-5.0, -6.0, 0.0),
            }
        _:
            return {}

static func shot_pose_profile(weapon_id: StringName) -> Dictionary:
    var kick := 5.0
    if weapon_id == &"sct8":
        kick = 12.0
    elif weapon_id == &"bx9":
        kick = 7.0
    return {
        &"right_upper_arm": Vector3(kick, 0.0, 0.0),
        &"left_upper_arm": Vector3(kick * 0.72, 0.0, 0.0),
        &"chest": Vector3(kick * 0.22, 0.0, 0.0),
    }

static func melee_pose_profile(move_id: StringName) -> Dictionary:
    match move_id:
        &"jab_left":
            return {&"left_upper_arm": Vector3(-72.0, -8.0, -7.0), &"left_forearm": Vector3(-34.0, 0.0, 0.0), &"right_upper_arm": Vector3(-24.0, 8.0, 10.0), &"chest": Vector3(-4.0, -7.0, 0.0)}
        &"cross_right":
            return {&"right_upper_arm": Vector3(-82.0, 8.0, 8.0), &"right_forearm": Vector3(-30.0, 0.0, 0.0), &"left_upper_arm": Vector3(-28.0, -8.0, -10.0), &"chest": Vector3(-5.0, 12.0, -3.0)}
        &"hook_left":
            return {&"left_upper_arm": Vector3(-54.0, -32.0, -35.0), &"left_forearm": Vector3(-64.0, 0.0, -14.0), &"chest": Vector3(-3.0, -22.0, 7.0)}
        &"hook_right":
            return {&"right_upper_arm": Vector3(-56.0, 34.0, 34.0), &"right_forearm": Vector3(-62.0, 0.0, 14.0), &"chest": Vector3(-3.0, 24.0, -7.0)}
        &"uppercut_right":
            return {&"right_upper_arm": Vector3(-38.0, 18.0, 18.0), &"right_forearm": Vector3(-92.0, 0.0, 0.0), &"chest": Vector3(9.0, 10.0, -5.0)}
        &"body_hook_left":
            return {&"left_upper_arm": Vector3(-42.0, -28.0, -26.0), &"left_forearm": Vector3(-74.0, 0.0, -12.0), &"chest": Vector3(10.0, -18.0, 5.0)}
        &"front_kick_right", &"push_kick_right":
            return {&"right_thigh": Vector3(-66.0, 0.0, 0.0), &"left_thigh": Vector3(8.0, 0.0, -3.0), &"left_upper_arm": Vector3(-25.0, -8.0, -8.0), &"right_upper_arm": Vector3(-24.0, 8.0, 8.0), &"chest": Vector3(10.0, 0.0, 0.0)}
        &"low_kick_left":
            return {&"left_thigh": Vector3(-52.0, -8.0, -18.0), &"right_thigh": Vector3(8.0, 0.0, 3.0), &"chest": Vector3(7.0, -12.0, 4.0)}
        &"elbow_right":
            return {&"right_upper_arm": Vector3(-48.0, 32.0, 28.0), &"right_forearm": Vector3(-108.0, 0.0, 18.0), &"chest": Vector3(-3.0, 28.0, -8.0)}
        _:
            return {&"right_upper_arm": Vector3(-42.0, 0.0, 0.0), &"left_upper_arm": Vector3(-28.0, 0.0, 0.0)}
