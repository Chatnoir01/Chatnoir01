extends Node

# LOT 1 companion to CombatWeaponVisualUpgradeRuntime.
# The grip runtime owns the exact hand position; this layer owns a stable,
# player-relative carry orientation so the weapon cannot be geometrically
# attached to hand.r while pointing into the avatar/body or straight at camera.

const SIGNATURE := "combat_weapon_hand_orientation_v1"
const RIGHT_HAND_SOCKET_NAME := "WeaponRightHandGripSocket"
const HAND_LOCK_EPSILON_M := 0.025

func _ready() -> void:
    # CombatWeaponVisualUpgradeRuntime runs at the default priority and first
    # locks the grip. Run afterwards to orient around that same grip.
    process_priority = 100
    set_process(true)

func _process(_delta: float) -> void:
    var scene := get_tree().current_scene
    if scene == null:
        return
    var player := scene.get_node_or_null("Player") as CharacterBody3D
    if player == null:
        return
    var weapon_id := StringName(player.get_meta("combat_weapon_id", &""))
    if weapon_id == &"":
        player.set_meta("combat_weapon_orientation_locked", false)
        return
    var holder := player.get_node_or_null("CombatWeaponVisual") as Node3D
    if holder == null:
        player.set_meta("combat_weapon_orientation_locked", false)
        return
    orient_weapon_from_player(holder, player, weapon_id)

func orient_weapon_from_player(holder: Node3D, player: CharacterBody3D, weapon_id: StringName) -> bool:
    if holder == null or player == null or not is_instance_valid(holder) or not is_instance_valid(player):
        return false
    var grip_runtime := get_node_or_null("/root/CombatWeaponVisualUpgradeRuntime")
    if grip_runtime == null or not grip_runtime.has_method("resolve_right_hand_anchor"):
        player.set_meta("combat_weapon_orientation_locked", false)
        return false
    var anchor_variant: Variant = grip_runtime.call("resolve_right_hand_anchor", player)
    if not anchor_variant is Dictionary:
        player.set_meta("combat_weapon_orientation_locked", false)
        return false
    var anchor := anchor_variant as Dictionary
    if not bool(anchor.get("found", false)):
        player.set_meta("combat_weapon_orientation_locked", false)
        return false
    var hand_transform: Transform3D = anchor.get("transform", Transform3D.IDENTITY)
    var socket := holder.get_node_or_null(RIGHT_HAND_SOCKET_NAME) as Node3D
    if socket == null:
        player.set_meta("combat_weapon_orientation_locked", false)
        return false

    # Local weapon geometry is authored along -Z. Orient that axis from the
    # player frame instead of trusting imported hand-bone axes (which differ
    # between rigs). A slight outward yaw keeps the weapon readable from the
    # production third-person camera while remaining a low-ready carry pose.
    var carry_deg := carry_rotation_degrees(weapon_id)
    holder.global_rotation = player.global_rotation + Vector3(
        deg_to_rad(carry_deg.x),
        deg_to_rad(carry_deg.y),
        deg_to_rad(carry_deg.z)
    )

    # Rotation changes the socket world position. Re-lock it to the hand after
    # orientation so visual readability never reintroduces floating weapons.
    holder.global_position += hand_transform.origin - socket.global_position
    var gap_m := socket.global_position.distance_to(hand_transform.origin)
    var locked := gap_m <= HAND_LOCK_EPSILON_M
    holder.set_meta("combat_weapon_orientation_signature", SIGNATURE)
    holder.set_meta("combat_weapon_orientation_locked", locked)
    holder.set_meta("combat_weapon_carry_rotation_deg", carry_deg)
    player.set_meta("combat_weapon_orientation_locked", locked)
    player.set_meta("combat_weapon_orientation_gap_m", gap_m)
    player.set_meta("combat_weapon_carry_rotation_deg", carry_deg)
    return locked

static func carry_rotation_degrees(weapon_id: StringName) -> Vector3:
    match weapon_id:
        &"bx9":
            return Vector3(-12.0, -18.0, -8.0)
        &"cbr4":
            return Vector3(-10.0, -22.0, -5.0)
        &"sct8":
            return Vector3(-12.0, -24.0, -5.0)
        _:
            return Vector3(-10.0, -18.0, -6.0)

static func minimum_player_view_extent_px(weapon_id: StringName) -> Vector2:
    match weapon_id:
        &"bx9":
            return Vector2(10.0, 12.0)
        &"cbr4":
            return Vector2(24.0, 18.0)
        &"sct8":
            return Vector2(24.0, 18.0)
        _:
            return Vector2(10.0, 10.0)
