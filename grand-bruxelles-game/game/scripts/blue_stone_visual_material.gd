extends RefCounted

## Shared authored blue-stone presentation family.
## Material identity must be independently source-confirmed at each reuse site.
## Texture/color/roughness/scale below are authored presentation values, not calibrated photometry.

const TEXTURE_SIZE := 256
const AUTHORED_REPEAT_SIZE_M := 1.60

static func _mineral_texture() -> ImageTexture:
    var image := Image.create_empty(TEXTURE_SIZE, TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
    for y: int in range(TEXTURE_SIZE):
        for x: int in range(TEXTURE_SIZE):
            var fine_seed: int = (x * 73 + y * 151 + ((x * y) % 97) * 37) % 997
            var coarse_seed: int = ((x / 16) * 43 + (y / 16) * 71 + ((x + y) / 31) * 19) % 113
            var fine: float = float(fine_seed) / 996.0 - 0.5
            var coarse: float = float(coarse_seed) / 112.0 - 0.5
            var value: float = fine * 0.024 + coarse * 0.060
            var base := Color(0.255, 0.278, 0.296, 1.0)
            image.set_pixel(
                x,
                y,
                Color(
                    clampf(base.r + value * 0.78, 0.0, 1.0),
                    clampf(base.g + value * 0.90, 0.0, 1.0),
                    clampf(base.b + value, 0.0, 1.0),
                    1.0
                )
            )
    return ImageTexture.create_from_image(image)

static func create_paving_material() -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = Color.WHITE
    material.albedo_texture = _mineral_texture()
    material.roughness = 0.88
    material.metallic = 0.0
    material.uv1_triplanar = true
    material.uv1_world_triplanar = true
    material.uv1_scale = Vector3.ONE / AUTHORED_REPEAT_SIZE_M
    material.cull_mode = BaseMaterial3D.CULL_DISABLED
    material.set_meta("source_material_identity", "blue_stone_paving")
    material.set_meta("authored_repeat_size_m", AUTHORED_REPEAT_SIZE_M)
    material.set_meta("authored_presentation_values", true)
    material.set_meta("procedural_original_asset", true)
    material.set_meta("copyrighted_photo_texture_used", false)
    return material

static func create_boundary_material() -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = Color(0.185, 0.205, 0.218, 1.0)
    material.roughness = 0.94
    material.metallic = 0.0
    material.cull_mode = BaseMaterial3D.CULL_DISABLED
    material.set_meta("presentation_boundary_only", true)
    material.set_meta("authored_presentation_values", true)
    return material
