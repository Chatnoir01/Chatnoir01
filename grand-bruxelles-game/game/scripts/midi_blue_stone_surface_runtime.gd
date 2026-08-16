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
    _targets.clear()
    _collect_targets(midi)
    if _targets.size() != 4:
        push_error("Midi blue-stone runtime: expected 4 verified base surfaces, got %d" % _targets.size())
        _identity_failure = true
        _ready_complete = true
        return
    _material = MATERIAL_FACTORY.create(
        Color(0.095, 0.125, 0.145, 1.0),
        Color(0.255, 0.275, 0.285, 1.0),
        0.78,
        "Midi Urban 9423 blue-stone bases"
    )
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
    var contract := identity.get("presentation_contract", {}) as Dictionary
    if str(identity.get("schema", "")) != "grand-bruxelles-material-identity-v1":
        _identity_failure = true
        return {}
    if str(contract.get("material_identity", "")) != "blue_stone":
        _identity_failure = true
        return {}
    if bool(contract.get("geometry_changed", true)) or bool(contract.get("new_location_specific_placement", true)):
        _identity_failure = true
        return {}
    if bool(contract.get("masonry_joints_authored", true)) or bool(contract.get("tooling_pattern_authored", true)):
        _identity_failure = true
        return {}
    return identity

func _collect_targets(node: Node) -> void:
    if node is MeshInstance3D and node.name in TARGET_NAMES:
        _targets.append(node as MeshInstance3D)
    for child in node.get_children():
        _collect_targets(child)

func set_enhanced_material_enabled(enabled: bool) -> void:
    _enabled = enabled
    if not _ready_complete or _identity_failure:
        return
    for target in _targets:
        if enabled:
            target.material_override = _material
        else:
            target.material_override = _original_materials.get(target.get_instance_id(), null)

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
