extends Node

const MATERIAL_FACTORY := preload("res://game/scripts/brussels_osm_road_surface_material.gd")
const OFFICIAL_MATERIAL_FACTORY := preload("res://game/scripts/brussels_ground_network_official_material.gd")
const DATA_PATH := "res://data/osm/vertical_slice_01.game.json"
const MAJOR_ROADS := ["primary", "secondary", "tertiary"]
const SOURCE := "OpenStreetMap contributors via Overpass API"
const LICENSE := "ODbL-1.0"

var _roads: Array[CSGBox3D] = []
var _legacy_materials: Dictionary = {}
var _owned_materials: Dictionary = {}
var _roles: Dictionary = {}
var _materials: Dictionary = {}
var _road_classes: Dictionary = {}
var _official_nodes: Dictionary = {}
var _official_legacy_materials: Dictionary = {}
var _official_owned_materials: Dictionary = {}
var _official_roles: Dictionary = {}
var _official_materials: Dictionary = {}
var _enhanced_enabled := true
var _ready_complete := false
var _failed := false
var _road_bind_scheduled := false
var _tearing_down := false

func _ready() -> void:
    _tearing_down = false
    if not get_tree().node_added.is_connected(_on_node_added):
        get_tree().node_added.connect(_on_node_added)
    if not get_tree().node_removed.is_connected(_on_node_removed):
        get_tree().node_removed.connect(_on_node_removed)
    call_deferred("_schedule_road_bind")

func _exit_tree() -> void:
    _tearing_down = true
    var tree := get_tree()
    if tree != null and tree.node_added.is_connected(_on_node_added):
        tree.node_added.disconnect(_on_node_added)
    if tree != null and tree.node_removed.is_connected(_on_node_removed):
        tree.node_removed.disconnect(_on_node_removed)
    _release_material_ownership()

func _release_material_ownership() -> void:
    for road: CSGBox3D in _roads:
        if road == null or not is_instance_valid(road):
            continue
        var instance_id := road.get_instance_id()
        var owned := _owned_materials.get(instance_id) as Material
        if owned != null and road.material == owned:
            road.material = _legacy_materials.get(instance_id) as Material
    for raw_id: Variant in _official_nodes.keys():
        var instance_id := int(raw_id)
        var instance := _official_nodes.get(instance_id) as MeshInstance3D
        if instance == null or not is_instance_valid(instance):
            continue
        var owned := _official_owned_materials.get(instance_id) as Material
        if owned != null and instance.material_override == owned:
            instance.material_override = _official_legacy_materials.get(instance_id) as Material
        _clear_official_presentation_claim(instance)
    _roads.clear()
    _legacy_materials.clear()
    _owned_materials.clear()
    _roles.clear()
    _official_nodes.clear()
    _official_legacy_materials.clear()
    _official_owned_materials.clear()
    _official_roles.clear()

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

func _ensure_road_classes() -> bool:
    if not _road_classes.is_empty():
        return true
    _road_classes = _load_road_classes()
    if not _road_classes.is_empty():
        return true
    push_error("Brussels OSM road surface runtime: source road classes missing")
    _failed = true
    _ready_complete = true
    return false

func _ensure_road_materials() -> void:
    if _materials.is_empty():
        _materials = MATERIAL_FACTORY.create_materials()

func _osm_id_from_name(node_name: String) -> int:
    if not node_name.begins_with("Road_"):
        return 0
    var remainder := node_name.trim_prefix("Road_")
    var separator := remainder.find("_")
    if separator <= 0:
        return 0
    return int(remainder.substr(0, separator))

func _is_generated_roads_root(node: Node) -> bool:
    if not node is Node3D or str(node.name) != "GeneratedRoads":
        return false
    var parent := node.get_parent()
    return parent != null and str(parent.name) == "BrusselsOSM"

func _is_generated_road_child(node: Node) -> bool:
    if not node is CSGBox3D or not str(node.name).begins_with("Road_"):
        return false
    var parent := node.get_parent()
    return parent != null and _is_generated_roads_root(parent)

func _schedule_road_bind() -> void:
    if _failed or _tearing_down or _road_bind_scheduled:
        return
    _road_bind_scheduled = true
    call_deferred("_recover_existing_roads")

func _recover_existing_roads() -> void:
    if _tearing_down or not is_inside_tree():
        _road_bind_scheduled = false
        return
    var tree: SceneTree = get_tree()
    if tree == null:
        _road_bind_scheduled = false
        return
    await tree.process_frame
    _road_bind_scheduled = false
    if _failed or _tearing_down or not is_inside_tree():
        return
    var roots := tree.root.find_children("GeneratedRoads", "Node3D", true, false)
    for candidate: Node in roots:
        if _is_generated_roads_root(candidate):
            _bind_roads_root(candidate as Node3D)
            if _failed:
                return

func _bind_road(road: CSGBox3D) -> bool:
    var instance_id := road.get_instance_id()
    if _legacy_materials.has(instance_id):
        return false
    if not _ensure_road_classes():
        return false
    var osm_id := _osm_id_from_name(str(road.name))
    if osm_id == 0 or not _road_classes.has(osm_id):
        push_error("Brussels OSM road surface runtime: unresolved source id for %s" % road.name)
        _failed = true
        _ready_complete = true
        return false
    _ensure_road_materials()
    var road_class := str(_road_classes[osm_id])
    var role := "major" if road_class in MAJOR_ROADS else "regular"
    _roads.append(road)
    _legacy_materials[instance_id] = road.material
    _roles[instance_id] = role
    road.set_meta("osm_id", osm_id)
    road.set_meta("road_class", road_class)
    road.set_meta("source", SOURCE)
    road.set_meta("license", LICENSE)
    road.set_meta("geometry_changed_by_road_surface_runtime", false)
    return true

func _bind_roads_root(roads_root: Node3D) -> void:
    if _failed:
        return
    var bound_count := 0
    for child: Node in roads_root.get_children():
        if child is CSGBox3D and child.name.begins_with("Road_"):
            if _bind_road(child as CSGBox3D):
                bound_count += 1
            if _failed:
                return
    if bound_count == 0:
        return

    _scan_existing_official_surfaces()
    _set_material_state(_enhanced_enabled)
    _ready_complete = true
    print("BRUSSELS_OSM_ROAD_SURFACE_READY: roads=%d newly_bound=%d materials=2 family=%s source=OSM license=ODbL-1.0 geometry_changed=false event_driven=true" % [_roads.size(), bound_count, MATERIAL_FACTORY.MATERIAL_FAMILY])

func _ensure_official_materials() -> void:
    if not _official_materials.is_empty():
        return
    _official_materials = {
        "road": OFFICIAL_MATERIAL_FACTORY.create_material("road"),
        "street_surface": OFFICIAL_MATERIAL_FACTORY.create_material("street_surface"),
    }

func _on_node_added(node: Node) -> void:
    _register_official_surface(node)
    if _failed:
        return
    if _is_generated_roads_root(node) or _is_generated_road_child(node):
        _schedule_road_bind()

func _on_node_removed(node: Node) -> void:
    var instance_id := node.get_instance_id()
    if node is CSGBox3D:
        _roads.erase(node)
        _legacy_materials.erase(instance_id)
        _owned_materials.erase(instance_id)
        _roles.erase(instance_id)
    if node is MeshInstance3D and _official_nodes.has(instance_id):
        _official_nodes.erase(instance_id)
        _official_legacy_materials.erase(instance_id)
        _official_owned_materials.erase(instance_id)
        _official_roles.erase(instance_id)

func _scan_existing_official_surfaces() -> void:
    var ixelles := get_tree().root.find_child("StreetSurfaces_S", true, false)
    if ixelles != null:
        _register_official_surface(ixelles)
    var jette := get_tree().root.find_child("JetteOfficialStreetSurfaces", true, false)
    if jette != null:
        _register_official_surface(jette)

func _register_official_surface(node: Node) -> void:
    if not node is MeshInstance3D:
        return
    var role := ""
    if str(node.name) == "StreetSurfaces_S" and node.get_parent() != null and str(node.get_parent().name) == "OfficialIxellesStreetSurfaces":
        role = "road"
    elif str(node.name) == "JetteOfficialStreetSurfaces":
        role = "street_surface"
    if role.is_empty():
        return

    var instance := node as MeshInstance3D
    var instance_id := instance.get_instance_id()
    if _official_nodes.has(instance_id):
        return
    _ensure_official_materials()
    _official_nodes[instance_id] = instance
    _official_legacy_materials[instance_id] = instance.material_override
    _official_roles[instance_id] = role
    instance.set_meta("ground_network_provider", OFFICIAL_MATERIAL_FACTORY.PROVIDER_URBIS)
    instance.set_meta("geometry_changed_by_ground_network_runtime", false)
    if _enhanced_enabled:
        var owned := _official_materials[role] as Material
        _official_owned_materials[instance_id] = owned
        instance.material_override = owned
        instance.set_meta("ground_network_presentation_family", OFFICIAL_MATERIAL_FACTORY.MATERIAL_FAMILY)
    print("BRUSSELS_OFFICIAL_ROAD_SURFACE_READY: node=%s role=%s provider=UrbIS geometry_changed=false license_claimed=false" % [instance.name, role])

func _clear_official_presentation_claim(instance: MeshInstance3D) -> void:
    if str(instance.get_meta("ground_network_presentation_family", "")) == OFFICIAL_MATERIAL_FACTORY.MATERIAL_FAMILY:
        instance.remove_meta("ground_network_presentation_family")

func _road_material_can_be_mutated(road: CSGBox3D, instance_id: int) -> bool:
    var legacy := _legacy_materials.get(instance_id) as Material
    var owned := _owned_materials.get(instance_id) as Material
    var current := road.material
    if current == legacy or (owned != null and current == owned):
        return true
    _owned_materials.erase(instance_id)
    return false

func _official_material_can_be_mutated(instance: MeshInstance3D, instance_id: int) -> bool:
    var legacy := _official_legacy_materials.get(instance_id) as Material
    var owned := _official_owned_materials.get(instance_id) as Material
    var current := instance.material_override
    if current == legacy or (owned != null and current == owned):
        return true
    _official_owned_materials.erase(instance_id)
    _clear_official_presentation_claim(instance)
    return false

func _set_material_state(enabled: bool) -> void:
    for road: CSGBox3D in _roads:
        if not is_instance_valid(road):
            continue
        var instance_id := road.get_instance_id()
        if not _road_material_can_be_mutated(road, instance_id):
            continue
        if enabled:
            var owned := _materials[str(_roles.get(instance_id, "regular"))] as Material
            _owned_materials[instance_id] = owned
            road.material = owned
        else:
            road.material = _legacy_materials.get(instance_id) as Material
            _owned_materials.erase(instance_id)
    for raw_id: Variant in _official_nodes.keys():
        var instance_id := int(raw_id)
        var instance := _official_nodes.get(instance_id) as MeshInstance3D
        if instance == null or not is_instance_valid(instance):
            continue
        if not _official_material_can_be_mutated(instance, instance_id):
            continue
        if enabled:
            var owned := _official_materials[str(_official_roles.get(instance_id, "street_surface"))] as Material
            _official_owned_materials[instance_id] = owned
            instance.material_override = owned
            instance.set_meta("ground_network_presentation_family", OFFICIAL_MATERIAL_FACTORY.MATERIAL_FAMILY)
        else:
            instance.material_override = _official_legacy_materials.get(instance_id) as Material
            _official_owned_materials.erase(instance_id)
            _clear_official_presentation_claim(instance)

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

func official_applied_road_count() -> int:
    return _official_nodes.size()
