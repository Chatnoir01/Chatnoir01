extends Node

const MATERIAL_FACTORY := preload("res://game/scripts/brussels_osm_sidewalk_surface_material.gd")
const OFFICIAL_MATERIAL_FACTORY := preload("res://game/scripts/brussels_ground_network_official_material.gd")
const EXPECTED_WIDTHS := [1.85, 2.55]
const WIDTH_TOLERANCE := 0.02
const HEIGHT := 0.12
const HEIGHT_TOLERANCE := 0.005
const IXELLES_TARGET_NAME := &"StreetSurfaces_SW"
const IXELLES_PARENT_NAME := &"OfficialIxellesStreetSurfaces"
const IXELLES_ROOT_NAME := &"IxellesDirectMicroSlice"

var _sidewalks: Array[CSGBox3D] = []
var _legacy_materials: Dictionary = {}
var _original_transforms: Dictionary = {}
var _original_sizes: Dictionary = {}
var _material: ShaderMaterial
var _official_sidewalks: Dictionary = {}
var _official_legacy_materials: Dictionary = {}
var _official_material: StandardMaterial3D
var _enhanced_enabled := true
var _ready_complete := false
var _failed := false
var _sidewalk_bind_scheduled := false
var _tearing_down := false

func _ready() -> void:
    _tearing_down = false
    if not get_tree().node_added.is_connected(_on_node_added):
        get_tree().node_added.connect(_on_node_added)
    call_deferred("_schedule_sidewalk_bind")

func _exit_tree() -> void:
    _tearing_down = true
    var tree := get_tree()
    if tree != null and tree.node_added.is_connected(_on_node_added):
        tree.node_added.disconnect(_on_node_added)

func _is_generated_sidewalk(box: CSGBox3D) -> bool:
    if str(box.name).begins_with("Road_"):
        return false
    if absf(box.size.y - HEIGHT) > HEIGHT_TOLERANCE:
        return false
    for expected: float in EXPECTED_WIDTHS:
        if absf(box.size.x - expected) <= WIDTH_TOLERANCE:
            return true
    return false

func _is_generated_roads_root(node: Node) -> bool:
    if not node is Node3D or str(node.name) != "GeneratedRoads":
        return false
    var parent := node.get_parent()
    return parent != null and str(parent.name) == "BrusselsOSM"

func _is_generated_sidewalk_child(node: Node) -> bool:
    if not node is CSGBox3D:
        return false
    var parent := node.get_parent()
    if parent == null or not _is_generated_roads_root(parent):
        return false
    return _is_generated_sidewalk(node as CSGBox3D)

func _ensure_material() -> void:
    if _material == null:
        _material = MATERIAL_FACTORY.create_material()

func _schedule_sidewalk_bind() -> void:
    if _failed or _tearing_down or _sidewalk_bind_scheduled:
        return
    _sidewalk_bind_scheduled = true
    call_deferred("_recover_existing_sidewalks")

func _recover_existing_sidewalks() -> void:
    if _tearing_down or not is_inside_tree():
        _sidewalk_bind_scheduled = false
        return
    var tree: SceneTree = get_tree()
    if tree == null:
        _sidewalk_bind_scheduled = false
        return
    await tree.process_frame
    _sidewalk_bind_scheduled = false
    if _failed or _tearing_down or not is_inside_tree():
        return
    var roots := tree.root.find_children("GeneratedRoads", "Node3D", true, false)
    for candidate: Node in roots:
        if _is_generated_roads_root(candidate):
            _bind_sidewalks_root(candidate as Node3D)
            if _failed:
                return

func _bind_sidewalk(sidewalk: CSGBox3D) -> bool:
    var instance_id := sidewalk.get_instance_id()
    if _legacy_materials.has(instance_id):
        return false
    _ensure_material()
    _sidewalks.append(sidewalk)
    _legacy_materials[instance_id] = sidewalk.material
    _original_transforms[instance_id] = sidewalk.global_transform
    _original_sizes[instance_id] = sidewalk.size
    sidewalk.set_meta("environment_role", "generated_osm_sidewalk")
    sidewalk.set_meta("material_family", MATERIAL_FACTORY.MATERIAL_FAMILY)
    sidewalk.set_meta("placement_provenance", "adjacent_to_existing_osm_road_runtime_convention")
    sidewalk.set_meta("surface_composition_claimed", false)
    sidewalk.set_meta("sidewalk_presence_source_backed", false)
    sidewalk.set_meta("sidewalk_width_source_backed", false)
    sidewalk.set_meta("vertical_profile_source_backed", false)
    sidewalk.set_meta("curb_height_source_backed", false)
    sidewalk.set_meta("geometry_changed_by_sidewalk_surface_runtime", false)
    if _enhanced_enabled:
        sidewalk.material = _material
    return true

func _bind_sidewalks_root(roads_root: Node3D) -> void:
    if _failed:
        return
    var bound_count := 0
    for child: Node in roads_root.get_children():
        if child is CSGBox3D and _is_generated_sidewalk(child as CSGBox3D):
            if _bind_sidewalk(child as CSGBox3D):
                bound_count += 1
    if bound_count == 0:
        return
    _scan_existing_official_sidewalks()
    _set_material_state(_enhanced_enabled)
    _ready_complete = true
    print("BRUSSELS_OSM_SIDEWALK_SURFACE_READY: sidewalks=%d newly_bound=%d materials=1 family=%s source=OSM-adjacent authored-placement license=ODbL-1.0 geometry_changed=false event_driven=true" % [_sidewalks.size(), bound_count, MATERIAL_FACTORY.MATERIAL_FAMILY])

func _on_node_added(node: Node) -> void:
    _register_official_sidewalk(node)
    if _failed:
        return
    if _is_generated_roads_root(node) or _is_generated_sidewalk_child(node):
        _schedule_sidewalk_bind()

func _scan_existing_official_sidewalks() -> void:
    var ixelles := get_tree().root.find_child(str(IXELLES_TARGET_NAME), true, false)
    if ixelles != null:
        _register_official_sidewalk(ixelles)

func _is_reserved_ixelles_sidewalk(node: Node) -> bool:
    if node == null or node.name != IXELLES_TARGET_NAME:
        return false
    var parent := node.get_parent()
    if parent == null or parent.name != IXELLES_PARENT_NAME:
        return false
    var slice_root := parent.get_parent()
    return slice_root != null and slice_root.name == IXELLES_ROOT_NAME

func _register_official_sidewalk(node: Node) -> void:
    # The historical Ixelles LABO mesh has its own authored blue-stone
    # presentation. Its `SW` name comes from legacy cell.street_surfaces.type,
    # not the current Brussels Mobility urbadm_ssw contract. Do not let this
    # generic shared runtime race or overwrite the specialized material owner.
    if _is_reserved_ixelles_sidewalk(node):
        return
    if not node is MeshInstance3D:
        return
    if str(node.name) != "StreetSurfaces_SW" or node.get_parent() == null or str(node.get_parent().name) != "OfficialIxellesStreetSurfaces":
        return
    var instance := node as MeshInstance3D
    var instance_id := instance.get_instance_id()
    if _official_sidewalks.has(instance_id):
        return
    if _official_material == null:
        _official_material = OFFICIAL_MATERIAL_FACTORY.create_material("sidewalk")
    _official_sidewalks[instance_id] = instance
    _official_legacy_materials[instance_id] = instance.material_override
    instance.set_meta("ground_network_provider", OFFICIAL_MATERIAL_FACTORY.PROVIDER_URBIS)
    instance.set_meta("ground_network_presentation_family", OFFICIAL_MATERIAL_FACTORY.MATERIAL_FAMILY)
    instance.set_meta("geometry_changed_by_ground_network_runtime", false)
    if _enhanced_enabled:
        instance.material_override = _official_material
    print("BRUSSELS_OFFICIAL_SIDEWALK_SURFACE_READY: node=%s provider=UrbIS geometry_changed=false license_claimed=false" % instance.name)

func _set_material_state(enabled: bool) -> void:
    for sidewalk: CSGBox3D in _sidewalks:
        if not is_instance_valid(sidewalk):
            continue
        var instance_id := sidewalk.get_instance_id()
        if enabled:
            sidewalk.material = _material
        else:
            sidewalk.material = _legacy_materials.get(instance_id) as Material
    for raw_id: Variant in _official_sidewalks.keys():
        var instance_id := int(raw_id)
        var instance := _official_sidewalks.get(instance_id) as MeshInstance3D
        if instance == null or not is_instance_valid(instance):
            continue
        if enabled:
            instance.material_override = _official_material
        else:
            instance.material_override = _official_legacy_materials.get(instance_id) as Material

func set_enhanced_enabled(enabled: bool) -> void:
    _enhanced_enabled = enabled
    if not _failed:
        _set_material_state(enabled)

func enhanced_enabled() -> bool:
    return _enhanced_enabled

func ready_complete() -> bool:
    return _ready_complete

func failed() -> bool:
    return _failed

func applied_sidewalk_count() -> int:
    return _sidewalks.size() if _ready_complete and not _failed else 0

func shared_material_count() -> int:
    return 1 if _material != null else 0

func official_applied_sidewalk_count() -> int:
    return _official_sidewalks.size()

func official_manages_sidewalk(node: Node) -> bool:
    if node == null or not is_instance_valid(node):
        return false
    return _official_sidewalks.has(node.get_instance_id())

func geometry_unchanged() -> bool:
    for sidewalk: CSGBox3D in _sidewalks:
        if not is_instance_valid(sidewalk):
            return false
        var instance_id := sidewalk.get_instance_id()
        var original_transform: Transform3D = _original_transforms.get(instance_id, Transform3D.IDENTITY)
        var original_size: Vector3 = _original_sizes.get(instance_id, Vector3.ZERO)
        if not sidewalk.global_transform.is_equal_approx(original_transform):
            return false
        if not sidewalk.size.is_equal_approx(original_size):
            return false
    return true
