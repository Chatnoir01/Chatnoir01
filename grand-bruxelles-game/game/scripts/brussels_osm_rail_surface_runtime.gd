extends Node

const MATERIAL_FACTORY := preload("res://game/scripts/brussels_osm_rail_surface_material.gd")
const OFFICIAL_MATERIAL_FACTORY := preload("res://game/scripts/brussels_ground_network_official_material.gd")
const SOURCE := "OpenStreetMap contributors via Overpass API"
const LICENSE := "ODbL-1.0"

var _rails: Array[CSGBox3D] = []
var _legacy_materials: Dictionary = {}
var _enhanced_material: Material
var _official_rails: Dictionary = {}
var _official_legacy_materials: Dictionary = {}
var _official_material: StandardMaterial3D
var _enhanced_enabled := true
var _ready_complete := false
var _failed := false

func _ready() -> void:
    if not get_tree().node_added.is_connected(_on_node_added):
        get_tree().node_added.connect(_on_node_added)
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

    _scan_existing_official_rails()
    _set_material_state(_enhanced_enabled)
    _ready_complete = true
    print("BRUSSELS_OSM_RAIL_SURFACE_READY: rails=%d materials=1 family=%s source=OSM license=ODbL-1.0 geometry_changed=false" % [_rails.size(), MATERIAL_FACTORY.MATERIAL_FAMILY])

func _on_node_added(node: Node) -> void:
    _register_official_rail(node)

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
        instance.material_override = _official_material
    print("BRUSSELS_OFFICIAL_TRAM_RAIL_READY: node=%s provider=UrbIS source_alignment_only=true fabricated_gauge=false geometry_changed=false license_claimed=false" % instance.name)

func _set_material_state(enabled: bool) -> void:
    for rail: CSGBox3D in _rails:
        if not is_instance_valid(rail):
            continue
        if enabled:
            rail.material = _enhanced_material
        else:
            rail.material = _legacy_materials.get(rail.get_instance_id()) as Material
    for raw_id: Variant in _official_rails.keys():
        var instance_id := int(raw_id)
        var instance := _official_rails.get(instance_id) as MeshInstance3D
        if instance == null or not is_instance_valid(instance):
            continue
        if enabled:
            instance.material_override = _official_material
        else:
            instance.material_override = _official_legacy_materials.get(instance_id) as Material

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

func official_applied_rail_count() -> int:
    return _official_rails.size()
