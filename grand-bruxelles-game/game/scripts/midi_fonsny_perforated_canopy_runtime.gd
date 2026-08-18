extends Node

## Source-backed replacement for the existing solid Fonsny entrance canopy.
## Urban 9423 explicitly describes a vast concrete canopy perforated with
## glass blocks. Exact frame-cell count/spacing below are presentation
## conventions constrained to the already-authored production canopy envelope;
## they are not survey measurements and do not alter the official UrbIS plan.

const IDENTITY_PATH := "res://data/visual/midi_fonsny_perforated_canopy_identity.json"
const REPLACEMENT_NAME := "EntranceSourceBackedPerforatedCanopy"
const BASELINE_NAME := "EntranceConcreteCanopy"
const CANOPY_SIZE := Vector3(17.8, 0.48, 25.0)
const CANOPY_POSITION := Vector3(-7.0, 4.55, 0.0)
const EDGE_WIDTH := 0.48
const RIB_WIDTH := 0.32
const FRAME_HEIGHT := 0.36
const PANEL_HEIGHT := 0.12
const X_CELLS := 4
const Z_CELLS := 5

var _built := false
var _build_failure := false
var _source_backed_enabled := false
var _baseline: MeshInstance3D
var _replacement: Node3D


func _ready() -> void:
    call_deferred("_build_when_parent_ready")


func _build_when_parent_ready() -> void:
    var parent_runtime := get_parent()
    for _i in range(120):
        if parent_runtime != null and parent_runtime.has_method("ready_complete") and parent_runtime.ready_complete():
            break
        await get_tree().process_frame
    if parent_runtime == null or not parent_runtime.has_method("ready_complete") or not parent_runtime.ready_complete():
        push_error("Midi Fonsny canopy: concrete material mount never became ready")
        _build_failure = true
        return
    if parent_runtime.has_method("identity_failure") and parent_runtime.identity_failure():
        push_error("Midi Fonsny canopy: parent concrete material identity failed")
        _build_failure = true
        return

    var identity := _read_identity()
    if identity.is_empty() or not _identity_allowed(identity):
        push_error("Midi Fonsny canopy: source identity contract invalid")
        _build_failure = true
        return

    var entrance := get_tree().root.find_child("MidiMainEntranceFonsny", true, false) as Node3D
    if entrance == null:
        push_error("Midi Fonsny canopy: entrance anchor missing")
        _build_failure = true
        return
    _baseline = entrance.get_node_or_null(BASELINE_NAME) as MeshInstance3D
    if _baseline == null or not (_baseline.mesh is BoxMesh):
        push_error("Midi Fonsny canopy: production solid-canopy baseline missing")
        _build_failure = true
        return
    var baseline_box := _baseline.mesh as BoxMesh
    if not baseline_box.size.is_equal_approx(CANOPY_SIZE) or not _baseline.position.is_equal_approx(CANOPY_POSITION):
        push_error("Midi Fonsny canopy: production canopy envelope drifted")
        _build_failure = true
        return

    var concrete := _effective_material(_baseline)
    var glass_block_source := get_tree().root.find_child("VerticalGlassTower", true, false) as MeshInstance3D
    var glass_block: Material = null
    if glass_block_source != null:
        glass_block = _effective_material(glass_block_source)
    if concrete == null or glass_block == null:
        push_error("Midi Fonsny canopy: source-designated production materials unavailable")
        _build_failure = true
        return

    _replacement = _build_source_backed_canopy(entrance, concrete, glass_block)
    if _replacement == null:
        _build_failure = true
        return
    set_source_backed_enabled(true)
    _built = true
    print("MIDI_FONSNY_PERFORATED_CANOPY_READY panels=%d geometry_envelope_changed=false source_urban_id=9423" % [X_CELLS * Z_CELLS])


func _read_identity() -> Dictionary:
    if not FileAccess.file_exists(IDENTITY_PATH):
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(IDENTITY_PATH))
    if typeof(parsed) != TYPE_DICTIONARY:
        return {}
    return parsed as Dictionary


func _identity_allowed(identity: Dictionary) -> bool:
    if str(identity.get("schema", "")) != "grand-bruxelles-midi-fonsny-canopy-v1":
        return false
    var source := identity.get("heritage_source", {}) as Dictionary
    if int(source.get("urban_id", -1)) != 9423:
        return false
    var envelope := identity.get("existing_presentation_envelope", {}) as Dictionary
    if not bool(envelope.get("preserve_size", false)) or not bool(envelope.get("preserve_local_position", false)):
        return false
    var contract := identity.get("replacement_contract", {}) as Dictionary
    if not bool(contract.get("replace_existing_surface_in_place", false)):
        return false
    if not bool(contract.get("additive_duplicate_forbidden", false)):
        return false
    if bool(contract.get("panel_count_is_source_measured", true)) or bool(contract.get("rib_spacing_is_source_measured", true)):
        return false
    if bool(contract.get("new_station_plan_geometry", true)):
        return false
    return bool(contract.get("urbis_station_plan_authority_preserved", false))


func _effective_material(instance: MeshInstance3D) -> Material:
    if instance.material_override != null:
        return instance.material_override
    if instance.mesh != null and instance.mesh.material != null:
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


func _build_source_backed_canopy(entrance: Node3D, concrete: Material, glass_block: Material) -> Node3D:
    if entrance.get_node_or_null(REPLACEMENT_NAME) != null:
        push_error("Midi Fonsny canopy: duplicate replacement root")
        return null
    var root := Node3D.new()
    root.name = REPLACEMENT_NAME
    root.position = CANOPY_POSITION
    root.set_meta("source_urban_id", 9423)
    root.set_meta("source_fact", "vast concrete canopy perforated with glass blocks")
    root.set_meta("fonsny_canopy_dimensions_are_visualization_convention", true)
    root.set_meta("panel_count_source_measured", false)
    root.set_meta("rib_spacing_source_measured", false)
    root.set_meta("official_station_plan_authority", "UrbIS")
    root.set_meta("replaces_surface", BASELINE_NAME)
    entrance.add_child(root)

    var half_x := CANOPY_SIZE.x * 0.5
    var half_z := CANOPY_SIZE.z * 0.5
    var inner_x := CANOPY_SIZE.x - EDGE_WIDTH * 2.0
    var inner_z := CANOPY_SIZE.z - EDGE_WIDTH * 2.0
    var panel_x := (inner_x - RIB_WIDTH * float(X_CELLS - 1)) / float(X_CELLS)
    var panel_z := (inner_z - RIB_WIDTH * float(Z_CELLS - 1)) / float(Z_CELLS)

    _add_box(root, "CanopyConcreteEdgeNorth", Vector3(CANOPY_SIZE.x, FRAME_HEIGHT, EDGE_WIDTH), Vector3(0.0, 0.0, -half_z + EDGE_WIDTH * 0.5), concrete)
    _add_box(root, "CanopyConcreteEdgeSouth", Vector3(CANOPY_SIZE.x, FRAME_HEIGHT, EDGE_WIDTH), Vector3(0.0, 0.0, half_z - EDGE_WIDTH * 0.5), concrete)
    _add_box(root, "CanopyConcreteEdgeStation", Vector3(EDGE_WIDTH, FRAME_HEIGHT, inner_z), Vector3(-half_x + EDGE_WIDTH * 0.5, 0.0, 0.0), concrete)
    _add_box(root, "CanopyConcreteEdgeRoad", Vector3(EDGE_WIDTH, FRAME_HEIGHT, inner_z), Vector3(half_x - EDGE_WIDTH * 0.5, 0.0, 0.0), concrete)

    var start_x := -inner_x * 0.5
    var start_z := -inner_z * 0.5
    for boundary_x: int in range(X_CELLS - 1):
        var rib_x := start_x + panel_x * float(boundary_x + 1) + RIB_WIDTH * (float(boundary_x) + 0.5)
        _add_box(root, "CanopyConcreteRib_X_%02d" % boundary_x, Vector3(RIB_WIDTH, FRAME_HEIGHT, inner_z), Vector3(rib_x, 0.0, 0.0), concrete)
    for boundary_z: int in range(Z_CELLS - 1):
        var rib_z := start_z + panel_z * float(boundary_z + 1) + RIB_WIDTH * (float(boundary_z) + 0.5)
        _add_box(root, "CanopyConcreteRib_Z_%02d" % boundary_z, Vector3(inner_x, FRAME_HEIGHT, RIB_WIDTH), Vector3(0.0, 0.0, rib_z), concrete)

    for x_index: int in range(X_CELLS):
        var panel_center_x := start_x + panel_x * 0.5 + float(x_index) * (panel_x + RIB_WIDTH)
        for z_index: int in range(Z_CELLS):
            var panel_center_z := start_z + panel_z * 0.5 + float(z_index) * (panel_z + RIB_WIDTH)
            _add_box(
                root,
                "CanopyGlassBlockPanel_%02d_%02d" % [x_index, z_index],
                Vector3(panel_x, PANEL_HEIGHT, panel_z),
                Vector3(panel_center_x, 0.0, panel_center_z),
                glass_block
            )
    return root


func set_source_backed_enabled(enabled: bool) -> void:
    _source_backed_enabled = enabled
    if _baseline != null:
        _baseline.visible = not enabled
    if _replacement != null:
        _replacement.visible = enabled


func source_backed_enabled() -> bool:
    return _source_backed_enabled


func built() -> bool:
    return _built


func build_failure() -> bool:
    return _build_failure


func replacement_root() -> Node3D:
    return _replacement


func baseline_surface() -> MeshInstance3D:
    return _baseline
