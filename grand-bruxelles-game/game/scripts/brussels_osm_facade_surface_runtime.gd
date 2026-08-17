extends Node

const MATERIAL_FACTORY := preload("res://game/scripts/brussels_osm_facade_surface_material.gd")
const EXPECTED_MAX_PALETTE := 6

var _buildings: Array[CSGPolygon3D] = []
var _legacy_materials: Dictionary = {}
var _original_transforms: Dictionary = {}
var _original_polygons: Dictionary = {}
var _original_depths: Dictionary = {}
var _materials: Dictionary = {}
var _enhanced_enabled := true
var _ready_complete := false
var _failed := false
var _hero_replacements_touched := 0

func _ready() -> void:
    call_deferred("_apply_when_ready")

func _palette_key(material: Material) -> String:
    if material is StandardMaterial3D:
        var standard := material as StandardMaterial3D
        var color := standard.albedo_color
        return "%0.4f:%0.4f:%0.4f:%0.4f" % [color.r, color.g, color.b, standard.roughness]
    return ""

func _shared_material_for(material: Material) -> ShaderMaterial:
    var key := _palette_key(material)
    if key.is_empty():
        return null
    if _materials.has(key):
        return _materials[key] as ShaderMaterial
    var standard := material as StandardMaterial3D
    var shared := MATERIAL_FACTORY.create_material(standard.albedo_color, standard.roughness)
    shared.set_meta("legacy_palette_key", key)
    _materials[key] = shared
    return shared

func _apply_when_ready() -> void:
    var buildings_root: Node3D = null
    for _attempt: int in range(180):
        await get_tree().process_frame
        var candidate := get_tree().root.find_child("GeneratedBuildings", true, false)
        if candidate is Node3D:
            buildings_root = candidate as Node3D
            break
    if buildings_root == null:
        push_error("Brussels OSM facade surface runtime: GeneratedBuildings missing")
        _failed = true
        _ready_complete = true
        return

    for child: Node in buildings_root.get_children():
        if not child is CSGPolygon3D or not str(child.name).begins_with("Building_"):
            continue
        var building := child as CSGPolygon3D
        var shared := _shared_material_for(building.material)
        if shared == null:
            push_error("Brussels OSM facade surface runtime: unsupported legacy material for %s" % building.name)
            _failed = true
            _ready_complete = true
            return
        var instance_id := building.get_instance_id()
        _buildings.append(building)
        _legacy_materials[instance_id] = building.material
        _original_transforms[instance_id] = building.global_transform
        _original_polygons[instance_id] = building.polygon.duplicate()
        _original_depths[instance_id] = building.depth
        building.set_meta("environment_role", "generic_osm_building_wall")
        building.set_meta("material_family", MATERIAL_FACTORY.MATERIAL_FAMILY)
        building.set_meta("placement_provenance", "OpenStreetMap contributors via Overpass API")
        building.set_meta("license", "ODbL-1.0")
        building.set_meta("building_material_claimed", false)
        building.set_meta("geometry_changed_by_facade_surface_runtime", false)

    if _buildings.is_empty():
        push_error("Brussels OSM facade surface runtime: no generic production buildings found")
        _failed = true
        _ready_complete = true
        return
    if _materials.size() > EXPECTED_MAX_PALETTE:
        push_error("Brussels OSM facade surface runtime: unexpected legacy palette expansion (%d)" % _materials.size())
        _failed = true
        _ready_complete = true
        return

    _set_material_state(_enhanced_enabled)
    _ready_complete = true
    print("BRUSSELS_OSM_FACADE_SURFACE_READY: buildings=%d materials=%d family=%s source=OSM license=ODbL-1.0 geometry_changed=false material_identity_claimed=false" % [_buildings.size(), _materials.size(), MATERIAL_FACTORY.MATERIAL_FAMILY])

func _set_material_state(enabled: bool) -> void:
    for building: CSGPolygon3D in _buildings:
        if not is_instance_valid(building):
            continue
        var instance_id := building.get_instance_id()
        if enabled:
            var legacy := _legacy_materials.get(instance_id) as Material
            building.material = _shared_material_for(legacy)
        else:
            building.material = _legacy_materials.get(instance_id) as Material

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

func applied_building_count() -> int:
    return _buildings.size() if _ready_complete and not _failed else 0

func shared_material_count() -> int:
    return _materials.size()

func hero_replacement_count() -> int:
    return _hero_replacements_touched

func material_family() -> String:
    return MATERIAL_FACTORY.MATERIAL_FAMILY

func geometry_unchanged() -> bool:
    for building: CSGPolygon3D in _buildings:
        if not is_instance_valid(building):
            return false
        var instance_id := building.get_instance_id()
        var original_transform: Transform3D = _original_transforms.get(instance_id, Transform3D.IDENTITY)
        var original_polygon: PackedVector2Array = _original_polygons.get(instance_id, PackedVector2Array())
        var original_depth: float = float(_original_depths.get(instance_id, -1.0))
        if not building.global_transform.is_equal_approx(original_transform):
            return false
        if building.polygon != original_polygon:
            return false
        if not is_equal_approx(building.depth, original_depth):
            return false
    return true
