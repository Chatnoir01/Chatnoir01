extends Node

const MATERIAL_FACTORY := preload("res://game/scripts/brussels_urbis_finish_material.gd")

const ZONE_SPECS := {
    "jette": {
        "road_node": "JetteOfficialStreetSurfaces",
        "building_node": "JetteOfficialBuildings",
    },
}

var _enhanced_enabled := true
var _applied_zone := ""
var _road: MeshInstance3D
var _buildings: MeshInstance3D
var _road_original_override: Material
var _building_original_override: Material
var _road_transform := Transform3D.IDENTITY
var _building_transform := Transform3D.IDENTITY
var _road_material := MATERIAL_FACTORY.create_road()
var _facade_material := MATERIAL_FACTORY.create_facade()

func _ready() -> void:
    set_process(true)

func _process(_delta: float) -> void:
    if not _applied_zone.is_empty():
        return
    for zone_id in ZONE_SPECS.keys():
        var spec: Dictionary = ZONE_SPECS[zone_id]
        var road_candidate := get_tree().root.find_child(str(spec["road_node"]), true, false)
        var building_candidate := get_tree().root.find_child(str(spec["building_node"]), true, false)
        if road_candidate is MeshInstance3D and building_candidate is MeshInstance3D:
            _bind(zone_id, road_candidate as MeshInstance3D, building_candidate as MeshInstance3D)
            return

func _bind(zone_id: String, road: MeshInstance3D, buildings: MeshInstance3D) -> void:
    _road = road
    _buildings = buildings
    _road_original_override = _road.material_override
    _building_original_override = _buildings.material_override
    _road_transform = _road.global_transform
    _building_transform = _buildings.global_transform
    _applied_zone = zone_id
    _set_material_state(_enhanced_enabled)
    _road.set_meta("finish_family", MATERIAL_FACTORY.MATERIAL_FAMILY)
    _road.set_meta("geometry_source", "UrbIS")
    _road.set_meta("surface_composition_claimed", false)
    _buildings.set_meta("finish_family", MATERIAL_FACTORY.MATERIAL_FAMILY)
    _buildings.set_meta("geometry_source", "UrbIS")
    _buildings.set_meta("building_material_claimed", false)
    print("BRUSSELS_URBIS_FINISH_READY: zone=%s family=%s road=1 buildings=1 geometry_changed=false material_identity_claimed=false" % [zone_id, MATERIAL_FACTORY.MATERIAL_FAMILY])

func _set_material_state(enabled: bool) -> void:
    if not is_instance_valid(_road) or not is_instance_valid(_buildings):
        return
    _road.material_override = _road_material if enabled else _road_original_override
    _buildings.material_override = _facade_material if enabled else _building_original_override

func set_enhanced_enabled(enabled: bool) -> void:
    _enhanced_enabled = enabled
    _set_material_state(enabled)

func enhanced_enabled() -> bool:
    return _enhanced_enabled

func applied_zone() -> String:
    return _applied_zone

func material_family() -> String:
    return MATERIAL_FACTORY.MATERIAL_FAMILY

func geometry_unchanged() -> bool:
    if not is_instance_valid(_road) or not is_instance_valid(_buildings):
        return false
    return _road.global_transform.is_equal_approx(_road_transform) and _buildings.global_transform.is_equal_approx(_building_transform)
