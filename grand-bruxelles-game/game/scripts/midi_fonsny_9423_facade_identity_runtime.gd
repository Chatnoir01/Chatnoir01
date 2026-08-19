extends Node

const CONTRACT_PATH := "res://data/visual/midi_fonsny_9423_facade_identity.json"
const BLOCK_NAMES := ["FonsnyWingSouth", "FonsnyCentral", "FonsnyWingNorth"]
const CENTRAL_NAME := "FonsnyCentral"
const LEGACY_FRAME_NAME := "VerticalGlassTowerFrame"
const LEGACY_GLASS_NAME := "VerticalGlassTower"
const WINDOW_PREFIX := "Window_"

const SUNSHADE_PROJECTION_M := 0.42
const SUNSHADE_THICKNESS_M := 0.09
const TRANSOM_THICKNESS_M := 0.07
const LATERAL_BAY_FRACTION := 0.32
const BOW_DEPTH_M := 0.42
const BOW_SEGMENTS := 7
const BEVEL_ANGLE_DEG := 18.0

var _ready_complete := false
var _failed := false
var _enabled := true
var _station: Node3D
var _identity_nodes: Array[Node3D] = []
var _legacy_frame: MeshInstance3D
var _legacy_glass: MeshInstance3D
var _legacy_frame_visible := true
var _legacy_glass_visible := true
var _window_count := 0
var _sunshade_count := 0
var _transom_count := 0
var _vertical_bay_count := 0
var _bow_segment_count := 0

func _ready() -> void:
    call_deferred("_bind_when_ready")

func _bind_when_ready() -> void:
    if not _contract_valid():
        _fail("source contract invalid")
        return
    for _attempt: int in range(240):
        await get_tree().process_frame
        var station := get_tree().root.find_child("BruxellesMidiStation", true, false) as Node3D
        if station == null:
            continue
        var blocks: Array[Node3D] = []
        var complete := true
        for block_name: String in BLOCK_NAMES:
            var block := station.get_node_or_null(block_name) as Node3D
            if block == null:
                complete = false
                break
            blocks.append(block)
        if not complete:
            continue
        var central := station.get_node_or_null(CENTRAL_NAME) as Node3D
        if central == null:
            continue
        var legacy_frame := central.get_node_or_null(LEGACY_FRAME_NAME) as MeshInstance3D
        var legacy_glass := central.get_node_or_null(LEGACY_GLASS_NAME) as MeshInstance3D
        if legacy_frame == null or legacy_glass == null:
            continue
        if legacy_frame.mesh == null or legacy_glass.mesh == null:
            continue
        _station = station
        _legacy_frame = legacy_frame
        _legacy_glass = legacy_glass
        _legacy_frame_visible = legacy_frame.visible
        _legacy_glass_visible = legacy_glass.visible
        if not _build_identity(blocks, central):
            _fail("facade identity build failed")
            return
        if _window_count < 300 or _vertical_bay_count != 2 or _bow_segment_count != BOW_SEGMENTS * 2:
            _fail("broad facade contract incomplete")
            return
        set_identity_enabled(true)
        _ready_complete = true
        print("MIDI_FONSNY_9423_FACADE_READY: windows=%d sunshades=%d transoms=%d vertical_bays=%d bow_segments=%d geometry_owner_unchanged=true collisions_added=0" % [_window_count, _sunshade_count, _transom_count, _vertical_bay_count, _bow_segment_count])
        return
    _fail("station frontage nodes unavailable")

func _contract_valid() -> bool:
    if not FileAccess.file_exists(CONTRACT_PATH):
        return false
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONTRACT_PATH))
    if typeof(parsed) != TYPE_DICTIONARY:
        return false
    var contract := parsed as Dictionary
    if str(contract.get("schema", "")) != "grand-bruxelles-visual-source-contract-v1":
        return false
    var source := contract.get("source", {}) as Dictionary
    if int(source.get("urban_id", -1)) != 9423:
        return false
    var authored := contract.get("authored_not_measured", {}) as Dictionary
    if absf(float(authored.get("sunshade_projection_m", -1.0)) - SUNSHADE_PROJECTION_M) > 0.0001:
        return false
    if absf(float(authored.get("lateral_bay_position_fraction_of_existing_central_length", -1.0)) - LATERAL_BAY_FRACTION) > 0.0001:
        return false
    if absf(float(authored.get("bow_depth_m", -1.0)) - BOW_DEPTH_M) > 0.0001:
        return false
    if int(authored.get("bow_segments", -1)) != BOW_SEGMENTS:
        return false
    var hard := contract.get("hard_invariants", {}) as Dictionary
    for key: String in ["urbis_plan_geometry_changed", "building_height_changed", "floor_count_changed", "collision_changed", "new_window_openings_authored", "survey_coordinates_claimed", "realism_complete"]:
        if bool(hard.get(key, true)):
            return false
    return true

func _build_identity(blocks: Array[Node3D], central: Node3D) -> bool:
    _identity_nodes.clear()
    _window_count = 0
    _sunshade_count = 0
    _transom_count = 0
    _vertical_bay_count = 0
    _bow_segment_count = 0
    var aluminium := _aluminium_material()
    for block: Node3D in blocks:
        if not _build_window_register(block, aluminium):
            return false
    return _build_twin_vertical_bays(central)

func _build_window_register(block: Node3D, aluminium: Material) -> bool:
    var windows: Array[MeshInstance3D] = []
    for child: Node in block.get_children():
        if child is MeshInstance3D and str(child.name).begins_with(WINDOW_PREFIX):
            windows.append(child as MeshInstance3D)
    if windows.is_empty():
        return false
    var first_box := windows[0].mesh as BoxMesh
    if first_box == null:
        return false
    var root := Node3D.new()
    root.name = "Urban9423WindowRegister"
    root.set_meta("source", "Urban 9423")
    root.set_meta("placement", "derived_from_existing_window_openings")
    root.set_meta("survey_dimensions_claimed", false)
    block.add_child(root)
    _identity_nodes.append(root)
    var sunshade_positions: Array[Vector3] = []
    var transom_positions: Array[Vector3] = []
    for window: MeshInstance3D in windows:
        var box := window.mesh as BoxMesh
        if box == null:
            return false
        var outer_x := window.position.x + box.size.x * 0.5
        sunshade_positions.append(Vector3(
            outer_x + SUNSHADE_PROJECTION_M * 0.5,
            window.position.y + box.size.y * 0.5 + 0.12,
            window.position.z
        ))
        transom_positions.append(Vector3(
            outer_x + 0.035,
            window.position.y + box.size.y * 0.22,
            window.position.z
        ))
    _add_multimesh(root, "Sunshades", Vector3(SUNSHADE_PROJECTION_M, SUNSHADE_THICKNESS_M, first_box.size.z + 0.12), sunshade_positions, aluminium)
    _add_multimesh(root, "Transoms", Vector3(0.10, TRANSOM_THICKNESS_M, first_box.size.z), transom_positions, aluminium)
    _window_count += windows.size()
    _sunshade_count += sunshade_positions.size()
    _transom_count += transom_positions.size()
    return true

func _build_twin_vertical_bays(central: Node3D) -> bool:
    var brick := central.get_node_or_null("FauquenbergBrick") as MeshInstance3D
    var brick_box := brick.mesh as BoxMesh if brick != null else null
    var frame_box := _legacy_frame.mesh as BoxMesh
    var glass_box := _legacy_glass.mesh as BoxMesh
    if brick_box == null or frame_box == null or glass_box == null:
        return false
    var concrete := _mesh_material(_legacy_frame)
    var glass_block := _mesh_material(_legacy_glass)
    if concrete == null or glass_block == null:
        return false
    var root := Node3D.new()
    root.name = "Urban9423TwinVerticalGlassBlockBays"
    root.set_meta("source", "Urban 9423 no.47 axial-body lateral full-height beveled bays with bowed glass-block wall")
    root.set_meta("placement", "visualization_convention_on_existing_authored_central_body_not_survey_registration")
    root.set_meta("lateral_fraction_authored", LATERAL_BAY_FRACTION)
    root.set_meta("bow_depth_m_authored", BOW_DEPTH_M)
    root.set_meta("bevel_angle_deg_authored", BEVEL_ANGLE_DEG)
    central.add_child(root)
    _identity_nodes.append(root)
    var bay_offset := brick_box.size.z * LATERAL_BAY_FRACTION
    for side: float in [-1.0, 1.0]:
        var bay_center_z := side * bay_offset
        var bay := Node3D.new()
        bay.name = "LateralGlassBlockBay_%s" % ("South" if side < 0.0 else "North")
        root.add_child(bay)
        _build_bowed_glass_wall(bay, bay_center_z, glass_box, glass_block)
        var half_width := glass_box.size.z * 0.5
        var bevel_rad := deg_to_rad(BEVEL_ANGLE_DEG)
        for edge: float in [-1.0, 1.0]:
            var reveal := _add_box(
                bay,
                "BeveledReveal",
                Vector3(0.62, frame_box.size.y, 0.30),
                Vector3(_legacy_frame.position.x + 0.13, _legacy_frame.position.y, bay_center_z + edge * (half_width + 0.14)),
                concrete
            )
            reveal.rotation.y = -edge * bevel_rad
        _vertical_bay_count += 1
    return true

func _build_bowed_glass_wall(parent: Node3D, center_z: float, glass_box: BoxMesh, material: Material) -> void:
    var segment_width := glass_box.size.z / float(BOW_SEGMENTS)
    for index: int in range(BOW_SEGMENTS):
        var u := (float(index) + 0.5) / float(BOW_SEGMENTS) * 2.0 - 1.0
        var local_z := u * glass_box.size.z * 0.5
        var bow_x := BOW_DEPTH_M * (1.0 - u * u)
        var slope := (-2.0 * BOW_DEPTH_M * u) / maxf(glass_box.size.z * 0.5, 0.01)
        var panel := _add_box(
            parent,
            "GlassBlockBow_%02d" % index,
            Vector3(glass_box.size.x, glass_box.size.y, segment_width * 1.06),
            Vector3(_legacy_glass.position.x + bow_x, _legacy_glass.position.y, center_z + local_z),
            material
        )
        panel.rotation.y = atan(slope)
        _bow_segment_count += 1

func _aluminium_material() -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = Color(0.49, 0.515, 0.53, 1.0)
    material.roughness = 0.34
    material.metallic = 0.56
    material.set_meta("source_identity", "Urban 9423 aluminium window frames and sunshades")
    material.set_meta("pbr_values_authored_not_measured", true)
    return material

func _mesh_material(mesh_instance: MeshInstance3D) -> Material:
    if mesh_instance.material_override != null:
        return mesh_instance.material_override
    if mesh_instance.mesh != null:
        return mesh_instance.mesh.material
    return null

func _add_box(parent: Node3D, node_name: String, size: Vector3, position: Vector3, material: Material) -> MeshInstance3D:
    var mesh := BoxMesh.new()
    mesh.size = size
    mesh.material = material
    var instance := MeshInstance3D.new()
    instance.name = node_name
    instance.mesh = mesh
    instance.position = position
    parent.add_child(instance)
    return instance

func _add_multimesh(parent: Node3D, node_name: String, size: Vector3, positions: Array[Vector3], material: Material) -> void:
    var box := BoxMesh.new()
    box.size = size
    box.material = material
    var multi := MultiMesh.new()
    multi.transform_format = MultiMesh.TRANSFORM_3D
    multi.mesh = box
    multi.instance_count = positions.size()
    for index: int in range(positions.size()):
        multi.set_instance_transform(index, Transform3D(Basis.IDENTITY, positions[index]))
    var instance := MultiMeshInstance3D.new()
    instance.name = node_name
    instance.multimesh = multi
    parent.add_child(instance)

func set_identity_enabled(enabled: bool) -> void:
    _enabled = enabled
    for node: Node3D in _identity_nodes:
        node.visible = enabled
    if is_instance_valid(_legacy_frame):
        _legacy_frame.visible = _legacy_frame_visible and not enabled
    if is_instance_valid(_legacy_glass):
        _legacy_glass.visible = _legacy_glass_visible and not enabled

func identity_enabled() -> bool:
    return _enabled

func ready_complete() -> bool:
    return _ready_complete

func failed() -> bool:
    return _failed

func window_count() -> int:
    return _window_count

func vertical_bay_count() -> int:
    return _vertical_bay_count

func bow_segment_count() -> int:
    return _bow_segment_count

func collision_count_added() -> int:
    return 0

func _fail(message: String) -> void:
    _failed = true
    _ready_complete = true
    push_error("Midi Fonsny Urban 9423 facade identity: " + message)
