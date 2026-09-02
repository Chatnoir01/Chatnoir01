extends Node

const MATERIAL_FACTORY := preload("res://game/scripts/brussels_osm_rail_surface_material.gd")
const OFFICIAL_MATERIAL_FACTORY := preload("res://game/scripts/brussels_ground_network_official_material.gd")
const SOURCE := "OpenStreetMap contributors via Overpass API"
const LICENSE := "ODbL-1.0"

var _rails: Array[CSGBox3D] = []
var _legacy_materials: Dictionary = {}
var _owned_materials: Dictionary = {}
var _original_transforms: Dictionary = {}
var _original_sizes: Dictionary = {}
var _enhanced_material: Material
var _official_rails: Dictionary = {}
var _official_legacy_materials: Dictionary = {}
var _official_owned_materials: Dictionary = {}
var _official_material: StandardMaterial3D
var _enhanced_enabled := true
var _ready_complete := false
var _failed := false
var _rail_bind_scheduled := false
var _tearing_down := false

func _ready() -> void:
    _tearing_down = false
    if not get_tree().node_added.is_connected(_on_node_added):
        get_tree().node_added.connect(_on_node_added)
    if not get_tree().node_removed.is_connected(_on_node_removed):
        get_tree().node_removed.connect(_on_node_removed)
    call_deferred("_schedule_rail_bind")

func _exit_tree() -> void:
    _tearing_down = true
    var tree := get_tree()
    if tree != null and tree.node_added.is_connected(_on_node_added):
        tree.node_added.disconnect(_on_node_added)
    if tree != null and tree.node_removed.is_connected(_on_node_removed):
        tree.node_removed.disconnect(_on_node_removed)
    _release_material_ownership()

func _release_material_ownership() -> void:
    for rail: CSGBox3D in _rails:
        if rail == null or not is_instance_valid(rail):
            continue
        var instance_id := rail.get_instance_id()
        var owned := _owned_materials.get(instance_id) as Material
        if owned != null and rail.material == owned:
            rail.material = _legacy_materials.get(instance_id) as Material
            if str(rail.get_meta("material_family", "")) == MATERIAL_FACTORY.MATERIAL_FAMILY:
                rail.remove_meta("material_family")
    for raw_id: Variant in _official_rails.keys():
        var instance_id := int(raw_id)
        var instance := _official_rails.get(instance_id) as MeshInstance3D
        if instance == null or not is_instance_valid(instance):
            continue
        var owned := _official_owned_materials.get(instance_id) as Material
        if owned != null and instance.material_override == owned:
            instance.material_override = _official_legacy_materials.get(instance_id) as Material
            if str(instance.get_meta("ground_network_presentation_family", "")) == OFFICIAL_MATERIAL_FACTORY.MATERIAL_FAMILY:
                instance.remove_meta("ground_network_presentation_family")
    _rails.clear()
    _legacy_materials.clear()
    _owned_materials.clear()
    _original_transforms.clear()
    _original_sizes.clear()
    _official_rails.clear()
    _official_legacy_materials.clear()
    _official_owned_materials.clear()

func _is_authoritative_rail_scene(node: Node) -> bool:
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
    return str(candidate.name) == "Main" and parent is Viewport and parent.get_parent() == tree.root

func _is_generated_rails_root(node: Node) -> bool:
    if not node is Node3D or str(node.name) != "GeneratedRails":
        return false
    var parent := node.get_parent()
    if parent == null or str(parent.name) != "BrusselsOSM":
        return false
    return _is_authoritative_rail_scene(parent.get_parent())

func _is_generated_rail_child(node: Node) -> bool:
    if not node is CSGBox3D:
        return false
    var name := str(node.name)
    if not name.begins_with("Rail_"):
        return false
    var parent := node.get_parent()
    return parent != null and _is_generated_rails_root(parent)

func _ensure_material() -> void:
    if _enhanced_material == null:
        _enhanced_material = MATERIAL_FACTORY.create_material()

func _schedule_rail_bind() -> void:
    if _failed or _tearing_down or _rail_bind_scheduled:
        return
    _rail_bind_scheduled = true
    call_deferred("_recover_existing_rails")

func _recover_existing_rails() -> void:
    if _tearing_down or not is_inside_tree():
        _rail_bind_scheduled = false
        return
    var tree: SceneTree = get_tree()
    if tree == null:
        _rail_bind_scheduled = false
        return
    await tree.process_frame
    _rail_bind_scheduled = false
    if _failed or _tearing_down or not is_inside_tree():
        return
    var roots := tree.root.find_children("GeneratedRails", "Node3D", true, false)
    for candidate: Node in roots:
        if _is_generated_rails_root(candidate):
            _bind_rails_root(candidate as Node3D)
            if _failed:
                return

func _bind_rail(rail: CSGBox3D) -> bool:
    var instance_id := rail.get_instance_id()
    if _legacy_materials.has(instance_id):
        return false
    _ensure_material()
    _rails.append(rail)
    _legacy_materials[instance_id] = rail.material
    _original_transforms[instance_id] = rail.global_transform
    _original_sizes[instance_id] = rail.size
    rail.set_meta("source", SOURCE)
    rail.set_meta("license", LICENSE)
    rail.set_meta("material_family", MATERIAL_FACTORY.MATERIAL_FAMILY)
    rail.set_meta("placement_source_backed", true)
    rail.set_meta("rail_alignment_source_backed", true)
    rail.set_meta("rail_existence_source_backed", true)
    rail.set_meta("rail_class_source_backed", true)
    rail.set_meta("rail_visibility_source_backed", true)
    rail.set_meta("alloy_source_backed", false)
    rail.set_meta("finish_source_backed", false)
    rail.set_meta("oxidation_source_backed", false)
    rail.set_meta("wear_source_backed", false)
    rail.set_meta("geometry_changed_by_rail_surface_runtime", false)
    if _enhanced_enabled:
        _owned_materials[instance_id] = _enhanced_material
        rail.material = _enhanced_material
    return true

func _bind_rails_root(rails_root: Node3D) -> void:
    if _failed:
        return
    var bound_count := 0
    for child: Node in rails_root.get_children():
        if not child is CSGBox3D:
            continue
        var name := str(child.name)
        if not name.begins_with("Rail_"):
            continue
        if _bind_rail(child as CSGBox3D):
            bound_count += 1
    if bound_count == 0:
        return
    _scan_existing_official_rails()
    _set_material_state(_enhanced_enabled)
    _ready_complete = true
    print("BRUSSELS_OSM_RAIL_SURFACE_READY: rails=%d newly_bound=%d materials=1 family=%s source=OSM license=ODbL-1.0 geometry_changed=false event_driven=true" % [_rails.size(), bound_count, MATERIAL_FACTORY.MATERIAL_FAMILY])

func _on_node_added(node: Node) -> void:
    _register_official_rail(node)
    if _failed:
        return
    if _is_generated_rails_root(node) or _is_generated_rail_child(node):
        _schedule_rail_bind()

func _on_node_removed(node: Node) -> void:
    if node == null or not is_instance_valid(node):
        return
    var instance_id := node.get_instance_id()
    if node is CSGBox3D:
        _rails.erase(node)
        _legacy_materials.erase(instance_id)
        _owned_materials.erase(instance_id)
        _original_transforms.erase(instance_id)
        _original_sizes.erase(instance_id)
    if node is MeshInstance3D:
        _official_rails.erase(instance_id)
        _official_legacy_materials.erase(instance_id)
        _official_owned_materials.erase(instance_id)

func _scan_existing_official_rails() -> void:
    var jette := get_tree().root.find_child("JetteOfficialTramNetwork", true, false)
    if jette != null:
        _register_official_rail(jette)

func _register_official_rail(node: Node) -> void:
    if not node is MeshInstance3D or str(node.name) != "JetteOfficialTramNetwork":
        return
    var instance := node as MeshInstance3D
    var instance_id := instance.get_instance_id()
    if _official_rails.has(instance_id):
        return
    if _official_material == null:
        _official_material = OFFICIAL_MATERIAL_FACTORY.create_material("tram_rail")
    _official_rails[instance_id] = instance
    _official_legacy_materials[instance_id] = instance.material_override
    instance.set_meta("ground_network_provider", OFFICIAL_MATERIAL_FACTORY.PROVIDER_URBIS)
    instance.set_meta("ground_network_presentation_family", OFFICIAL_MATERIAL_FACTORY.MATERIAL_FAMILY)
    instance.set_meta("ground_network_geometry_claim", "source_alignment_only_no_fabricated_dual_rail_gauge")
    instance.set_meta("geometry_changed_by_ground_network_runtime", false)
    if _enhanced_enabled:
        _official_owned_materials[instance_id] = _official_material
        instance.material_override = _official_material
    print("BRUSSELS_OFFICIAL_TRAM_RAIL_READY: node=%s provider=UrbIS source_alignment_only=true fabricated_gauge=false geometry_changed=false license_claimed=false" % instance.name)

func _set_material_state(enabled: bool) -> void:
    for rail: CSGBox3D in _rails:
        if not is_instance_valid(rail):
            continue
        var instance_id := rail.get_instance_id()
        if enabled:
            _owned_materials[instance_id] = _enhanced_material
            rail.material = _enhanced_material
        else:
            var owned := _owned_materials.get(instance_id) as Material
            if owned == null or rail.material == owned:
                rail.material = _legacy_materials.get(instance_id) as Material
            _owned_materials.erase(instance_id)
    for raw_id: Variant in _official_rails.keys():
        var instance_id := int(raw_id)
        var instance := _official_rails.get(instance_id) as MeshInstance3D
        if instance == null or not is_instance_valid(instance):
            continue
        if enabled:
            _official_owned_materials[instance_id] = _official_material
            instance.material_override = _official_material
        else:
            var owned := _official_owned_materials.get(instance_id) as Material
            if owned == null or instance.material_override == owned:
                instance.material_override = _official_legacy_materials.get(instance_id) as Material
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

func applied_rail_count() -> int:
    return _rails.size() if _ready_complete and not _failed else 0

func official_applied_rail_count() -> int:
    return _official_rails.size()

func geometry_unchanged() -> bool:
    for rail: CSGBox3D in _rails:
        if not is_instance_valid(rail):
            return false
        var instance_id := rail.get_instance_id()
        var original_transform: Transform3D = _original_transforms.get(instance_id, Transform3D.IDENTITY)
        var original_size: Vector3 = _original_sizes.get(instance_id, Vector3.ZERO)
        if not rail.global_transform.is_equal_approx(original_transform):
            return false
        if not rail.size.is_equal_approx(original_size):
            return false
    return true
