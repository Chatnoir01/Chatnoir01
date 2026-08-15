extends "res://game/scripts/midi_hero_zone.gd"

# Heritage-backed material identity for Bruxelles-Midi / Brussel-Zuid.
# Geometry remains owned by the existing Midi hero zone. Texture scale, colors,
# roughness and block cadence are authored presentation values, not survey data.

const CONCRETE_TEXTURE_METRES := 1.80
const GLASS_BLOCK_TEXTURE_METRES := 1.60

func _make_materials() -> void:
    super._make_materials()
    # The base Fauquenberg texture already carries the sourced brick cadence.
    # Derive low-cost PBR response maps from that exact authored albedo instead
    # of adding unrelated texture detail or changing geometry.
    _apply_surface_response_maps(_brick_yellow, 0.42, 0.91)
    _apply_surface_response_maps(_brick_shadow, 0.38, 0.94)
    _concrete = _architectural_concrete_material()
    _glass_block = _glass_block_material()

func _build_station_entrance() -> void:
    super._build_station_entrance()
    # The heritage inventory explicitly describes the Fonsny/covered-street
    # entrance porch as concrete with long concrete-crossed bays filled with
    # glass blocks. Reuse the existing entrance plane; do not add new massing.
    var entrance := get_node_or_null("MidiMainEntranceFonsny") as Node3D
    if entrance == null:
        return
    var glazing := entrance.get_node_or_null("EntranceGlazing") as MeshInstance3D
    if glazing != null and glazing.mesh != null:
        glazing.mesh.material = _glass_block

func _architectural_concrete_material() -> StandardMaterial3D:
    const SIZE := 128
    var image := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
    var base := Color(0.47, 0.485, 0.475, 1.0)
    image.fill(base)
    # Large, quiet deterministic mineral variation. No high-frequency noise.
    for tile_y: int in range(8):
        for tile_x: int in range(8):
            var hash_value := (tile_x * 37 + tile_y * 61 + tile_x * tile_y * 7) % 11
            var delta := (float(hash_value) - 5.0) * 0.0045
            var patch := Color(base.r + delta, base.g + delta, base.b + delta * 0.8, 1.0)
            _fill_image_rect(image, tile_x * 16, tile_y * 16, (tile_x + 1) * 16, (tile_y + 1) * 16, patch)
    var material := StandardMaterial3D.new()
    material.albedo_color = Color.WHITE
    material.albedo_texture = ImageTexture.create_from_image(image)
    material.roughness = 0.91
    material.metallic = 0.0
    material.uv1_triplanar = true
    material.uv1_world_triplanar = true
    material.uv1_scale = Vector3.ONE / CONCRETE_TEXTURE_METRES
    _apply_surface_response_maps(material, 0.28, 0.90)
    material.set_meta("brussels_material_family", "architectural_concrete")
    material.set_meta("source_identity", "Midi heritage concrete canopy")
    material.set_meta("source_geometry_unchanged", true)
    material.set_meta("authored_pbr_values", true)
    material.set_meta("procedural_original_asset", true)
    return material

func _glass_block_material() -> StandardMaterial3D:
    const WIDTH := 256
    const HEIGHT := 256
    const CELL := 32
    const JOINT := 3
    var image := Image.create_empty(WIDTH, HEIGHT, false, Image.FORMAT_RGBA8)
    var mortar := Color(0.36, 0.39, 0.39, 0.92)
    var glass_a := Color(0.36, 0.49, 0.51, 0.72)
    var glass_b := Color(0.31, 0.44, 0.47, 0.70)
    image.fill(mortar)
    for y: int in range(0, HEIGHT, CELL):
        for x: int in range(0, WIDTH, CELL):
            var parity := ((x / CELL) + (y / CELL)) % 2
            var glass := glass_a if parity == 0 else glass_b
            _fill_image_rect(image, x + JOINT, y + JOINT, x + CELL - JOINT, y + CELL - JOINT, glass)
            # Soft authored centre highlight makes the blocks read as translucent
            # masonry rather than a flat cyan checker at normal distance.
            _fill_image_rect(image, x + 9, y + 9, x + CELL - 9, y + CELL - 9, glass.lightened(0.045))
    var material := StandardMaterial3D.new()
    material.albedo_color = Color.WHITE
    material.albedo_texture = ImageTexture.create_from_image(image)
    material.roughness = 0.28
    material.metallic = 0.0
    material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    material.uv1_triplanar = true
    material.uv1_world_triplanar = true
    material.uv1_scale = Vector3.ONE / GLASS_BLOCK_TEXTURE_METRES
    material.set_meta("brussels_material_family", "glass_block")
    material.set_meta("source_identity", "Midi heritage glass-block bays")
    material.set_meta("source_geometry_unchanged", true)
    material.set_meta("authored_block_cadence", true)
    material.set_meta("authored_pbr_values", true)
    material.set_meta("procedural_original_asset", true)
    return material

func _apply_surface_response_maps(material: StandardMaterial3D, normal_strength: float, base_roughness: float) -> void:
    if material == null or material.albedo_texture == null:
        return
    var source := material.albedo_texture.get_image()
    if source == null or source.is_empty():
        return
    var width := source.get_width()
    var height := source.get_height()
    var normal_image := Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
    var roughness_image := Image.create_empty(width, height, false, Image.FORMAT_RGBA8)

    for y: int in range(height):
        var y0 := maxi(y - 1, 0)
        var y1 := mini(y + 1, height - 1)
        for x: int in range(width):
            var x0 := maxi(x - 1, 0)
            var x1 := mini(x + 1, width - 1)
            var left := _surface_luma(source.get_pixel(x0, y))
            var right := _surface_luma(source.get_pixel(x1, y))
            var up := _surface_luma(source.get_pixel(x, y0))
            var down := _surface_luma(source.get_pixel(x, y1))
            var tangent_normal := Vector3(
                -(right - left) * normal_strength,
                -(down - up) * normal_strength,
                1.0
            ).normalized()
            normal_image.set_pixel(x, y, Color(
                tangent_normal.x * 0.5 + 0.5,
                tangent_normal.y * 0.5 + 0.5,
                tangent_normal.z * 0.5 + 0.5,
                1.0
            ))

            var luminance := _surface_luma(source.get_pixel(x, y))
            var local_roughness := clampf(base_roughness + (0.50 - luminance) * 0.16, 0.68, 1.0)
            roughness_image.set_pixel(x, y, Color(local_roughness, local_roughness, local_roughness, 1.0))

    material.set_meta("photoreal_base_roughness", base_roughness)
    material.normal_enabled = true
    material.normal_texture = ImageTexture.create_from_image(normal_image)
    material.normal_scale = 0.62
    material.roughness = 1.0
    material.roughness_texture = ImageTexture.create_from_image(roughness_image)
    material.set_meta("photoreal_normal_map", true)
    material.set_meta("photoreal_roughness_map", true)
    material.set_meta("pbr_maps_source", "derived_from_existing_authored_albedo")

func _surface_luma(color: Color) -> float:
    return color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722
