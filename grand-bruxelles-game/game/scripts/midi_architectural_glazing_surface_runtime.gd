extends Node

const MATERIAL_FACTORY := preload("res://game/scripts/brussels_architectural_glazing_material.gd")
const IDENTITY_PATH := "res://data/visual/midi_architectural_glazing_material_identity.json"
const EXACT_NAMES := ["StationLongGlassBand", "EntranceGlazing"]
const PREFIXES := ["Window_", "GroundOpening_"]
const EXPECTED_SURFACES := 340

var _targets: Array[MeshInstance3D] = []
var _original_materials: Dictionary = {}
var _material: ShaderMaterial
var _ready_complete := false
var _identity_failure := false
var _enabled := false
var _identity: Dictionary = {}

func _ready() -> void:
    call_deferred("_apply_when_ready")

func _apply_when_ready() -> void:
    await get_tree().process_frame
    _identity = _read_identity()
    if _identity.is_empty():
        _ready_complete = true
        return
    var midi := get_tree().root.get_node_or_null("GrandBruxelles/MidiHeroZone")
    if midi == null:
        midi = get_tree().root.find_child("MidiHeroZone", true, false)
    if midi == null:
        push_error("Midi glazing runtime: MidiHeroZone missing")
        _identity_failure = true
        _ready_complete = true
        return
    _collect_targets(midi)
    if _targets.size() != EXPECTED_SURFACES:
        push_error("Midi glazing runtime: expected %d verified glazing surfaces, got %d" % [EXPECTED_SURFACES, _targets.size()])
        _identity_failure = true
        _ready_complete = true
        return
    _material = MATERIAL_FACTORY.create("Midi Urban 9423 architectural glazing")
    for target in _targets:
        _original_materials[target.get_instance_id()] = target.material_override if target.material_override != null else target.mesh.material
    if _runtime_identity_allowed(_identity):
        set_enhanced_material_enabled(true)
    _ready_complete = true

func _read_identity() -> Dictionary:
    if not FileAccess.file_exists(IDENTITY_PATH):
        push_error("Midi glazing runtime: material identity missing")
        _identity_failure = true
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(IDENTITY_PATH))
    if typeof(parsed) != TYPE_DICTIONARY:
        push_error("Midi glazing runtime: material identity invalid")
        _identity_failure = true
        return {}
    return parsed as Dictionary

func _runtime_identity_allowed(identity: Dictionary) -> bool:
    if str(identity.get("schema", "")) != "grand-bruxelles-material-identity-v1":
        return false
    var target := identity.get("target", {}) as Dictionary
    if int(target.get("expected_surface_count", -1)) != EXPECTED_SURFACES:
        return false
    var contract := identity.get("presentation_contract", {}) as Dictionary
    if str(contract.get("material_identity", "")) != "architectural_glazing":
        return false
    if bool(contract.get("geometry_changed", true)) or bool(contract.get("new_location_specific_placement", true)):
        return false
    if bool(contract.get("pane_layout_authored", true)) or bool(contract.get("interior_authored", true)):
        return false
    if bool(contract.get("exact_reflectance_claimed", true)):
        return false
    return bool(contract.get("runtime_approved", false))

func _is_target_name(node_name: String) -> bool:
    if node_name in EXACT_NAMES:
        return true
    for prefix in PREFIXES:
        if node_name.begins_with(prefix):
            return true
    return false

func _collect_targets(node: Node) -> void:
    if node is MeshInstance3D and _is_target_name(node.name):
        _targets.append(node as MeshInstance3D)
    for child in node.get_children():
        _collect_targets(child)

func set_enhanced_material_enabled(enabled: bool) -> void:
    _enabled = enabled
    if _material == null:
        return
    for target in _targets:
        if enabled:
            target.material_override = _material
        else:
            target.material_override = null
            var original: Material = _original_materials.get(target.get_instance_id(), null)
            if target.mesh != null:
                target.mesh.material = original

func apply_candidate_for_validation() -> void:
    set_enhanced_material_enabled(true)

func enhanced_material_enabled() -> bool:
    return _enabled

func ready_complete() -> bool:
    return _ready_complete

func identity_failure() -> bool:
    return _identity_failure

func applied_surface_count() -> int:
    return _targets.size() if _ready_complete and not _identity_failure else 0

func enhanced_material() -> ShaderMaterial:
    return _material
