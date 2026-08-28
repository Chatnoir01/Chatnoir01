extends Node

## Full in-place source-backed replacement of the generic Avenue Fonsny entrance.
## Heritage identity: urban.brussels architectural inventory Urban 9423.
## The official UrbIS station plan remains authoritative. Register heights,
## bay spacing, panel cadence and column placement below are bounded presentation
## conventions, never claimed as survey/LiDAR dimensions.

const IDENTITY_PATH := "res://data/visual/midi_fonsny_full_entrance_identity.json"
const REPLACEMENT_NAME := "EntranceSourceBackedFonsnyPorch"
const VISIBILITY_OWNER_META := "fonsny_visibility_owner"
const VISIBILITY_OWNER_VALUE := "midi_fonsny_full_entrance_runtime"
const CANOPY_SIZE := Vector3(17.8, 0.48, 25.0)
const CANOPY_POSITION := Vector3(-7.0, 4.55, 0.0)
const SUPERSEDED_EXACT := ["EntranceBlueStoneWall", "EntranceGlazing", "EntranceConcreteCanopy", "CanopyMetalEdge"]
const EXISTING_COLUMN_RADIUS := 0.14
const EXISTING_COLUMN_HEIGHT := 4.25
const EXISTING_COLUMN_X := -13.9
const EXISTING_COLUMN_Y := 2.125
const EXISTING_COLUMN_Z := [-9.1, -3.1, 3.1, 9.1]
const MATCH_EPSILON := 0.002
const X_CELLS := 4
const Z_CELLS := 5

var _built := false
var _build_failure := false
var _replacement_enabled := false
var _entrance: Node3D
var _replacement: Node3D
var _superseded: Array[Node3D] = []
var _original_visibility: Dictionary = {}
var _tearing_down := false

func _ready() -> void:
    _tearing_down = false
    call_deferred("_build_when_parent_ready")

func _exit_tree() -> void:
    _tearing_down = true
    _release_owned_replacement()

func _build_when_parent_ready() -> void:
    if _tearing_down or not is_inside_tree():
        return
    var parent_runtime := get_parent()
    for _i in range(120):
        if _tearing_down or not is_inside_tree():
            return
        if parent_runtime != null and parent_runtime.has_method("ready_complete") and parent_runtime.ready_complete():
            break
        var tree: SceneTree = get_tree()
        if tree == null:
            return
        await tree.process_frame
        if _tearing_down or not is_inside_tree():
            return
    if _tearing_down or not is_inside_tree():
        return
    if parent_runtime == null or not parent_runtime.has_method("ready_complete") or not parent_runtime.ready_complete():
        _fail("concrete material mount never became ready")
        return
    if parent_runtime.has_method("identity_failure") and parent_runtime.identity_failure():
        _fail("parent concrete material identity failed")
        return

    var identity := _read_identity()
    if identity.is_empty() or not _identity_allowed(identity):
        _fail("source identity contract invalid")
        return

    var tree: SceneTree = get_tree()
    if tree == null or _tearing_down or not is_inside_tree():
        return
    _entrance = tree.root.find_child("MidiMainEntranceFonsny", true, false) as Node3D
    if _entrance == null:
        _fail("production entrance anchor missing")
        return
    if not _collect_and_validate_superseded():
        return

    var blue_stone := _effective_material(_entrance.get_node_or_null("EntranceBlueStoneWall") as MeshInstance3D)
    var dark_glass := _effective_material(_entrance.get_node_or_null("EntranceGlazing") as MeshInstance3D)
    var concrete := _effective_material(_entrance.get_node_or_null("EntranceConcreteCanopy") as MeshInstance3D)
    var glass_block_source := tree.root.find_child("VerticalGlassTower", true, false) as MeshInstance3D
    var yellow_brick_source := tree.root.find_child("FauquenbergBrick", true, false) as MeshInstance3D
    var glass_block := _effective_material(glass_block_source)
    var yellow_brick := _effective_material(yellow_brick_source)
    if blue_stone == null or dark_glass == null or concrete == null or glass_block == null or yellow_brick == null:
        _fail("production material families unavailable")
        return
    if _tearing_down or not is_inside_tree():
        return

    _replacement = _build_replacement(blue_stone, dark_glass, concrete, glass_block, yellow_brick)
    if _replacement == null:
        _fail("replacement build failed")
        return
    if _tearing_down or not is_inside_tree():
        _release_owned_replacement()
        return
    set_replacement_enabled(true)
    if _build_failure:
        _release_owned_replacement()
        return
    _built = true
    print("MIDI_FONSNY_FULL_ENTRANCE_READY bays=3 canopy_panels=%d polygonal_columns=4 source_urban_id=9423" % [X_CELLS * Z_CELLS])

func _release_owned_replacement() -> void:
    if _replacement != null and is_instance_valid(_replacement):
        set_replacement_enabled(false)
        var replacement_parent := _replacement.get_parent()
        if replacement_parent != null:
            replacement_parent.remove_child(_replacement)
        _replacement.queue_free()
    else:
        _release_superseded_visibility_ownership()
    _replacement = null
    _replacement_enabled = false
    _built = false
    _entrance = null
    _superseded.clear()
    _original_visibility.clear()

func _read_identity() -> Dictionary:
    if not FileAccess.file_exists(IDENTITY_PATH):
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(IDENTITY_PATH))
    if typeof(parsed) != TYPE_DICTIONARY:
        return {}
    return parsed as Dictionary

func _identity_allowed(identity: Dictionary) -> bool:
    if str(identity.get("schema", "")) != "grand-bruxelles-midi-fonsny-full-entrance-v1":
        return false
    var source := identity.get("heritage_source", {}) as Dictionary
    if int(source.get("urban_id", -1)) != 9423:
        return false
    var contract := identity.get("replacement_contract", {}) as Dictionary
    if str(contract.get("scope", "")) != "full_existing_fonsny_entrance_articulation":
        return false
    if not bool(contract.get("replace_existing_objects_in_place", false)):
        return false
    if not bool(contract.get("additive_duplicate_forbidden", false)):
        return false
    if not bool(contract.get("three_registers_required", false)):
        return false
    if not bool(contract.get("polygonal_columns_required", false)):
        return false
    if not bool(contract.get("glass_block_perforated_canopy_required", false)):
        return false
    if bool(contract.get("register_dimensions_are_source_measured", true)):
        return false
    if bool(contract.get("panel_count_is_source_measured", true)):
        return false
    if bool(contract.get("column_positions_are_source_measured", true)):
        return false
    if bool(contract.get("new_station_plan_geometry", true)):
        return false
    return bool(contract.get("urbis_station_plan_authority_preserved", false))

func _collect_and_validate_superseded() -> bool:
    _superseded.clear()
    _original_visibility.clear()
    for node_name in SUPERSEDED_EXACT:
        var node := _entrance.get_node_or_null(node_name) as Node3D
        if node == null:
            _fail("superseded production node missing: %s" % node_name)
            return false
        _superseded.append(node)
    var matched_columns := 0
    for child in _entrance.get_children():
        if _is_existing_entrance_column(child):
            _superseded.append(child as Node3D)
            matched_columns += 1
    if matched_columns != 4:
        _fail("expected 4 production entrance columns by geometry, got %d" % matched_columns)
        return false
    if _superseded.size() != 8:
        _fail("expected 8 superseded entrance objects, got %d" % _superseded.size())
        return false
    var canopy := _entrance.get_node_or_null("EntranceConcreteCanopy") as MeshInstance3D
    if canopy == null or not (canopy.mesh is BoxMesh):
        _fail("production canopy baseline invalid")
        return false
    var canopy_box := canopy.mesh as BoxMesh
    if not canopy_box.size.is_equal_approx(CANOPY_SIZE) or not canopy.position.is_equal_approx(CANOPY_POSITION):
        _fail("production canopy envelope drifted")
        return false
    return true

func _is_existing_entrance_column(node: Node) -> bool:
    if not (node is MeshInstance3D):
        return false
    var instance := node as MeshInstance3D
    if not (instance.mesh is CylinderMesh):
        return false
    var cylinder := instance.mesh as CylinderMesh
    if absf(cylinder.height - EXISTING_COLUMN_HEIGHT) > MATCH_EPSILON:
        return false
    if absf(cylinder.top_radius - EXISTING_COLUMN_RADIUS) > MATCH_EPSILON:
        return false
    if absf(cylinder.bottom_radius - EXISTING_COLUMN_RADIUS) > MATCH_EPSILON:
        return false
    if absf(instance.position.x - EXISTING_COLUMN_X) > MATCH_EPSILON:
        return false
    if absf(instance.position.y - EXISTING_COLUMN_Y) > MATCH_EPSILON:
        return false
    for expected_z in EXISTING_COLUMN_Z:
        if absf(instance.position.z - float(expected_z)) <= MATCH_EPSILON:
            return true
    return false

func _effective_material(instance: MeshInstance3D) -> Material:
    if instance == null:
        return null
    if instance.material_override != null:
        return instance.material_override
    if instance.mesh != null:
        return instance.mesh.material
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

func _add_polygonal_column(parent: Node3D, index: int, position: Vector3, concrete: Material) -> MeshInstance3D:
    var mesh := CylinderMesh.new()
    mesh.top_radius = 0.23
    mesh.bottom_radius = 0.23
    mesh.height = 4.3
    mesh.radial_segments = 6
    mesh.material = concrete
    var instance := MeshInstance3D.new()
    instance.name = "PorchPolygonalColumn_%02d" % index
    instance.mesh = mesh
    instance.position = position
    parent.add_child(instance)
    return instance

func _build_replacement(blue_stone: Material, dark_glass: Material, concrete: Material, glass_block: Material, yellow_brick: Material) -> Node3D:
    if _tearing_down or not is_inside_tree() or _entrance == null or not is_instance_valid(_entrance):
        return null
    if _entrance.get_node_or_null(REPLACEMENT_NAME) != null:
        return null
    var root := Node3D.new()
    root.name = REPLACEMENT_NAME
    root.set_meta("source_urban_id", 9423)
    root.set_meta("source_record", "Gare du Midi et bâtiments annexes")
    root.set_meta("official_station_plan_authority", "UrbIS")
    root.set_meta("register_dimensions_are_visualization_convention", true)
    root.set_meta("canopy_cell_cadence_is_visualization_convention", true)
    root.set_meta("replaces_existing_fonsny_articulation", true)
    _entrance.add_child(root)

    # Register 1 — low base + glazed access.
    _add_box(root, "PorchLowerRegisterBase", Vector3(0.30, 0.65, 20.8), Vector3(-15.34, 0.45, 0.0), blue_stone)
    _add_box(root, "PorchLowerRegisterGlazing", Vector3(0.18, 2.45, 19.2), Vector3(-15.53, 1.65, 0.0), dark_glass)
    _add_box(root, "PorchLowerRegisterLintel", Vector3(0.42, 0.34, 20.8), Vector3(-15.36, 3.02, 0.0), concrete)

    # Register 2 — three long bays, concrete crosswork, glass-block infill.
    var bay_span := 5.35
    var bay_centres := [-6.15, 0.0, 6.15]
    for bay_index: int in range(3):
        var z := float(bay_centres[bay_index])
        _add_box(root, "PorchGlassBlockBay_%02d" % bay_index, Vector3(0.20, 3.55, bay_span), Vector3(-15.50, 4.95, z), glass_block)
        _add_box(root, "PorchBayVerticalCross_%02d" % bay_index, Vector3(0.34, 3.85, 0.26), Vector3(-15.66, 4.95, z), concrete)
        _add_box(root, "PorchBayHorizontalCross_%02d" % bay_index, Vector3(0.34, 0.28, bay_span + 0.12), Vector3(-15.66, 4.95, z), concrete)
    for separator_index: int in range(4):
        var z := -9.25 + float(separator_index) * 6.17
        _add_box(root, "PorchBayPier_%02d" % separator_index, Vector3(0.48, 4.0, 0.48), Vector3(-15.62, 4.95, z), concrete)

    # Register 3 — blind upper register.
    _add_box(root, "PorchBlindUpperRegister", Vector3(0.34, 1.75, 20.8), Vector3(-15.42, 7.72, 0.0), yellow_brick)
    _add_box(root, "PorchUpperConcreteCap", Vector3(0.50, 0.32, 21.2), Vector3(-15.40, 8.72, 0.0), concrete)

    # Vast concrete canopy perforated with glass blocks, constrained to the
    # exact existing production canopy presentation envelope.
    var canopy_root := Node3D.new()
    canopy_root.name = "PorchPerforatedCanopy"
    canopy_root.position = CANOPY_POSITION
    canopy_root.set_meta("preserves_existing_canopy_size", true)
    canopy_root.set_meta("panel_count_source_measured", false)
    root.add_child(canopy_root)
    var edge_width := 0.48
    var rib_width := 0.32
    var frame_height := 0.36
    var panel_height := 0.12
    var half_x := CANOPY_SIZE.x * 0.5
    var half_z := CANOPY_SIZE.z * 0.5
    var inner_x := CANOPY_SIZE.x - edge_width * 2.0
    var inner_z := CANOPY_SIZE.z - edge_width * 2.0
    var panel_x := (inner_x - rib_width * float(X_CELLS - 1)) / float(X_CELLS)
    var panel_z := (inner_z - rib_width * float(Z_CELLS - 1)) / float(Z_CELLS)
    _add_box(canopy_root, "CanopyConcreteEdgeNorth", Vector3(CANOPY_SIZE.x, frame_height, edge_width), Vector3(0.0, 0.0, -half_z + edge_width * 0.5), concrete)
    _add_box(canopy_root, "CanopyConcreteEdgeSouth", Vector3(CANOPY_SIZE.x, frame_height, edge_width), Vector3(0.0, 0.0, half_z - edge_width * 0.5), concrete)
    _add_box(canopy_root, "CanopyConcreteEdgeStation", Vector3(edge_width, frame_height, inner_z), Vector3(-half_x + edge_width * 0.5, 0.0, 0.0), concrete)
    _add_box(canopy_root, "CanopyConcreteEdgeRoad", Vector3(edge_width, frame_height, inner_z), Vector3(half_x - edge_width * 0.5, 0.0, 0.0), concrete)
    var start_x := -inner_x * 0.5
    var start_z := -inner_z * 0.5
    for boundary_x: int in range(X_CELLS - 1):
        var rib_x := start_x + panel_x * float(boundary_x + 1) + rib_width * (float(boundary_x) + 0.5)
        _add_box(canopy_root, "CanopyConcreteRib_X_%02d" % boundary_x, Vector3(rib_width, frame_height, inner_z), Vector3(rib_x, 0.0, 0.0), concrete)
    for boundary_z: int in range(Z_CELLS - 1):
        var rib_z := start_z + panel_z * float(boundary_z + 1) + rib_width * (float(boundary_z) + 0.5)
        _add_box(canopy_root, "CanopyConcreteRib_Z_%02d" % boundary_z, Vector3(inner_x, frame_height, rib_width), Vector3(0.0, 0.0, rib_z), concrete)
    for x_index: int in range(X_CELLS):
        var panel_center_x := start_x + panel_x * 0.5 + float(x_index) * (panel_x + rib_width)
        for z_index: int in range(Z_CELLS):
            var panel_center_z := start_z + panel_z * 0.5 + float(z_index) * (panel_z + rib_width)
            _add_box(canopy_root, "CanopyGlassBlockPanel_%02d_%02d" % [x_index, z_index], Vector3(panel_x, panel_height, panel_z), Vector3(panel_center_x, 0.0, panel_center_z), glass_block)

    # Heritage-described polygonal supports. Exact local positions remain
    # presentation conventions within the already-authored canopy envelope.
    var column_z := [-9.1, -3.1, 3.1, 9.1]
    for column_index: int in range(4):
        _add_polygonal_column(root, column_index, Vector3(-8.05, 2.15, float(column_z[column_index])), concrete)
    return root

func _claim_superseded_visibility_ownership() -> bool:
    for node in _superseded:
        if not is_instance_valid(node):
            continue
        var owner := str(node.get_meta(VISIBILITY_OWNER_META, ""))
        if owner != "" and owner != VISIBILITY_OWNER_VALUE:
            _release_superseded_visibility_ownership()
            return false
        var instance_id := node.get_instance_id()
        if not _original_visibility.has(instance_id):
            _original_visibility[instance_id] = node.visible
        node.set_meta(VISIBILITY_OWNER_META, VISIBILITY_OWNER_VALUE)
        node.visible = false
    return true

func _release_superseded_visibility_ownership() -> void:
    for node in _superseded:
        if not is_instance_valid(node):
            continue
        var instance_id := node.get_instance_id()
        if not _original_visibility.has(instance_id):
            continue
        if str(node.get_meta(VISIBILITY_OWNER_META, "")) != VISIBILITY_OWNER_VALUE:
            continue
        if not node.visible:
            node.visible = bool(_original_visibility.get(instance_id, true))
        node.remove_meta(VISIBILITY_OWNER_META)
    _original_visibility.clear()

func set_replacement_enabled(enabled: bool) -> void:
    if enabled:
        if not _claim_superseded_visibility_ownership():
            _replacement_enabled = false
            if _replacement != null and is_instance_valid(_replacement):
                _replacement.visible = false
            _fail("superseded Fonsny visibility already owned by another runtime")
            return
        _replacement_enabled = true
        if _replacement != null and is_instance_valid(_replacement):
            _replacement.visible = true
        return
    _release_superseded_visibility_ownership()
    _replacement_enabled = false
    if _replacement != null and is_instance_valid(_replacement):
        _replacement.visible = false

func replacement_enabled() -> bool:
    return _replacement_enabled

func built() -> bool:
    return _built

func build_failure() -> bool:
    return _build_failure

func replacement_root() -> Node3D:
    return _replacement

func superseded_count() -> int:
    return _superseded.size()

func _fail(message: String) -> void:
    if _tearing_down:
        return
    push_error("Midi Fonsny full entrance: " + message)
    _build_failure = true
