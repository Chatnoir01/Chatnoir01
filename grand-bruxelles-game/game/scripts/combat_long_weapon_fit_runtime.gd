extends Node

# Corrects the long-weapon silhouette without moving the canonical right-hand grip.
# The authored player has a short two-bone reach, so support-hand geometry must
# stay close enough to the receiver to be physically reachable. The support
# socket and the visible fore-end are always moved together; the hand must never
# be validated against an invisible point in space.

const CBR4_ID := &"cbr4"
const SCT8_ID := &"sct8"
const SUPPORT_SOCKET_NAME := "WeaponSupportGripSocket"
const SIGNATURE := "combat_long_weapon_fit_v3_compact_rear_profile"

# Compact support positions measured from the canonical right-hand grip frame.
# They keep roughly 13-20 cm of forward separation after each weapon's visual
# scale, which is reachable by the production rig while still reading as a
# genuine two-handed hold.
const CBR4_SUPPORT_LOCAL := Vector3(0.0, -0.01, -0.16)
const SCT8_SUPPORT_LOCAL := Vector3(0.0, -0.03, -0.18)

const CBR4_HANDGUARD_SIZE := Vector3(0.19, 0.16, 0.36)
const CBR4_HANDGUARD_POSITION := Vector3(0.0, 0.015, -0.30)
const CBR4_STOCK_BEAM_SIZE := Vector3(0.10, 0.10, 0.18)
const CBR4_STOCK_BEAM_POSITION := Vector3(0.0, -0.04, 0.18)
const CBR4_SHOULDER_PAD_SIZE := Vector3(0.16, 0.22, 0.07)
const CBR4_SHOULDER_PAD_POSITION := Vector3(0.0, -0.06, 0.30)
const CBR4_REAR_EXTENT_M := 0.335

const SCT8_FOREGRIP_SIZE := Vector3(0.18, 0.16, 0.28)
const SCT8_FOREGRIP_POSITION := Vector3(0.0, -0.035, -0.25)
const SCT8_STOCK_NECK_SIZE := Vector3(0.12, 0.13, 0.16)
const SCT8_STOCK_NECK_POSITION := Vector3(0.0, -0.05, 0.14)
const SCT8_STOCK_SIZE := Vector3(0.16, 0.21, 0.20)
const SCT8_STOCK_POSITION := Vector3(0.0, -0.09, 0.27)
const SCT8_REAR_EXTENT_M := 0.37

const SURFACE_EPSILON_M := 0.002

var _holder_id := 0
var _weapon_id: StringName = &""

func _ready() -> void:
    process_priority = 35
    set_process(true)

func _process(_delta: float) -> void:
    var player := _current_player()
    if player == null:
        _holder_id = 0
        _weapon_id = &""
        return
    var weapon_id := StringName(player.get_meta("combat_weapon_id", &""))
    if weapon_id != CBR4_ID and weapon_id != SCT8_ID:
        return
    var holder := player.get_node_or_null("CombatWeaponVisual") as Node3D
    if holder == null:
        return
    if holder.get_instance_id() == _holder_id and weapon_id == _weapon_id and String(holder.get_meta("combat_long_weapon_fit_signature", "")) == SIGNATURE:
        return
    if _apply_fit(holder, weapon_id):
        _holder_id = holder.get_instance_id()
        _weapon_id = weapon_id
        holder.set_meta("combat_long_weapon_fit_signature", SIGNATURE)
        player.set_meta("combat_long_weapon_fit_signature", SIGNATURE)
        player.set_meta("combat_long_weapon_fit_weapon_id", weapon_id)
        player.set_meta("combat_long_weapon_support_surface_locked", bool(holder.get_meta("combat_long_weapon_support_surface_locked", false)))
        player.set_meta("combat_long_weapon_support_surface_name", String(holder.get_meta("combat_long_weapon_support_surface_name", "")))
        player.set_meta("combat_long_weapon_rear_extent_m", float(holder.get_meta("combat_long_weapon_rear_extent_m", 999.0)))

func _apply_fit(holder: Node3D, weapon_id: StringName) -> bool:
    var support := holder.find_child(SUPPORT_SOCKET_NAME, true, false) as Node3D
    if support == null:
        return false

    var support_surface_name := ""
    var rear_extent_m := 999.0
    match weapon_id:
        CBR4_ID:
            support.position = CBR4_SUPPORT_LOCAL
            _fit_box(holder, "CarbineHandguard", CBR4_HANDGUARD_SIZE, CBR4_HANDGUARD_POSITION)
            _fit_box(holder, "CarbineStockBeam", CBR4_STOCK_BEAM_SIZE, CBR4_STOCK_BEAM_POSITION)
            _fit_box(holder, "CarbineShoulderPad", CBR4_SHOULDER_PAD_SIZE, CBR4_SHOULDER_PAD_POSITION)
            support_surface_name = "CarbineHandguard"
            rear_extent_m = CBR4_REAR_EXTENT_M
        SCT8_ID:
            support.position = SCT8_SUPPORT_LOCAL
            _fit_box(holder, "ScatterForegrip", SCT8_FOREGRIP_SIZE, SCT8_FOREGRIP_POSITION)
            _fit_box(holder, "ScatterStockNeck", SCT8_STOCK_NECK_SIZE, SCT8_STOCK_NECK_POSITION)
            _fit_box(holder, "ScatterStock", SCT8_STOCK_SIZE, SCT8_STOCK_POSITION)
            support_surface_name = "ScatterForegrip"
            rear_extent_m = SCT8_REAR_EXTENT_M
        _:
            return false

    holder.set_meta("combat_weapon_support_local_fitted", support.position)
    holder.set_meta("combat_long_weapon_rear_extent_m", rear_extent_m)
    _publish_support_surface_contract(holder, support, support_surface_name)
    return true

func _fit_box(holder: Node3D, node_name: String, size: Vector3, position: Vector3) -> void:
    var instance := holder.find_child(node_name, true, false) as MeshInstance3D
    if instance == null:
        return
    var box := instance.mesh as BoxMesh
    if box != null:
        box.size = size
    instance.position = position

func _publish_support_surface_contract(holder: Node3D, support: Node3D, node_name: String) -> void:
    var surface := holder.find_child(node_name, true, false) as MeshInstance3D
    var locked := false
    var surface_size := Vector3.ZERO
    var surface_position := Vector3.ZERO
    if surface != null and support.get_parent() == surface.get_parent():
        var box := surface.mesh as BoxMesh
        if box != null:
            surface_size = box.size
            surface_position = surface.position
            var half := surface_size * 0.5 + Vector3.ONE * SURFACE_EPSILON_M
            var delta := support.position - surface_position
            locked = absf(delta.x) <= half.x and absf(delta.y) <= half.y and absf(delta.z) <= half.z

    holder.set_meta("combat_long_weapon_support_surface_name", node_name)
    holder.set_meta("combat_long_weapon_support_surface_position", surface_position)
    holder.set_meta("combat_long_weapon_support_surface_size", surface_size)
    holder.set_meta("combat_long_weapon_support_socket_local", support.position)
    holder.set_meta("combat_long_weapon_support_surface_locked", locked)

func _current_player() -> CharacterBody3D:
    var scene := get_tree().current_scene
    if scene == null:
        return null
    return scene.get_node_or_null("Player") as CharacterBody3D
