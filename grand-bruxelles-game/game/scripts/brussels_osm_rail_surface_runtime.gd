extends Node

const MATERIAL_FACTORY := preload("res://game/scripts/brussels_osm_rail_surface_material.gd")
const SOURCE := "OpenStreetMap contributors via Overpass API"
const LICENSE := "ODbL-1.0"

var _rails: Array[CSGBox3D] = []
var _legacy_materials: Dictionary = {}
var _enhanced_material: Material
var _enhanced_enabled := true
var _ready_complete := false
var _failed := false

func _ready() -> void:
    call_deferred("_apply_when_ready")

func _apply_when_ready() -> void:
    var rails_root: Node3D = null
    for _attempt: int in range(180):
        await get_tree().process_frame
        var candidate := get_tree().root.find_child("GeneratedRails", true, false)
        if candidate is Node3D:
            rails_root = candidate as Node3D
            break
    if rails_root == null:
        push_error("Brussels OSM rail surface runtime: GeneratedRails missing")
        _failed = true
        _ready_complete = true
        return

    _enhanced_material = MATERIAL_FACTORY.create_material()
    for child: Node in rails_root.get_children():
        if not child is CSGBox3D or not child.name.begins_with("Rail_"):
            continue
        var rail := child as CSGBox3D
        var instance_id := rail.get_instance_id()
        _rails.append(rail)
        _legacy_materials[instance_id] = rail.material
        rail.set_meta("source", SOURCE)
        rail.set_meta("license", LICENSE)
        rail.set_meta("geometry_changed_by_rail_surface_runtime", false)

    if _rails.is_empty():
        push_error("Brussels OSM rail surface runtime: no production Rail_* segments found")
        _failed = true
        _ready_complete = true
        return

    _set_material_state(_enhanced_enabled)
    _ready_complete = true
    print("BRUSSELS_OSM_RAIL_SURFACE_READY: rails=%d materials=1 family=%s source=OSM license=ODbL-1.0 geometry_changed=false" % [_rails.size(), MATERIAL_FACTORY.MATERIAL_FAMILY])

func _set_material_state(enabled: bool) -> void:
    for rail: CSGBox3D in _rails:
        if not is_instance_valid(rail):
            continue
        if enabled:
            rail.material = _enhanced_material
        else:
            rail.material = _legacy_materials.get(rail.get_instance_id()) as Material

func set_enhanced_enabled(enabled: bool) -> void:
    _enhanced_enabled = enabled
    if _ready_complete and not _failed:
        _set_material_state(enabled)

func enhanced_enabled() -> bool:
    return _enhanced_enabled

func ready_complete() -> bool:
    return _ready_complete

func failed() -> bool:
    return _failed

func applied_rail_count() -> int:
    return _rails.size() if _ready_complete and not _failed else 0
