extends Node

# Uses Godot 4.7's built-in TwoBoneIK3D as a non-destructive support-hand layer.
# The modifier is a direct Skeleton3D child and is only active for long weapons.

const ACTIVE_WEAPONS: Array[StringName] = [&"cbr4", &"sct8", &"crossbow"]
const IK_NAME := "CombatSupportHandIK"
const TARGET_NAME := "CombatSupportHandTarget"
const POLE_NAME := "CombatSupportElbowPole"
const SUPPORT_SOCKET_NAME := "WeaponSupportGripSocket"
const SIGNATURE := "combat_support_hand_ik_v3"
const MAX_BIND_ATTEMPTS := 480

var _player: CharacterBody3D = null
var _skeleton: Skeleton3D = null
var _ik: TwoBoneIK3D = null
var _target: Node3D = null
var _pole: Node3D = null
var _hand_bone := -1
var _wrist_bone := -1
var _lower_arm_bone := -1
var _upper_arm_bone := -1
var _bind_attempts := 0

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
        _set_active(false, weapon_id, "inactive_mode")
        return

    var target_world := _resolve_support_target(_player, weapon_id)
    if not bool(target_world.get("found", false)):
        _set_active(false, weapon_id, "target_unavailable")
        return

    var desired_hand_world: Vector3 = target_world.get("position", _target.global_position)
    # TwoBoneIK3D needs a contiguous three-bone chain. KayKit inserts wrist.l
    # between lowerarm.l and hand.l, so the solver ends at the wrist. Offset the
    # wrist target by the current wrist->hand vector so the actual hand lands on
    # the foregrip instead of the wrist itself.
    var wrist_world := _bone_world_position(_wrist_bone)
    var hand_world := _bone_world_position(_hand_bone)
    var wrist_to_hand := hand_world - wrist_world
    _target.global_position = desired_hand_world - wrist_to_hand

    var shoulder_world := _bone_world_position(_upper_arm_bone)
    _pole.global_position = shoulder_world + _player.global_transform.basis * Vector3(-0.42, -0.18, -0.04)
    _set_active(true, weapon_id, "support_grip")
    _player.set_meta("combat_support_ik_desired_hand_world", desired_hand_world)
    _player.set_meta("combat_support_ik_target_world", _target.global_position)
    _player.set_meta("combat_support_ik_pole_world", _pole.global_position)
    _player.set_meta("combat_support_ik_target_source", String(target_world.get("source", "")))

func _ensure_bound() -> bool:
    var current := _current_player()
    if current == null:
        _clear_binding()
        return false
    if current != _player:
        _clear_binding()
        _player = current
    if is_instance_valid(_skeleton) and is_instance_valid(_ik) and is_instance_valid(_target) and is_instance_valid(_pole):
        return true
    if _bind_attempts >= MAX_BIND_ATTEMPTS:
        return false
    _bind_attempts += 1
    var visual := _player.get_node_or_null("VisualUpgrade")
    if visual == null:
        return false
    var skeleton := _find_left_hand_skeleton(visual)
    if skeleton == null:
        return false
    var hand := _find_left_hand_bone(skeleton)
    if hand < 0:
        return false

    # KayKit arm hierarchy is upperarm.l -> lowerarm.l -> wrist.l -> hand.l.
    # Resolve the semantic bones and keep the TwoBoneIK3D chain contiguous.
    var wrist := skeleton.get_bone_parent(hand)
    var lower := _find_named_ancestor(skeleton, wrist, "lowerarm") if wrist >= 0 else -1
    var upper := _find_named_ancestor(skeleton, lower, "upperarm") if lower >= 0 else -1
    if wrist < 0 or lower < 0 or upper < 0:
        return false

    _skeleton = skeleton
    _hand_bone = hand
    _wrist_bone = wrist
    _lower_arm_bone = lower
    _upper_arm_bone = upper

    _target = Node3D.new()
    _target.name = TARGET_NAME
    _skeleton.add_child(_target)
    _pole = Node3D.new()
    _pole.name = POLE_NAME
    _skeleton.add_child(_pole)

    _ik = TwoBoneIK3D.new()
    _ik.name = IK_NAME
    _ik.setting_count = 1
    _skeleton.add_child(_ik)
    _ik.set_root_bone_name(0, String(_skeleton.get_bone_name(_upper_arm_bone)))
    _ik.set_middle_bone_name(0, String(_skeleton.get_bone_name(_lower_arm_bone)))
    _ik.set_end_bone_name(0, String(_skeleton.get_bone_name(_wrist_bone)))
    _ik.set_target_node(0, _ik.get_path_to(_target))
    _ik.set_pole_node(0, _ik.get_path_to(_pole))
    _ik.set_pole_direction_vector(0, Vector3(0.0, 0.0, 1.0))
    _ik.influence = 1.0
    _ik.active = false
    _ik.modification_processed.connect(_on_ik_processed)

    _player.set_meta("combat_support_ik_signature", SIGNATURE)
    _player.set_meta("combat_support_ik_bones", {
        "upper": String(_skeleton.get_bone_name(_upper_arm_bone)),
        "lower": String(_skeleton.get_bone_name(_lower_arm_bone)),
        "end": String(_skeleton.get_bone_name(_wrist_bone)),
        "hand": String(_skeleton.get_bone_name(_hand_bone)),
    })
    return true

func _resolve_support_target(player: CharacterBody3D, weapon_id: StringName) -> Dictionary:
    if weapon_id == &"cbr4" or weapon_id == &"sct8":
        var holder := player.get_node_or_null("CombatWeaponVisual") as Node3D
        if holder == null:
            return {"found": false}
        var support := holder.find_child(SUPPORT_SOCKET_NAME, true, false) as Node3D
        if support == null:
            return {"found": false}
        return {"found": true, "position": support.global_position, "source": "support_socket"}

    if weapon_id == &"crossbow":
        var crossbow := player.find_child("2H_Crossbow", true, false) as Node3D
        if crossbow == null or not crossbow.visible:
            return {"found": false}
        # The native crossbow has no authored support socket. Place the target
        # in its fore-end region relative to the crossbow transform, not relative
        # to the current hand (which would make the goal move with the solver).
        var target_world := crossbow.global_transform * Vector3(-0.10, -0.02, -0.30)
        return {"found": true, "position": target_world, "source": "crossbow_foregrip_region"}

    return {"found": false}

func _on_ik_processed() -> void:
    if _player == null or _skeleton == null or _target == null or _hand_bone < 0 or _ik == null or not _ik.active:
        return
    var desired_hand_world: Vector3 = _player.get_meta("combat_support_ik_desired_hand_world", _target.global_position)
    var hand_world := _bone_world_position(_hand_bone)
    var gap := hand_world.distance_to(desired_hand_world)
    _player.set_meta("combat_support_hand_gap_m", gap)
    _player.set_meta("combat_support_ik_active", true)
    _player.set_meta("combat_support_ik_locked", gap <= 0.085)

func _set_active(enabled: bool, weapon_id: StringName, reason: String) -> void:
    if _ik != null:
        _ik.active = enabled
    if _player != null:
        _player.set_meta("combat_support_ik_active", enabled)
        _player.set_meta("combat_support_ik_weapon_id", weapon_id)
        _player.set_meta("combat_support_ik_reason", reason)
        if not enabled:
            _player.set_meta("combat_support_ik_locked", false)
            _player.set_meta("combat_support_hand_gap_m", 999.0)

func _authored_animation_is_active(player: CharacterBody3D) -> bool:
    var visual := player.get_node_or_null("VisualUpgrade")
    if visual == null:
        return false
    var animation_player := _find_animation_player(visual)
    return animation_player != null and animation_player.active

func _find_animation_player(node: Node) -> AnimationPlayer:
    if node is AnimationPlayer:
        return node as AnimationPlayer
    for child: Node in node.get_children():
        var found := _find_animation_player(child)
        if found != null:
            return found
    return null

func _find_left_hand_skeleton(node: Node) -> Skeleton3D:
    if node is Skeleton3D:
        var skeleton := node as Skeleton3D
        if _find_left_hand_bone(skeleton) >= 0:
            return skeleton
    for child: Node in node.get_children():
        var found := _find_left_hand_skeleton(child)
        if found != null:
            return found
    return null

func _find_left_hand_bone(skeleton: Skeleton3D) -> int:
    for index: int in range(skeleton.get_bone_count()):
        if _is_left_hand_name(String(skeleton.get_bone_name(index))):
            return index
    return -1

func _find_named_ancestor(skeleton: Skeleton3D, start_bone: int, semantic: String) -> int:
    var current := skeleton.get_bone_parent(start_bone) if start_bone >= 0 else -1
    while current >= 0:
        if _normalized_bone_name(String(skeleton.get_bone_name(current))).contains(semantic):
            return current
        current = skeleton.get_bone_parent(current)
    return -1

static func _normalized_bone_name(value: String) -> String:
    var compact := value.to_lower()
    for token: String in [":", "_", "-", ".", " "]:
        compact = compact.replace(token, "")
    return compact

static func _is_left_hand_name(value: String) -> bool:
    var compact := _normalized_bone_name(value)
    return compact.ends_with("lefthand") or compact.ends_with("handl") or compact == "lhand"

func _bone_world_position(bone_index: int) -> Vector3:
    if _skeleton == null or bone_index < 0:
        return Vector3.ZERO
    return (_skeleton.global_transform * _skeleton.get_bone_global_pose(bone_index)).origin

func _current_player() -> CharacterBody3D:
    var scene := get_tree().current_scene
    if scene == null:
        return null
    return scene.get_node_or_null("Player") as CharacterBody3D

func _clear_binding() -> void:
    if is_instance_valid(_ik):
        _ik.queue_free()
    if is_instance_valid(_target):
        _target.queue_free()
    if is_instance_valid(_pole):
        _pole.queue_free()
    _player = null
    _skeleton = null
    _ik = null
    _target = null
    _pole = null
    _hand_bone = -1
    _wrist_bone = -1
    _lower_arm_bone = -1
    _upper_arm_bone = -1
    _bind_attempts = 0
