extends Node

# Visual-only presentation for the Rogue/KayKit native crossbow.
# The imported 2H_Crossbow is already parented to handslot.r; this runtime only
# reorients that mesh around the authored right-hand region so it is readable
# from the production third-person camera. It never overrides Skeleton3D bones.

const SIGNATURE := "rogue_native_crossbow_presentation_v1"
const CROSSBOW_ID := &"crossbow"
const CROSSBOW_NODE := "2H_Crossbow"
const CARRY_ROTATION_DEG := Vector3(-12.0, 24.0, 5.0)
const MAX_NODE_ORIGIN_HAND_GAP_M := 0.12

var _bound_player_id := 0
var _bound_crossbow_id := 0
var _hand_region_offset_player := Vector3.ZERO
var _offset_ready := false

func _ready() -> void:
    # Run after the normal hand-orientation layer. That layer ignores native
    # crossbow mode because there is no CombatWeaponVisual holder.
    process_priority = 130
    set_process(true)

func _process(_delta: float) -> void:
    var player := _current_player()
    if player == null:
        _clear_binding()
        return
    if StringName(player.get_meta("combat_weapon_id", &"")) != CROSSBOW_ID:
        player.set_meta("combat_native_crossbow_orientation_locked", false)
        _clear_binding()
        return

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
    var owner_changed := _bound_player_id != player.get_instance_id() or _bound_crossbow_id != crossbow.get_instance_id()
    if owner_changed or not _offset_ready:
        _bound_player_id = player.get_instance_id()
        _bound_crossbow_id = crossbow.get_instance_id()
        _hand_region_offset_player = player.global_transform.basis.inverse() * (crossbow.global_position - hand_transform.origin)
        _offset_ready = true

    var carry_rad := Vector3(
        deg_to_rad(CARRY_ROTATION_DEG.x),
        deg_to_rad(CARRY_ROTATION_DEG.y),
        deg_to_rad(CARRY_ROTATION_DEG.z)
    )
    crossbow.global_rotation = player.global_rotation + carry_rad
    crossbow.global_position = hand_transform.origin + player.global_transform.basis * _hand_region_offset_player

    var gap_m := crossbow.global_position.distance_to(hand_transform.origin)
    var locked := gap_m <= MAX_NODE_ORIGIN_HAND_GAP_M
    crossbow.set_meta("combat_native_crossbow_presentation_signature", SIGNATURE)
    crossbow.set_meta("combat_native_crossbow_carry_rotation_deg", CARRY_ROTATION_DEG)
    player.set_meta("combat_native_crossbow_presentation_signature", SIGNATURE)
    player.set_meta("combat_native_crossbow_carry_rotation_deg", CARRY_ROTATION_DEG)
    player.set_meta("combat_native_crossbow_hand_region_gap_m", gap_m)
    player.set_meta("combat_native_crossbow_orientation_locked", locked)

func _clear_binding() -> void:
    _bound_player_id = 0
    _bound_crossbow_id = 0
    _hand_region_offset_player = Vector3.ZERO
    _offset_ready = false

func _current_player() -> CharacterBody3D:
    var scene := get_tree().current_scene
    if scene == null:
        return null
    return scene.get_node_or_null("Player") as CharacterBody3D
