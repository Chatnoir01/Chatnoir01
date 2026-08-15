extends RefCounted
class_name BrusselsSharedStreetMaterials

# Shared original procedural materials for already-authorized Brussels surfaces.
# These are art-direction assets, not measured material surveys. They must never
# be used as placement evidence or to alter source geometry.

const PAVING_TILE_METRES := 2.40
const TEXTURE_SIZE := 256
const MODULE_PX := 64
const JOINT_PX := 3

static func pedestrian_paving() -> StandardMaterial3D:
    var image := Image.create_empty(TEXTURE_SIZE, TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
    var joint := Color(0.285, 0.278, 0.262, 1.0)
    var slab_a := Color(0.43, 0.415, 0.385, 1.0)
    var slab_b := Color(0.395, 0.385, 0.36, 1.0)
    image.fill(joint)

    for row: int in range(4):
        for col: int in range(4):
            var inset_x := col * MODULE_PX + JOINT_PX
            var inset_y := row * MODULE_PX + JOINT_PX
            var parity := (row + col) % 2
            var slab := slab_a if parity == 0 else slab_b
            var variation_seed := (row * 17 + col * 29 + row * col * 5) % 7
            var variation := (float(variation_seed) - 3.0) * 0.004
            slab = Color(slab.r + variation, slab.g + variation, slab.b + variation, 1.0)
            _fill_rect(image, inset_x, inset_y, (col + 1) * MODULE_PX - JOINT_PX, (row + 1) * MODULE_PX - JOINT_PX, slab)

    var material := StandardMaterial3D.new()
    material.albedo_color = Color.WHITE
    material.albedo_texture = ImageTexture.create_from_image(image)
    material.roughness = 0.94
    material.metallic = 0.0
    material.uv1_triplanar = true
    material.uv1_world_triplanar = true
    material.uv1_scale = Vector3.ONE / PAVING_TILE_METRES
    material.set_meta("brussels_material_family", "shared_pedestrian_paving")
    material.set_meta("source_geometry_unchanged", true)
    material.set_meta("authored_pattern_scale", true)
    material.set_meta("authored_pbr_values", true)
    material.set_meta("procedural_original_asset", true)
    return material

static func _fill_rect(image: Image, x0: int, y0: int, x1: int, y1: int, color: Color) -> void:
    var min_x := clampi(x0, 0, image.get_width())
    var min_y := clampi(y0, 0, image.get_height())
    var max_x := clampi(x1, 0, image.get_width())
    var max_y := clampi(y1, 0, image.get_height())
    for y: int in range(min_y, max_y):
        for x: int in range(min_x, max_x):
            image.set_pixel(x, y, color)
