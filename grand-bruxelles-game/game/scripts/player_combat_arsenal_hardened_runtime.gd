extends "res://game/scripts/player_combat_arsenal_runtime.gd"

# Thin hardening layer over the feature-rich arsenal runtime.
# Keeps the base combat implementation stable while enforcing safe preflight rules.

func equip_weapon(player: CharacterBody3D, weapon_id: StringName) -> bool:
    var equipped := super.equip_weapon(player, weapon_id)
    if equipped:
        # Cadence belongs to the weapon that fired, not the next weapon selected.
        _next_fire_ms = 0
    return equipped

func request_fire(player: CharacterBody3D) -> Dictionary:
    var player_available := player != null and is_instance_valid(player) and player.is_inside_tree()
    var armed := is_armed()
    var camera_available := false
    if player_available and armed:
        camera_available = _player_camera(player) != null
    var preflight := fire_preflight_reason(player_available, armed, camera_available)
    if preflight != &"":
        return {"fired": false, "reason": String(preflight)}
    # Only the base implementation is allowed to consume ammo after preflight passes.
    return super.request_fire(player)

func set_aiming(player: CharacterBody3D, aiming: bool) -> bool:
    if player == null or not is_instance_valid(player) or not is_armed():
        return false
    _aiming = aiming
    player.set_meta("combat_weapon_aiming", aiming)
    _refresh_hud(player)
    return true

static func fire_preflight_reason(player_available: bool, armed: bool, camera_available: bool) -> StringName:
    if not player_available:
        return &"player_unavailable"
    if not armed:
        return &"unarmed"
    if not camera_available:
        return &"camera_unavailable"
    return &""
