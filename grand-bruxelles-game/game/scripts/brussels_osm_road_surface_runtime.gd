extends Node

const MATERIAL_FACTORY := preload("res://game/scripts/brussels_osm_road_surface_material.gd")
const DATA_PATH := "res://data/osm/vertical_slice_01.game.json"
const MAJOR_ROADS := ["primary", "secondary", "tertiary"]
const SOURCE := "OpenStreetMap contributors via Overpass API"
const LICENSE := "ODbL-1.0"

var _roads: Array[CSGBox3D] = []
var _legacy_materials: Dictionary = {}
var _roles: Dictionary = {}
var _materials: Dictionary = {}
var _enhanced_enabled := true
var _ready_complete := false
var _failed := false

func _ready() -> void:
    call_deferred("_apply_when_ready")

func _load_road_classes() -> Dictionary:
    var classes := {}
    if not FileAccess.file_exists(DATA_PATH):
        return classes
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
    if typeof(parsed) != TYPE_DICTIONARY:
        return classes
    for raw: Variant in (parsed as Dictionary).get("roads", []):
        if typeof(raw) != TYPE_DICTIONARY:
            continue
        var road := raw as Dictionary
        classes[int(road.get("osm_id", 0))] = str(road.get("class", ""))
    return classes

func _osm_id_from_name(node_name: String) -> int:
    if not node_name.begins_with("Road_"):
        return 0
    var remainder := node_name.trim_prefix("Road_")
    var separator := remainder.find("_")
    if separator <= 0:
        return 0
    return int(remainder.substr(0, separator))

func _apply_when_ready() -> void:
    var roads_root: Node3D = null
    for _attempt: int in range(180):
        await get_tree().process_frame
        var candidate := get_tree().root.find_child("GeneratedRoads", true, false)
        if candidate is Node3D:
            roads_root = candidate as Node3D
            break
    if roads_root == null:
        push_error("Brussels OSM road surface runtime: GeneratedRoads missing")
        _failed = true
        _ready_complete = true
        return

    var road_classes := _load_road_classes()
    if road_classes.is_empty():
        push_error("Brussels OSM road surface runtime: source road classes missing")
        _failed = true
        _ready_complete = true
        return

    _materials = MATERIAL_FACTORY.create_materials()
    for child: Node in roads_root.get_children():
        if not child is CSGBox3D or not child.name.begins_with("Road_"):
            continue
        var road := child as CSGBox3D
        var osm_id := _osm_id_from_name(str(road.name))
        if osm_id == 0 or not road_classes.has(osm_id):
            push_error("Brussels OSM road surface runtime: unresolved source id for %s" % road.name)
            _failed = true
            _ready_complete = true
            return
        var road_class := str(road_classes[osm_id])
        var role := "major" if road_class in MAJOR_ROADS else "regular"
        var instance_id := road.get_instance_id()
        _roads.append(road)
        _legacy_materials[instance_id] = road.material
        _roles[instance_id] = role
        road.set_meta("osm_id", osm_id)
        road.set_meta("road_class", road_class)
        road.set_meta("source", SOURCE)
        road.set_meta("license", LICENSE)
        road.set_meta("geometry_changed_by_road_surface_runtime", false)

    if _roads.is_empty():
        push_error("Brussels OSM road surface runtime: no production road segments found")
        _failed = true
        _ready_complete = true
        return

    _set_material_state(_enhanced_enabled)
    _ready_complete = true
    print("BRUSSELS_OSM_ROAD_SURFACE_READY: roads=%d materials=2 family=%s source=OSM license=ODbL-1.0 geometry_changed=false" % [_roads.size(), MATERIAL_FACTORY.MATERIAL_FAMILY])

func _set_material_state(enabled: bool) -> void:
    for road: CSGBox3D in _roads:
        if not is_instance_valid(road):
            continue
        var instance_id := road.get_instance_id()
        if enabled:
            road.material = _materials[str(_roles.get(instance_id, "regular"))] as Material
        else:
            road.material = _legacy_materials.get(instance_id) as Material

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

func applied_road_count() -> int:
    return _roads.size() if _ready_complete and not _failed else 0

func shared_material_count() -> int:
    return _materials.size()
