extends Node

const MATERIAL_FACTORY := preload("res://game/scripts/brussels_blue_stone_material.gd")
const IDENTITY_PATH := "res://data/visual/midi_blue_stone_material_identity.json"
const TARGET_NAMES := ["StationBaseBlueStone", "BlueStoneBase"]

var _targets: Array[MeshInstance3D] = []
var _original_materials: Dictionary = {}
var _material: ShaderMaterial
var _ready_complete := false
var _identity_failure := false
var _enabled := true
var _urbis_owner_skip := false

func _ready() -> void:
    call_deferred("_apply_when_ready")

func _apply_when_ready() -> void:
    await get_tree().process_frame
    var identity := _read_identity()
    if identity.is_empty():
        _ready_complete = true
        return
    var midi := get_tree().root.get_node_or_null("GrandBruxelles/MidiHeroZone")
    if midi == null:
        midi = get_tree().root.find_child("MidiHeroZone", true, false)
    if midi == null:
        push_error("Midi blue-stone runtime: MidiHeroZone missing")
        _identity_failure = true
        _ready_complete = true
        return
    if bool(midi.get_meta("midi_urbis_envelope_owner", false)):
        _urbis_owner_skip = true
        _ready_complete = true
        print("Midi blue-stone runtime: SKIP legacy station-mass surfaces; UrbISMidiExact owns station masses")
        return
    _targets.clear()
    _collect_targets(midi)
    if _targets.size() != 4:
        push_error("Midi blue-stone runtime: expected 4 verified base surfaces, got %d" % _targets.size())
        _identity_failure = true
        _ready_complete = true
        return
    _material = MATERIAL_FACTORY.create(Color(0.095, 0.125, 0.145, 1.0), Color(0.255, 0.275, 0.285, 1.0), 0.78, "Midi Urban 9423 blue-stone bases")
    for target in _targets:
        _original_materials[target.get_instance_id()] = target.material_override
        target.material_override = _material
    _ready_complete = true

func _read_identity() -> Dictionary:
    if not FileAccess.file_exists(IDENTITY_PATH):
        push_error("Midi blue-stone runtime: material identity missing")
        _identity_failure = true
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(IDENTITY_PATH))
    if typeof(parsed) != TYPE_DICTIONARY:
        push_error("Midi blue-stone runtime: material identity invalid")
        _identity_failure = true
        return {}
    var identity := parsed as Dictionary
    if not _runtime_identity_allowed(identity):
        push_error("Midi blue-stone runtime: material identity is not explicitly runtime-approved or violates the presentation contract")
        _identity_failure = true
        return {}
    return identity

func _runtime_identity_allowed(identity: Dictionary) -> bool:
    var contract := identity.get("presentation_contract", {}) as Dictionary
    if str(identity.get("schema", "")) != "grand-bruxelles-material-identity-v1": return false
    if str(contract.get("material_identity", "")) != "blue_stone": return false
    if bool(contract.get("geometry_changed", true)) or bool(contract.get("new_location_specific_placement", true)): return false
    if bool(contract.get("masonry_joints_authored", true)) or bool(contract.get("tooling_pattern_authored", true)): return false
    return bool(contract.get("runtime_approved", false))

func _collect_targets(node: Node) -> void:
    if node is MeshInstance3D and node.name in TARGET_NAMES: _targets.append(node as MeshInstance3D)
    for child in node.get_children(): _collect_targets(child)

func set_enhanced_material_enabled(enabled: bool) -> void:
    _enabled = enabled
    if not _ready_complete or _identity_failure or _urbis_owner_skip: return
    for target in _targets:
        target.material_override = _material if enabled else _original_materials.get(target.get_instance_id(), null)

func enhanced_material_enabled() -> bool: return _enabled
func ready_complete() -> bool: return _ready_complete
func identity_failure() -> bool: return _identity_failure
func applied_surface_count() -> int: return _targets.size() if _ready_complete and not _identity_failure else 0
func enhanced_material() -> ShaderMaterial: return _material
func urbis_owner_skip() -> bool: return _urbis_owner_skip
