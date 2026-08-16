extends Node
class_name BrusselsSharedAsphaltRuntime

# Reusable authored asphalt presentation for road geometry that is already
# sourced/placed by the OSM corridor builder. This script changes material only:
# no road width, centerline, collision, marking or location-specific detail.

const TEXTURE_SIZE := 256
const TEXTURE_METRES := 3.2
const LOCAL_BASE := Color(0.105, 0.11, 0.115, 1.0)
const MAJOR_BASE := Color(0.075, 0.08, 0.085, 1.0)

var _local_material: StandardMaterial3D
var _major_material: StandardMaterial3D
var _applied_count: int = 0

func _ready() -> void:
    _local_material = _make_asphalt_material(LOCAL_BASE, 0.96, "local")
    _major_material = _make_asphalt_material(MAJOR_BASE, 0.94, "major")
    call_deferred("_apply_when_ready")

func _apply_when_ready() -> void:
    var scene_root: Node = get_parent()
    if scene_root == null:
        return
    for _attempt: int in range(120):
        var roads_root: Node = scene_root.get_node_or_null("BrusselsOSM/GeneratedRoads")
        if roads_root != null:
            _applied_count = apply_to_roads(roads_root)
            print("Grand Bruxelles shared asphalt: applied=%d" % _applied_count)
            return
        await get_tree().process_frame
    push_warning("Grand Bruxelles shared asphalt: GeneratedRoads not available")

func apply_to_roads(roads_root: Node) -> int:
    if roads_root == null:
        return 0
    var changed: int = 0
    for child: Node in roads_root.get_children():
        if not child.name.begins_with("Road_"):
            continue
        var road := child as CSGBox3D
        if road == null:
            continue
        var current := road.material as StandardMaterial3D
        if current == null:
            continue
        # The source builder already distinguishes major roads using a darker
        # flat material. Preserve that classification rather than inferring a
        # new road type from names or geography.
        var major: bool = current.albedo_color.r < 0.09 or str(current.get_meta("asphalt_road_family", "")) == "major"
        road.material = _major_material if major else _local_material
        changed += 1
    return changed

func applied_count() -> int:
    return _applied_count

func local_material() -> StandardMaterial3D:
    return _local_material

func major_material() -> StandardMaterial3D:
    return _major_material

func flat_reference_material(family: String) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    if family == "major":
        material.albedo_color = MAJOR_BASE
        material.roughness = 0.94
    else:
        material.albedo_color = LOCAL_BASE
        material.roughness = 0.96
    material.metallic = 0.0
    return material

func _make_asphalt_material(base: Color, roughness: float, family: String) -> StandardMaterial3D:
    var image := Image.create_empty(TEXTURE_SIZE, TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
    image.fill(base)

    # Broad mineral variation keeps the material readable at gameplay distance
    # without fabricating cracks, patches, lane wear or site-specific repairs.
    const CELL := 16
    const TILE_COUNT := TEXTURE_SIZE / CELL
    for tile_y: int in range(TILE_COUNT):
        for tile_x: int in range(TILE_COUNT):
            var hash_value: int = (tile_x * 41 + tile_y * 67 + tile_x * tile_y * 11) % 17
            var delta: float = (float(hash_value) - 8.0) * 0.0026
            var patch := Color(
                clampf(base.r + delta, 0.0, 1.0),
                clampf(base.g + delta * 1.02, 0.0, 1.0),
                clampf(base.b + delta * 1.05, 0.0, 1.0),
                1.0
            )
            _fill_rect(image, tile_x * CELL, tile_y * CELL, CELL, CELL, patch)

    # Sparse deterministic aggregate flecks. These are generic authored
    # material response, not claims about a particular Brussels road surface.
    for index: int in range(1450):
        var x: int = (index * 73 + index * index * 19) % TEXTURE_SIZE
        var y: int = (index * 131 + index * index * 7) % TEXTURE_SIZE
        var tone: float = 0.020 if index % 3 != 0 else -0.014
        var existing := image.get_pixel(x, y)
        var fleck := Color(
            clampf(existing.r + tone, 0.0, 1.0),
            clampf(existing.g + tone, 0.0, 1.0),
            clampf(existing.b + tone, 0.0, 1.0),
            1.0
        )
        image.set_pixel(x, y, fleck)

    var material := StandardMaterial3D.new()
    material.albedo_color = Color.WHITE
    material.albedo_texture = ImageTexture.create_from_image(image)
    material.roughness = roughness
    material.metallic = 0.0
    material.uv1_triplanar = true
    material.uv1_world_triplanar = true
    material.uv1_scale = Vector3.ONE / TEXTURE_METRES
    material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
    material.set_meta("brussels_material_family", "shared_asphalt")
    material.set_meta("asphalt_road_family", family)
    material.set_meta("procedural_original_asset", true)
    material.set_meta("source_geometry_unchanged", true)
    material.set_meta("authored_pbr_values", true)
    material.set_meta("location_specific_repairs_added", false)
    return material

func _fill_rect(image: Image, x0: int, y0: int, width: int, height: int, color: Color) -> void:
    for y: int in range(y0, mini(y0 + height, image.get_height())):
        for x: int in range(x0, mini(x0 + width, image.get_width())):
            image.set_pixel(x, y, color)
