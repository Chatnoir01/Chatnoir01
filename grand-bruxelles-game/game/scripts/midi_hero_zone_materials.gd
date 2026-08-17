extends "res://game/scripts/midi_hero_zone.gd"

# Heritage-backed material identity for Bruxelles-Midi / Brussel-Zuid.
# Official UrbIS owns the station building envelope/masses. This layer keeps
# source-informed Fonsny street-level details only; material scale, colors,
# roughness and block cadence remain authored presentation values.

const MIDI_URBIS_ENVELOPE_OWNER := true
const CONCRETE_TEXTURE_METRES := 1.80
const GLASS_BLOCK_TEXTURE_METRES := 1.60
const CORRIDOR_FACADE_DEPTH_RUNTIME := preload("res://game/scripts/corridor_facade_depth_runtime.gd")

func _ready() -> void:
    _make_materials()
    # Inherited ready builds a second hand-authored station complex on top of
    # UrbISMidiExact, so production intentionally keeps only street-level detail.
    _build_station_entrance()
    _build_fonsny_forecourt()
    _build_fonsny_crossing()
    _build_fonsny_street_furniture()
    _build_shelters()
    _build_tram_railings()
    print("Grand Bruxelles hero zone: Bruxelles-Midi UrbIS masses + Fonsny street details active")
    call_deferred("_install_corridor_facade_depth")

func _install_corridor_facade_depth() -> void:
    var scene_root := get_parent()
    if scene_root == null or scene_root.get_node_or_null("CorridorFacadeDepthRuntime") != null:
        return
    var runtime := CORRIDOR_FACADE_DEPTH_RUNTIME.new()
    runtime.name = "CorridorFacadeDepthRuntime"
    scene_root.add_child(runtime)

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

func _architectural_concrete_material() -> StandardMaterial3D:
    const SIZE := 128
    var image := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
    var base := Color(0.47, 0.485, 0.475, 1.0)
    image.fill(base)
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
