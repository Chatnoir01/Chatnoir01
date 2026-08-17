extends Node

# Shared presentation only for the generic dashed lane markings already authored
# inside OSMCityBuilder/GeneratedRoads. This runtime does not create, move,
# resize or reinterpret any marking and deliberately does not touch Centre-owned
# exact-location markings such as the Fonsny crossing.
const MATERIAL_FAMILY := "brussels_road_paint_presentation_v1"
const SOURCE_GEOMETRY_CHANGED := false
const SOURCE_PHOTOMETRY_CLAIMED := false
const TARGET_WIDTH_M := 0.12
const TARGET_THICKNESS_M := 0.025
const TARGET_MAX_LENGTH_M := 3.5
const SOURCE_CONTEXT := "Belgian road-marking context; Brussels public-space materiality"
const SOURCE_REFERENCES := [
    "https://mobilit.belgium.be/fr/route/conduire/code-de-la-route-violations-et-sanctions",
    "https://urban.brussels/fr/pages/draaiboek-publieke-ruimte-in-het-brussels-hoofdstedelijk-gewest",
]

var _targets: Array[CSGBox3D] = []
var _legacy_materials: Dictionary = {}
var _material: StandardMaterial3D
var _enhanced_enabled := true
var _ready_complete := false
var _failed := false

func _ready() -> void:
    call_deferred("_apply_when_ready")

func _is_generic_lane_dash(node: Node) -> bool:
    if not node is CSGBox3D:
        return false
    var box := node as CSGBox3D
    return (
        absf(box.size.x - TARGET_WIDTH_M) <= 0.001
        and absf(box.size.y - TARGET_THICKNESS_M) <= 0.001
        and box.size.z > 0.0
        and box.size.z <= TARGET_MAX_LENGTH_M + 0.001
    )

func _make_paint_texture() -> ImageTexture:
    const SIZE := 64
    var image := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
    var base := Color(0.91, 0.90, 0.84, 1.0)
    image.fill(base)
    # Low-frequency, deterministic wear variation. This is authored presentation,
    # not a measurement of any individual Brussels marking.
    for tile_y: int in range(8):
        for tile_x: int in range(8):
            var hash_value := (tile_x * 31 + tile_y * 47 + tile_x * tile_y * 5) % 9
            var delta := (float(hash_value) - 4.0) * 0.009
            var patch := Color(
                clampf(base.r + delta, 0.0, 1.0),
                clampf(base.g + delta, 0.0, 1.0),
                clampf(base.b + delta * 0.75, 0.0, 1.0),
                1.0
            )
            image.fill_rect(Rect2i(tile_x * 8, tile_y * 8, 8, 8), patch)
    return ImageTexture.create_from_image(image)

func _make_material() -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = Color.WHITE
    material.albedo_texture = _make_paint_texture()
    material.roughness = 0.78
    material.metallic = 0.0
    material.uv1_triplanar = true
    material.uv1_world_triplanar = true
    material.uv1_scale = Vector3(1.8, 1.8, 1.8)
    material.set_meta("material_family", MATERIAL_FAMILY)
    material.set_meta("source_geometry_changed", SOURCE_GEOMETRY_CHANGED)
    material.set_meta("source_photometry_claimed", SOURCE_PHOTOMETRY_CLAIMED)
    material.set_meta("source_context", SOURCE_CONTEXT)
    material.set_meta("source_references", SOURCE_REFERENCES)
    material.set_meta("procedural_original_asset", true)
    return material

func _apply_when_ready() -> void:
    var roads_root: Node3D = null
    for _attempt: int in range(180):
        await get_tree().process_frame
        var candidate := get_tree().root.find_child("GeneratedRoads", true, false)
        if candidate is Node3D:
            roads_root = candidate as Node3D
            break
    if roads_root == null:
        push_error("Shared Brussels road paint: GeneratedRoads missing")
        _failed = true
        _ready_complete = true
        return

    _material = _make_material()
    for child: Node in roads_root.get_children():
        if not _is_generic_lane_dash(child):
            continue
        var dash := child as CSGBox3D
        var instance_id := dash.get_instance_id()
        _targets.append(dash)
        _legacy_materials[instance_id] = dash.material
        dash.set_meta("road_paint_material_family", MATERIAL_FAMILY)
        dash.set_meta("geometry_changed_by_road_paint_runtime", false)
        dash.set_meta("source_photometry_claimed", false)

    if _targets.is_empty():
        push_error("Shared Brussels road paint: no generic OSM lane dashes found")
        _failed = true
        _ready_complete = true
        return

    _set_material_state(_enhanced_enabled)
    _ready_complete = true
    print("BRUSSELS_SHARED_ROAD_PAINT_READY: dashes=%d family=%s geometry_changed=false photometry_claimed=false" % [_targets.size(), MATERIAL_FAMILY])

func _set_material_state(enabled: bool) -> void:
    for dash: CSGBox3D in _targets:
        if not is_instance_valid(dash):
            continue
        if enabled:
            dash.material = _material
        else:
            dash.material = _legacy_materials.get(dash.get_instance_id()) as Material

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

func applied_marking_count() -> int:
    return _targets.size() if _ready_complete and not _failed else 0
