extends Node

# Corrects the long-weapon silhouette without moving the canonical right-hand grip.
# The procedural V3 meshes were technically hand-locked but had stocks long enough
# to run through the avatar's head/shoulder. This owner shortens only rear geometry
# and moves the support socket into reachable fore-end territory.

const CBR4_ID := &"cbr4"
const SCT8_ID := &"sct8"
const SUPPORT_SOCKET_NAME := "WeaponSupportGripSocket"
const SIGNATURE := "combat_long_weapon_fit_v1"

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

func _apply_fit(holder: Node3D, weapon_id: StringName) -> bool:
    var support := holder.find_child(SUPPORT_SOCKET_NAME, true, false) as Node3D
    if support == null:
        return false
    match weapon_id:
        CBR4_ID:
            support.position = Vector3(0.0, -0.01, -0.52)
            _fit_box(holder, "CarbineStockBeam", Vector3(0.10, 0.10, 0.28), Vector3(0.0, -0.04, 0.24))
            _fit_box(holder, "CarbineShoulderPad", Vector3(0.16, 0.24, 0.08), Vector3(0.0, -0.06, 0.42))
        SCT8_ID:
            support.position = Vector3(0.0, -0.03, -0.52)
            _fit_box(holder, "ScatterForegrip", Vector3(0.18, 0.16, 0.30), Vector3(0.0, -0.035, -0.57))
            _fit_box(holder, "ScatterStockNeck", Vector3(0.13, 0.14, 0.22), Vector3(0.0, -0.05, 0.18))
            _fit_box(holder, "ScatterStock", Vector3(0.17, 0.23, 0.30), Vector3(0.0, -0.10, 0.39))
        _:
            return false
    holder.set_meta("combat_weapon_support_local_fitted", support.position)
    return true

func _fit_box(holder: Node3D, node_name: String, size: Vector3, position: Vector3) -> void:
    var instance := holder.find_child(node_name, true, false) as MeshInstance3D
    if instance == null:
        return
    var box := instance.mesh as BoxMesh
    if box != null:
        box.size = size
    instance.position = position

func _current_player() -> CharacterBody3D:
    var scene := get_tree().current_scene
    if scene == null:
        return null
    return scene.get_node_or_null("Player") as CharacterBody3D
