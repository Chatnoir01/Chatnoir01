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
const MATERIAL_OWNER_META := &"shared_sidewalk_material_owner"
const MATERIAL_OWNER_VALUE := "brussels_osm_sidewalk_surface_runtime"

var _sidewalks: Array[CSGBox3D] = []
var _legacy_materials: Dictionary = {}
var _owned_materials: Dictionary = {}
var _original_transforms: Dictionary = {}
var _original_sizes: Dictionary = {}
var _material: ShaderMaterial
var _official_sidewalks: Dictionary = {}
var _official_legacy_materials: Dictionary = {}
var _official_owned_materials: Dictionary = {}
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
    if not get_tree().node_removed.is_connected(_on_node_removed):
        get_tree().node_removed.connect(_on_node_removed)
    call_deferred("_schedule_sidewalk_bind")

func _exit_tree() -> void:
    _tearing_down = true
    var tree := get_tree()
    if tree != null and tree.node_added.is_connected(_on_node_added):
        tree.node_added.disconnect(_on_node_added)
    if tree != null and tree.node_removed.is_connected(_on_node_removed):
        tree.node_removed.disconnect(_on_node_removed)
    _release_material_ownership()

func _owns_material_metadata(node: Node) -> bool:
    return node.has_meta(MATERIAL_OWNER_META) and str(node.get_meta(MATERIAL_OWNER_META, "")) == MATERIAL_OWNER_VALUE

func _has_foreign_material_owner(node: Node) -> bool:
    return node.has_meta(MATERIAL_OWNER_META) and str(node.get_meta(MATERIAL_OWNER_META, "")) != MATERIAL_OWNER_VALUE

func _claim_generated_material(sidewalk: CSGBox3D) -> bool:
    if _has_foreign_material_owner(sidewalk):
        return false
    _ensure_material()
    var instance_id := sidewalk.get_instance_id()
    _owned_materials[instance_id] = _material
    sidewalk.set_meta(MATERIAL_OWNER_META, MATERIAL_OWNER_VALUE)
    sidewalk.set_meta("material_family", MATERIAL_FACTORY.MATERIAL_FAMILY)
    sidewalk.material = _material
    return true

func _claim_official_material(instance: MeshInstance3D) -> bool:
    if _has_foreign_material_owner(instance):
        return false
    if _official_material == null:
        _official_material = OFFICIAL_MATERIAL_FACTORY.create_material("sidewalk")
    var instance_id := instance.get_instance_id()
    _official_owned_materials[instance_id] = _official_material
    instance.set_meta(MATERIAL_OWNER_META, MATERIAL_OWNER_VALUE)
    instance.set_meta("ground_network_presentation_family", OFFICIAL_MATERIAL_FACTORY.MATERIAL_FAMILY)
    instance.material_override = _official_material
    return true

func _release_material_ownership() -> void:
    for sidewalk: CSGBox3D in _sidewalks:
        if sidewalk == null or not is_instance_valid(sidewalk):
            continue
        var instance_id := sidewalk.get_instance_id()
        var owned := _owned_materials.get(instance_id) as Material
        if owned != null and sidewalk.material == owned and _owns_material_metadata(sidewalk):
            sidewalk.material = _legacy_materials.get(instance_id) as Material
            if str(sidewalk.get_meta("material_family", "")) == MATERIAL_FACTORY.MATERIAL_FAMILY:
                sidewalk.remove_meta("material_family")
            sidewalk.remove_meta(MATERIAL_OWNER_META)
    for raw_id: Variant in _official_sidewalks.keys():
        var instance_id := int(raw_id)
        var instance := _official_sidewalks.get(instance_id) as MeshInstance3D
        if instance == null or not is_instance_valid(instance):
            continue
        var owned := _official_owned_materials.get(instance_id) as Material
        if owned != null and instance.material_override == owned and _owns_material_metadata(instance):
            instance.material_override = _official_legacy_materials.get(instance_id) as Material
            if str(instance.get_meta("ground_network_presentation_family", "")) == OFFICIAL_MATERIAL_FACTORY.MATERIAL_FAMILY:
                instance.remove_meta("ground_network_presentation_family")
            instance.remove_meta(MATERIAL_OWNER_META)
    _sidewalks.clear()
    _legacy_materials.clear()
    _owned_materials.clear()
    _original_transforms.clear()
    _original_sizes.clear()
    _official_sidewalks.clear()
    _official_legacy_materials.clear()
    _official_owned_materials.clear()

func _is_generated_sidewalk(box: CSGBox3D) -> bool:
    if str(box.name).begins_with("Road_"):
        return false
    if absf(box.size.y - HEIGHT) > HEIGHT_TOLERANCE:
        return false
    for expected: float in EXPECTED_WIDTHS:
        if absf(box.size.x - expected) <= WIDTH_TOLERANCE:
            return true
    return false

func _is_authoritative_sidewalk_scene(node: Node) -> bool:
    if not node is Node3D or not is_inside_tree():
        return false
    var candidate := node as Node3D
    var tree := get_tree()
    if tree == null:
        return false
    if tree.current_scene == candidate:
        return true
    var parent := candidate.get_parent()
    if parent == tree.root:
        return true
    # Preserve the established synthetic/editor mount: SceneTree.root -> Viewport -> Main.
    # Familiar anchor names nested any deeper never gain shared sidewalk-surface authority.
    return str(candidate.name) == "Main" and parent is Viewport and parent.get_parent() == tree.root

func _is_generated_roads_root(node: Node) -> bool:
    if not node is Node3D or str(node.name) != "GeneratedRoads":
        return false
    var parent := node.get_parent()
    if parent == null or str(parent.name) != "BrusselsOSM":
        return false
    return _is_authoritative_sidewalk_scene(parent.get_parent())

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
    # Discovery can remain recursive; authority is constrained by scene topology.
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
    sidewalk.set_meta("placement_provenance", "adjacent_to_existing_osm_road_runtime_convention")
    sidewalk.set_meta("surface_composition_claimed", false)
    sidewalk.set_meta("sidewalk_presence_source_backed", false)
    sidewalk.set_meta("sidewalk_width_source_backed", false)
    sidewalk.set_meta("vertical_profile_source_backed", false)
    sidewalk.set_meta("curb_height_source_backed", false)
    sidewalk.set_meta("geometry_changed_by_sidewalk_surface_runtime", false)
    if _enhanced_enabled:
        _claim_generated_material(sidewalk)
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

func _on_node_removed(node: Node) -> void:
    if node == null:
        return
    var instance_id := node.get_instance_id()
    if node is CSGBox3D:
        _sidewalks.erase(node)
        _legacy_materials.erase(instance_id)
        _owned_materials.erase(instance_id)
        _original_transforms.erase(instance_id)
        _original_sizes.erase(instance_id)
    if _official_sidewalks.get(instance_id) == node:
        _official_sidewalks.erase(instance_id)
        _official_legacy_materials.erase(instance_id)
        _official_owned_materials.erase(instance_id)

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
    instance.set_meta("geometry_changed_by_ground_network_runtime", false)
    if _enhanced_enabled:
        _claim_official_material(instance)
    print("BRUSSELS_OFFICIAL_SIDEWALK_SURFACE_READY: node=%s provider=UrbIS geometry_changed=false license_claimed=false" % instance.name)

func _set_material_state(enabled: bool) -> void:
    for sidewalk: CSGBox3D in _sidewalks:
        if not is_instance_valid(sidewalk):
            continue
        var instance_id := sidewalk.get_instance_id()
        if enabled:
            if _claim_generated_material(sidewalk):
                _owned_materials[instance_id] = _material
        else:
            var owned := _owned_materials.get(instance_id) as Material
            if owned != null and sidewalk.material == owned and _owns_material_metadata(sidewalk):
                sidewalk.material = _legacy_materials.get(instance_id) as Material
                if str(sidewalk.get_meta("material_family", "")) == MATERIAL_FACTORY.MATERIAL_FAMILY:
                    sidewalk.remove_meta("material_family")
                sidewalk.remove_meta(MATERIAL_OWNER_META)
            _owned_materials.erase(instance_id)
    for raw_id: Variant in _official_sidewalks.keys():
        var instance_id := int(raw_id)
        var instance := _official_sidewalks.get(instance_id) as MeshInstance3D
        if instance == null or not is_instance_valid(instance):
            continue
        if enabled:
            if _claim_official_material(instance):
                _official_owned_materials[instance_id] = _official_material
        else:
            var owned := _official_owned_materials.get(instance_id) as Material
            if owned != null and instance.material_override == owned and _owns_material_metadata(instance):
                instance.material_override = _official_legacy_materials.get(instance_id) as Material
                if str(instance.get_meta("ground_network_presentation_family", "")) == OFFICIAL_MATERIAL_FACTORY.MATERIAL_FAMILY:
                    instance.remove_meta("ground_network_presentation_family")
                instance.remove_meta(MATERIAL_OWNER_META)
            _official_owned_materials.erase(instance_id)

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