extends Node

const CIVILIAN_VEHICLE_VISUAL := preload("res://game/scripts/civilian_vehicle_visual.gd")
const CONTRACT := "midi_civilian_vehicle_style_mix_v1"
const SOURCE_VISUAL_NAME := "ProductionVisual"
const MIX_VISUAL_NAME := "ProductionVisualStyleMix"
const STYLE_COUNT := 3
const TARGET_PREFIXES := ["ParkedCar_", "AmbientTraffic_"]

var _processed_count: int = 0
var _replacement_count: int = 0


func _ready() -> void:
    if not get_tree().node_added.is_connected(_on_node_added):
        get_tree().node_added.connect(_on_node_added)
    call_deferred("_scan_tree")


func _exit_tree() -> void:
    if get_tree() != null and get_tree().node_added.is_connected(_on_node_added):
        get_tree().node_added.disconnect(_on_node_added)


func get_contract() -> Dictionary:
    return {
        "schema": CONTRACT,
        "target": "MidiUrbanLife ambient civilian vehicles",
        "style_count": STYLE_COUNT,
        "styles": ["sedan", "hatchback", "wagon"],
        "movement_owner_unchanged": true,
        "collision_owner_unchanged": true,
        "geography_unchanged": true,
    }


func get_processed_count() -> int:
    return _processed_count


func get_replacement_count() -> int:
    return _replacement_count


func style_for_vehicle_name(name_value: String) -> int:
    var separator: int = name_value.rfind("_")
    if separator >= 0 and separator + 1 < name_value.length():
        var suffix: String = name_value.substr(separator + 1)
        if suffix.is_valid_int():
            return int(suffix) % STYLE_COUNT

    var checksum: int = 0
    for index: int in range(name_value.length()):
        checksum += name_value.unicode_at(index) * (index + 1)
    return checksum % STYLE_COUNT


func apply_to_vehicle(vehicle: Node3D) -> bool:
    if vehicle == null or not is_instance_valid(vehicle):
        return false
    if not _is_target_vehicle(vehicle):
        return false
    if str(vehicle.get_meta("midi_vehicle_style_mix_contract", "")) == CONTRACT:
        return false

    var source_visual: Node3D = vehicle.get_node_or_null(SOURCE_VISUAL_NAME) as Node3D
    if source_visual == null or source_visual.get_script() != CIVILIAN_VEHICLE_VISUAL:
        return false

    var desired_style: int = style_for_vehicle_name(str(vehicle.name))
    var source_style: int = int(source_visual.get("body_style"))
    var replacement: Node3D = vehicle.get_node_or_null(MIX_VISUAL_NAME) as Node3D

    if desired_style != source_style:
        if replacement == null:
            replacement = CIVILIAN_VEHICLE_VISUAL.new()
            replacement.name = MIX_VISUAL_NAME
            replacement.set("paint_color", source_visual.get("paint_color"))
            replacement.set("body_style", desired_style)
            source_visual.visible = false
            vehicle.add_child(replacement)
            _replacement_count += 1
        else:
            replacement.set("body_style", desired_style)
            source_visual.visible = false
    else:
        source_visual.visible = true

    vehicle.set_meta("midi_vehicle_style_mix_contract", CONTRACT)
    vehicle.set_meta("midi_vehicle_style", desired_style)
    vehicle.set_meta("midi_vehicle_style_source", "stable_name_index")
    _processed_count += 1
    return true


func _scan_tree() -> void:
    if get_tree() == null:
        return
    _scan_node(get_tree().root)


func _scan_node(node: Node) -> void:
    if node is Node3D:
        apply_to_vehicle(node as Node3D)
    for child: Node in node.get_children():
        _scan_node(child)


func _on_node_added(node: Node) -> void:
    if not node is Node3D:
        return
    var node_3d: Node3D = node as Node3D
    if _is_target_vehicle(node_3d):
        call_deferred("_apply_if_valid", node_3d)
        return
    if str(node_3d.name) == SOURCE_VISUAL_NAME:
        var parent_vehicle: Node3D = node_3d.get_parent() as Node3D
        if parent_vehicle != null and _is_target_vehicle(parent_vehicle):
            call_deferred("_apply_if_valid", parent_vehicle)


func _apply_if_valid(vehicle: Node3D) -> void:
    if vehicle != null and is_instance_valid(vehicle):
        apply_to_vehicle(vehicle)


func _is_target_vehicle(vehicle: Node3D) -> bool:
    var name_value: String = str(vehicle.name)
    var prefix_match := false
    for prefix: String in TARGET_PREFIXES:
        if name_value.begins_with(prefix):
            prefix_match = true
            break
    if not prefix_match:
        return false

    var ancestor: Node = vehicle.get_parent()
    while ancestor != null:
        if str(ancestor.name) == "MidiUrbanLife":
            return true
        ancestor = ancestor.get_parent()
    return false
