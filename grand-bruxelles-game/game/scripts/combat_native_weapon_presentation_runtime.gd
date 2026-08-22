extends Node

# Presentation for Rogue/KayKit native crossbow + knife. These meshes remain
# authored children of the character rig. The runtime never overrides bones;
# it only adjusts the visible native mesh while its corresponding weapon is the
# canonical active equipment.

const SIGNATURE := "combat_native_weapon_presentation_v3_hand_relative_basis"
const CROSSBOW_ID := &"crossbow"
const KNIFE_ID := &"knife"
const CROSSBOW_NODE := "2H_Crossbow"
const KNIFE_NODE := "Knife"
const MAX_CROSSBOW_HAND_REGION_GAP_M := 0.12

# The crossbow's imported orientation already encodes how its mesh is aligned to
# the authored hand. Preserve that basis relative to the right-hand anchor instead
# of forcing player/world Euler angles, which made the bow cut across the neck.
const CROSSBOW_TRANSITION_ROTATION_DEG := Vector3(22.0, 18.0, 12.0)
const CROSSBOW_TRANSITION_OFFSET_LOCAL := Vector3(0.15, -0.31, 0.22)
const CROSSBOW_RECOIL_DEG := -5.0

var _bound_player_id := 0
var _bound_crossbow_id := 0
var _crossbow_hand_offset_local := Vector3.ZERO
var _crossbow_basis_in_hand := Basis.IDENTITY
var _crossbow_offset_ready := false
var _bound_knife_id := 0
var _knife_rest_position := Vector3.ZERO
var _knife_rest_rotation := Vector3.ZERO
var _knife_rest_ready := false

func _ready() -> void:
    process_priority = 130
    set_process(true)

func _process(_delta: float) -> void:
    var player := _current_player()
    if player == null:
        _clear_binding()
        return
    var weapon_id := StringName(player.get_meta("combat_weapon_id", &""))
    if weapon_id == CROSSBOW_ID:
        _present_crossbow(player)
        player.set_meta("combat_native_knife_orientation_locked", false)
        return
    if weapon_id == KNIFE_ID:
        _present_knife(player)
        player.set_meta("combat_native_crossbow_orientation_locked", false)
        return
    player.set_meta("combat_native_crossbow_orientation_locked", false)
    player.set_meta("combat_native_knife_orientation_locked", false)

# Public post-IK refresh used by the dual-arm carry owner. The normal process
# pass still owns presentation, but this lets the crossbow follow the right hand
# immediately after CombatCarryHandIK has solved it instead of one frame later.
func refresh_crossbow_from_current_hand(player: CharacterBody3D) -> bool:
    if player == null or not is_instance_valid(player):
        return false
    if StringName(player.get_meta("combat_weapon_id", &"")) != CROSSBOW_ID:
        return false
    var crossbow := player.find_child(CROSSBOW_NODE, true, false) as Node3D
    if crossbow == null or not crossbow.visible:
        return false
    _present_crossbow(player)
    player.set_meta("combat_native_crossbow_post_ik_refresh", true)
    return bool(player.get_meta("combat_native_crossbow_orientation_locked", false))

func _present_crossbow(player: CharacterBody3D) -> void:
    var crossbow := player.find_child(CROSSBOW_NODE, true, false) as Node3D
    if crossbow == null or not crossbow.visible:
        player.set_meta("combat_native_crossbow_orientation_locked", false)
        return
    var grip_runtime := get_node_or_null("/root/CombatWeaponVisualUpgradeRuntime")
    if grip_runtime == null or not grip_runtime.has_method("resolve_right_hand_anchor"):
        player.set_meta("combat_native_crossbow_orientation_locked", false)
        return
    var anchor_variant: Variant = grip_runtime.call("resolve_right_hand_anchor", player)
    if not anchor_variant is Dictionary:
        player.set_meta("combat_native_crossbow_orientation_locked", false)
        return
    var anchor := anchor_variant as Dictionary
    if not bool(anchor.get("found", false)):
        player.set_meta("combat_native_crossbow_orientation_locked", false)
        return
    var hand_transform: Transform3D = anchor.get("transform", Transform3D.IDENTITY)
    var hand_basis := hand_transform.basis.orthonormalized()

    var owner_changed := _bound_player_id != player.get_instance_id() or _bound_crossbow_id != crossbow.get_instance_id()
    if owner_changed or not _crossbow_offset_ready:
        _bound_player_id = player.get_instance_id()
        _bound_crossbow_id = crossbow.get_instance_id()
        _crossbow_hand_offset_local = hand_basis.inverse() * (crossbow.global_position - hand_transform.origin)
        _crossbow_basis_in_hand = hand_basis.inverse() * crossbow.global_transform.basis.orthonormalized()
        _crossbow_offset_ready = true

    var transition := _transition_weight(player)
    var transition_rotation := Vector3(
        deg_to_rad(CROSSBOW_TRANSITION_ROTATION_DEG.x * transition),
        deg_to_rad(CROSSBOW_TRANSITION_ROTATION_DEG.y * transition),
        deg_to_rad(CROSSBOW_TRANSITION_ROTATION_DEG.z * transition)
    )
    var recoil := _shot_recoil_weight(player)
    var recoil_rotation := Vector3(deg_to_rad(CROSSBOW_RECOIL_DEG * recoil), 0.0, 0.0)
    var local_correction := Basis.from_euler(transition_rotation) * Basis.from_euler(recoil_rotation)

    var target_basis := (hand_basis * _crossbow_basis_in_hand * local_correction).orthonormalized()
    var transition_offset := CROSSBOW_TRANSITION_OFFSET_LOCAL * transition
    var target_position := hand_transform.origin + hand_basis * (_crossbow_hand_offset_local + transition_offset)
    crossbow.global_transform = Transform3D(target_basis, target_position)

    var gap_m := crossbow.global_position.distance_to(hand_transform.origin)
    var transitioning := transition > 0.001
    var locked := not transitioning and gap_m <= MAX_CROSSBOW_HAND_REGION_GAP_M
    crossbow.set_meta("combat_native_weapon_presentation_signature", SIGNATURE)
    crossbow.set_meta("combat_native_crossbow_basis_mode", "authored_hand_relative")
    player.set_meta("combat_native_weapon_presentation_signature", SIGNATURE)
    player.set_meta("combat_native_crossbow_basis_mode", "authored_hand_relative")
    player.set_meta("combat_native_crossbow_hand_region_gap_m", gap_m)
    player.set_meta("combat_native_crossbow_orientation_locked", locked)
    player.set_meta("combat_native_crossbow_transition_weight", transition)

func _present_knife(player: CharacterBody3D) -> void:
    var knife := player.find_child(KNIFE_NODE, true, false) as Node3D
    if knife == null or not knife.visible:
        player.set_meta("combat_native_knife_orientation_locked", false)
        return
    if _bound_knife_id != knife.get_instance_id() or not _knife_rest_ready:
        _bound_knife_id = knife.get_instance_id()
        _knife_rest_position = knife.position
        _knife_rest_rotation = knife.rotation
        _knife_rest_ready = true

    var transition := _transition_weight(player)
    knife.position = _knife_rest_position + Vector3(0.07, -0.15, 0.08) * transition
    knife.rotation = _knife_rest_rotation + Vector3(
        deg_to_rad(24.0 * transition),
        deg_to_rad(-14.0 * transition),
        deg_to_rad(34.0 * transition)
    )
    knife.set_meta("combat_native_weapon_presentation_signature", SIGNATURE)
    player.set_meta("combat_native_weapon_presentation_signature", SIGNATURE)
    player.set_meta("combat_native_knife_transition_weight", transition)
    player.set_meta("combat_native_knife_orientation_locked", transition <= 0.001)

func _transition_weight(player: CharacterBody3D) -> float:
    var state := StringName(player.get_meta("combat_weapon_state", &"equipped"))
    if state != &"holstering" and state != &"equipping":
        return 0.0
    var started := int(player.get_meta("combat_weapon_switch_phase_started_ms", 0))
    var end := int(player.get_meta("combat_weapon_switch_phase_end_ms", 0))
    if end <= started:
        return 0.0
    var progress := clampf(float(Time.get_ticks_msec() - started) / float(end - started), 0.0, 1.0)
    return progress if state == &"holstering" else 1.0 - progress

func _shot_recoil_weight(player: CharacterBody3D) -> float:
    var shot_ms := int(player.get_meta("combat_crossbow_last_shot_ms", -100000))
    var age_ms := Time.get_ticks_msec() - shot_ms
    if age_ms < 0 or age_ms > 150:
        return 0.0
    return 1.0 - clampf(float(age_ms) / 150.0, 0.0, 1.0)

func _current_player() -> CharacterBody3D:
    var scene := get_tree().current_scene
    if scene == null:
        return null
    return scene.get_node_or_null("Player") as CharacterBody3D

func _clear_binding() -> void:
    _bound_player_id = 0
    _bound_crossbow_id = 0
    _crossbow_hand_offset_local = Vector3.ZERO
    _crossbow_basis_in_hand = Basis.IDENTITY
    _crossbow_offset_ready = false
    _bound_knife_id = 0
    _knife_rest_position = Vector3.ZERO
    _knife_rest_rotation = Vector3.ZERO
    _knife_rest_ready = false
