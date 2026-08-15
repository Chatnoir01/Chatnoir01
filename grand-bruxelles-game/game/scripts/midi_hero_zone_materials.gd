extends "res://game/scripts/midi_hero_zone.gd"

# Heritage-backed material identity for Bruxelles-Midi / Brussel-Zuid.
# Geometry remains owned by the existing Midi hero zone. Texture scale, colors,
# roughness and block cadence are authored presentation values, not survey data.

const CONCRETE_TEXTURE_METRES := 1.80
const GLASS_BLOCK_TEXTURE_METRES := 1.60

# Fonsny arrival articulation. The heritage inventory documents three long bays
# with concrete cross framing at the access porch. The existing authored glazing
# envelope is retained; exact frame thickness/offset are presentation values.
const FONSNY_FRAME_FACE_X := -14.49
const FONSNY_FRAME_DEPTH := 0.06
const FONSNY_VERTICAL_FRAME_WIDTH := 0.18
const FONSNY_HORIZONTAL_FRAME_HEIGHT := 0.16
const FONSNY_ENTRANCE_SPAN_Z := 18.8
const FONSNY_ENTRANCE_GLAZING_HEIGHT := 3.65

func _make_materials() -> void:
    super._make_materials()
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

    if bool(get_meta("disable_fonsny_three_bay_arrival", false)):
        return
    _build_fonsny_three_bay_arrival(entrance)

func _build_fonsny_three_bay_arrival(entrance: Node3D) -> void:
    var arrival_frame := Node3D.new()
    arrival_frame.name = "FonsnyThreeBayArrivalFrame"
    entrance.add_child(arrival_frame)

    # Three documented long bays: two shallow dividers across the existing
    # 18.8 m authored glazing span. No new entrance width/height is introduced.
    var bay_step := FONSNY_ENTRANCE_SPAN_Z / 3.0
    for divider_index: int in [1, 2]:
        var z := -FONSNY_ENTRANCE_SPAN_Z * 0.5 + bay_step * float(divider_index)
        var divider := _add_box(
            arrival_frame,
            "BayDivider_%d" % divider_index,
            Vector3(FONSNY_FRAME_DEPTH, FONSNY_ENTRANCE_GLAZING_HEIGHT, FONSNY_VERTICAL_FRAME_WIDTH),
            Vector3(FONSNY_FRAME_FACE_X, 2.15, z),
            _concrete
        )
        divider.set_meta("source_fact", "three_long_bays_with_concrete_cross_framing")
        divider.set_meta("authored_dimensions", true)

    # One quiet cross rail makes the documented concrete-cross framing legible
    # without the repeated projecting caps/shadows rejected in #326.
    var rail := _add_box(
        arrival_frame,
        "BayCrossRail",
        Vector3(FONSNY_FRAME_DEPTH, FONSNY_HORIZONTAL_FRAME_HEIGHT, FONSNY_ENTRANCE_SPAN_Z),
        Vector3(FONSNY_FRAME_FACE_X, 2.15, 0.0),
        _concrete
    )
    rail.set_meta("source_fact", "concrete_cross_framing")
    rail.set_meta("authored_dimensions", true)

    # Preserve the existing four authored porch columns exactly. Godot may
    # rename duplicate sibling node names, so identify the already-authored
    # supports by their CylinderMesh and committed local X/height/radius.
    for child in entrance.get_children():
        if not (child is MeshInstance3D):
            continue
        var column := child as MeshInstance3D
        if not _is_authored_fonsny_porch_column(column):
            continue
        column.mesh.material = _concrete
        column.set_meta("source_fact", "polygonal_columns_support_access_porch")
        column.set_meta("geometry_unchanged", true)

func _is_authored_fonsny_porch_column(column: MeshInstance3D) -> bool:
    if not (column.mesh is CylinderMesh):
        return false
    var cylinder := column.mesh as CylinderMesh
    return (
        is_equal_approx(column.position.x, -13.9)
        and is_equal_approx(cylinder.height, 4.25)
        and is_equal_approx(cylinder.top_radius, 0.14)
        and is_equal_approx(cylinder.bottom_radius, 0.14)
    )

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
