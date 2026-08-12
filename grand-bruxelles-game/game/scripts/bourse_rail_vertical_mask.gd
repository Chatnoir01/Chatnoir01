extends Node

@export_file("*.json") var data_path: String = "res://data/osm/vertical_slice_01.game.json"
@export var uncertainty_radius_m: float = 120.0

const BOURSE_ANCHOR := Vector2(81.54, -664.58)

var _hidden_nodes: int = 0


func _ready() -> void:
    call_deferred("_apply_mask")


func _legacy_runtime_lacks_vertical_topology() -> bool:
    if not FileAccess.file_exists(data_path):
        push_error("Bourse rail mask OSM data missing: %s" % data_path)
        return false
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(data_path))
    if typeof(parsed) != TYPE_DICTIONARY:
        push_error("Invalid Bourse rail mask OSM data: %s" % data_path)
        return false
    var data := parsed as Dictionary
    if str(data.get("format", "")) != "grand-bruxelles-osm-v1":
        push_error("Unsupported OSM runtime schema for Bourse rail mask")
        return false

    var railways: Array = data.get("railways", []) as Array
    if railways.is_empty():
        return false
    for raw: Variant in railways:
        if typeof(raw) != TYPE_DICTIONARY:
            continue
        var railway := raw as Dictionary
        if (
            railway.has("surface_visible")
            or railway.has("tunnel")
            or railway.has("covered")
            or railway.has("layer")
        ):
            return false
    return true


func _apply_mask() -> void:
    if not _legacy_runtime_lacks_vertical_topology():
        return

    var rails_root := get_node_or_null("../BrusselsOSM/GeneratedRails")
    if rails_root == null:
        push_warning("Bourse rail mask: GeneratedRails not available")
        return

    for child: Node in rails_root.get_children():
        if not child is Node3D:
            continue
        var rail_node := child as Node3D
        var point := Vector2(rail_node.global_position.x, rail_node.global_position.z)
        if point.distance_to(BOURSE_ANCHOR) > uncertainty_radius_m:
            continue
        rail_node.visible = false
        _hidden_nodes += 1

    print(
        "Bourse rail vertical mask: %d legacy rail/sleeper nodes hidden inside %.1f m uncertainty radius" %
        [_hidden_nodes, uncertainty_radius_m]
    )


func diagnostic_hidden_rail_node_count() -> int:
    return _hidden_nodes
