extends "res://game/scripts/midi_hero_zone.gd"

# Heritage-backed material identity for Bruxelles-Midi / Brussel-Zuid.
# Geometry remains owned by the existing Midi hero zone. Texture scale, colors,
# roughness and authored detail dimensions are presentation values, not survey data.

const CONCRETE_TEXTURE_METRES := 1.80
const GLASS_BLOCK_TEXTURE_METRES := 1.60

var _aluminium_window: StandardMaterial3D

func _make_materials() -> void:
    super._make_materials()
    _concrete = _architectural_concrete_material()
    _glass_block = _glass_block_material()
    _aluminium_window = _anodized_aluminium_window_material()

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

func _add_office_block(parent: Node3D, name: String, local_z: float, length: float, floors: int, glass_tower: bool) -> void:
    super._add_office_block(parent, name, local_z, length, floors, glass_tower)
    var block := parent.get_node_or_null(name) as Node3D
    if block != null:
        _add_aluminium_window_vocabulary(block)

func _add_aluminium_window_vocabulary(block: Node3D) -> void:
    # The heritage inventory states that the Fonsny administrative/postal
    # buildings use aluminium window frames with a fixed lower section,
    # tilting transom and sunshade. Existing window planes determine placement;
    # the thin authored frame/shade dimensions below do not claim survey truth.
    var windows: Array[MeshInstance3D] = []
    for child in block.get_children():
        if child is MeshInstance3D and String(child.name).begins_with("Window_"):
            windows.append(child as MeshInstance3D)
    if windows.is_empty():
        return

    var first_box := windows[0].mesh as BoxMesh
    if first_box == null:
        return
    var window_height := first_box.size.y
    var window_width := first_box.size.z
    var frame_thickness := 0.065
    var frame_depth := 0.10

    var vertical_mesh := BoxMesh.new()
    vertical_mesh.size = Vector3(frame_depth, window_height + 0.10, frame_thickness)
    vertical_mesh.material = _aluminium_window
    var vertical_mm := MultiMesh.new()
    vertical_mm.transform_format = MultiMesh.TRANSFORM_3D
    vertical_mm.mesh = vertical_mesh
    vertical_mm.instance_count = windows.size() * 2
    var vertical_instance := MultiMeshInstance3D.new()
    vertical_instance.name = "AluminiumWindowFrames"
    vertical_instance.multimesh = vertical_mm
    block.add_child(vertical_instance)

    var horizontal_mesh := BoxMesh.new()
    horizontal_mesh.size = Vector3(frame_depth, frame_thickness, window_width + 0.10)
    horizontal_mesh.material = _aluminium_window
    var horizontal_mm := MultiMesh.new()
    horizontal_mm.transform_format = MultiMesh.TRANSFORM_3D
    horizontal_mm.mesh = horizontal_mesh
    horizontal_mm.instance_count = windows.size() * 3
    var horizontal_instance := MultiMeshInstance3D.new()
    horizontal_instance.name = "AluminiumWindowTransoms"
    horizontal_instance.multimesh = horizontal_mm
    block.add_child(horizontal_instance)

    var shade_mesh := BoxMesh.new()
    shade_mesh.size = Vector3(0.38, 0.075, window_width + 0.14)
    shade_mesh.material = _aluminium_window
    var shade_mm := MultiMesh.new()
    shade_mm.transform_format = MultiMesh.TRANSFORM_3D
    shade_mm.mesh = shade_mesh
    shade_mm.instance_count = windows.size()
    var shade_instance := MultiMeshInstance3D.new()
    shade_instance.name = "AluminiumSunshades"
    shade_instance.multimesh = shade_mm
    block.add_child(shade_instance)

    var vi := 0
    var hi := 0
    var si := 0
    for window in windows:
        var box := window.mesh as BoxMesh
        if box == null:
            continue
        var half_width := box.size.z * 0.5
        var half_height := box.size.y * 0.5
        var front_x := window.position.x + 0.075
        vertical_mm.set_instance_transform(vi, Transform3D(Basis.IDENTITY, Vector3(front_x, window.position.y, window.position.z - half_width)))
        vi += 1
        vertical_mm.set_instance_transform(vi, Transform3D(Basis.IDENTITY, Vector3(front_x, window.position.y, window.position.z + half_width)))
        vi += 1
        for offset_y: float in [-half_height, 0.22, half_height]:
            horizontal_mm.set_instance_transform(hi, Transform3D(Basis.IDENTITY, Vector3(front_x, window.position.y + offset_y, window.position.z)))
            hi += 1
        shade_mm.set_instance_transform(si, Transform3D(Basis.IDENTITY, Vector3(window.position.x + 0.24, window.position.y + half_height + 0.11, window.position.z)))
        si += 1

func _anodized_aluminium_window_material() -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = Color(0.49, 0.515, 0.525, 1.0)
    material.roughness = 0.34
    material.metallic = 0.72
    material.set_meta("brussels_material_family", "anodized_aluminium_window")
    material.set_meta("source_identity", "Midi heritage aluminium window frames and sunshades")
    material.set_meta("source_geometry_unchanged", true)
    material.set_meta("authored_detail_dimensions", true)
    material.set_meta("authored_pbr_values", true)
    material.set_meta("procedural_original_asset", true)
    return material

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
