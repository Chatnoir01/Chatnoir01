extends Node

## Shared presentation-only pass for generic OSM roofs already built by BrusselsOSM.
## Geometry, placement, depth, collision and source height remain owned by the
## existing city builder. This runtime swaps only the roof material and can restore
## the exact original material for deterministic same-run A/B evidence.

var _enhanced_material: ShaderMaterial
var _enhanced_enabled := true
var _original_materials: Dictionary = {}
var _known_roofs: Dictionary = {}

func _ready() -> void:
    _enhanced_material = BrusselsOsmRoofSurfaceMaterial.create_material()
    get_tree().node_added.connect(_on_node_added)
    call_deferred("_scan_existing")

func _on_node_added(node: Node) -> void:
    if node.name == "GeneratedBuildings":
        call_deferred("_apply_to_root", node)

func _scan_existing() -> void:
    var scene := get_tree().current_scene
    if scene == null:
        return
    var root := _find_named(scene, "GeneratedBuildings")
    if root != null:
        _apply_to_root(root)

func _find_named(root: Node, wanted: String) -> Node:
    if root.name == wanted:
        return root
    for child: Node in root.get_children():
        var found := _find_named(child, wanted)
        if found != null:
            return found
    return null

func _apply_to_root(root: Node) -> void:
    var added := 0
    for child: Node in root.get_children():
        if not child is CSGPolygon3D or not child.name.begins_with("Roof_"):
            continue
        var roof := child as CSGPolygon3D
        var key := roof.get_instance_id()
        if not _original_materials.has(key):
            _original_materials[key] = roof.material
            _known_roofs[key] = roof
            added += 1
        roof.set_meta("generic_osm_roof", true)
        roof.set_meta("geometry_unchanged", true)
        roof.set_meta("material_family", BrusselsOsmRoofSurfaceMaterial.MATERIAL_FAMILY)
        roof.set_meta("source", BrusselsOsmRoofSurfaceMaterial.SOURCE)
        roof.set_meta("license", BrusselsOsmRoofSurfaceMaterial.LICENSE)
        roof.material = _enhanced_material if _enhanced_enabled else _original_materials[key]
    _prune_dead_roofs()
    if added > 0:
        print("BRUSSELS_OSM_ROOF_SURFACE_READY: roofs=%d family=%s source=OSM license=ODbL-1.0 geometry_changed=false" % [_live_roof_count(), BrusselsOsmRoofSurfaceMaterial.MATERIAL_FAMILY])

func set_enhanced_enabled(enabled: bool) -> void:
    _enhanced_enabled = enabled
    _prune_dead_roofs()
    for key: Variant in _known_roofs.keys():
        var roof := _known_roofs[key] as CSGPolygon3D
        if roof == null or not is_instance_valid(roof):
            continue
        roof.material = _enhanced_material if enabled else _original_materials.get(key, roof.material)

func enhanced_enabled() -> bool:
    return _enhanced_enabled

func roof_count() -> int:
    _prune_dead_roofs()
    return _live_roof_count()

func _live_roof_count() -> int:
    var count := 0
    for roof_variant: Variant in _known_roofs.values():
        var roof := roof_variant as CSGPolygon3D
        if roof != null and is_instance_valid(roof):
            count += 1
    return count

func _prune_dead_roofs() -> void:
    for key: Variant in _known_roofs.keys():
        var roof := _known_roofs[key] as CSGPolygon3D
        if roof == null or not is_instance_valid(roof):
            _known_roofs.erase(key)
            _original_materials.erase(key)
