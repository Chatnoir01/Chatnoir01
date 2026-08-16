extends Node

const MATERIAL_FACTORY := preload("res://game/scripts/brussels_slate_roof_material.gd")

const TARGETS := [
    {
        "root_path": NodePath("/root/GrandPlaceOfficialLod2"),
        "roof_name": "GrandPlace1655673_ROOFSURFACE",
        "identity_path": "res://data/visual/grand_place_1655673_roof_material_identity.json",
        "building_id": "https://databrussels.be/id/building/1655673",
        "cool": Color(0.045, 0.060, 0.075, 1.0),
        "warm": Color(0.155, 0.165, 0.175, 1.0),
        "roughness": 0.70,
    },
    {
        "root_path": NodePath("/root/GrandPlaceOfficialLod2Next"),
        "roof_name": "GrandPlace1786758_ROOFSURFACE",
        "identity_path": "res://data/visual/grand_place_1786758_roof_material_identity.json",
        "building_id": "https://databrussels.be/id/building/1786758",
        "cool": Color(0.055, 0.067, 0.080, 1.0),
        "warm": Color(0.175, 0.178, 0.180, 1.0),
        "roughness": 0.74,
    },
]

var _roofs: Array[MeshInstance3D] = []
var _original_overrides: Dictionary = {}
var _sourced_materials: Dictionary = {}
var _enabled := true
var _applied_surface_count := 0
var _ready_complete := false
var _identity_failure := false

func _ready() -> void:
    call_deferred("_apply_when_ready")

func _read_identity(path: String, expected_building_id: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        push_error("Grand-Place slate-roof runtime: identity missing %s" % path)
        _identity_failure = true
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    if typeof(parsed) != TYPE_DICTIONARY:
        push_error("Grand-Place slate-roof runtime: identity invalid %s" % path)
        _identity_failure = true
        return {}
    var identity := parsed as Dictionary
    if str(identity.get("schema", "")) != "grand-bruxelles-roof-material-identity-v1":
        push_error("Grand-Place slate-roof runtime: schema drifted %s" % path)
        _identity_failure = true
        return {}
    var target := identity.get("target", {}) as Dictionary
    var contract := identity.get("presentation_contract", {}) as Dictionary
    if str(target.get("urbis_building_id", "")) != expected_building_id:
        push_error("Grand-Place slate-roof runtime: building identity drifted %s" % path)
        _identity_failure = true
        return {}
    if str(contract.get("applies_to", "")) != "ROOFSURFACE only" or str(contract.get("material_identity", "")) != "slate":
        push_error("Grand-Place slate-roof runtime: roof-only slate contract drifted %s" % path)
        _identity_failure = true
        return {}
    if bool(contract.get("geometry_changed", true)) or bool(contract.get("roofing_unit_pattern_authored", true)) or bool(contract.get("exact_rgb_is_photometric_measurement", true)):
        push_error("Grand-Place slate-roof runtime: source/presentation boundary drifted %s" % path)
        _identity_failure = true
        return {}
    return identity

func _apply_when_ready() -> void:
    for _frame: int in range(30):
        if _try_apply_all():
            _ready_complete = true
            print("GRAND_PLACE_SLATE_ROOF_SURFACE_READY: surfaces=%d procedural=true geometry_changed=false" % _applied_surface_count)
            return
        if _identity_failure:
            return
        await get_tree().process_frame
    push_error("Grand-Place slate-roof runtime: target LoD2 roofs did not become ready")

func _try_apply_all() -> bool:
    if _applied_surface_count == TARGETS.size():
        return true
    for target_variant: Variant in TARGETS:
        var target := target_variant as Dictionary
        var root_node := get_node_or_null(target.get("root_path", NodePath("")))
        if root_node == null:
            return false
        var roof := root_node.get_node_or_null(str(target.get("roof_name", ""))) as MeshInstance3D
        if roof == null:
            return false
        if _roofs.has(roof):
            continue
        var identity_path := str(target.get("identity_path", ""))
        var building_id := str(target.get("building_id", ""))
        if _read_identity(identity_path, building_id).is_empty():
            return false
        var cool: Color = target.get("cool", Color(0.05, 0.06, 0.07, 1.0))
        var warm: Color = target.get("warm", Color(0.16, 0.17, 0.18, 1.0))
        var material := MATERIAL_FACTORY.create(
            cool,
            warm,
            float(target.get("roughness", 0.72)),
            identity_path
        )
        var instance_id := roof.get_instance_id()
        _original_overrides[instance_id] = roof.material_override
        _sourced_materials[instance_id] = material
        roof.material_override = material
        roof.set_meta("slate_roof_surface_runtime", true)
        roof.set_meta("roof_material_identity_path", identity_path)
        roof.set_meta("geometry_changed", false)
        roof.set_meta("roofing_unit_pattern_authored", false)
        _roofs.append(roof)
        _applied_surface_count += 1
    return _applied_surface_count == TARGETS.size()

func set_enabled(enabled: bool) -> void:
    _enabled = enabled
    for roof: MeshInstance3D in _roofs:
        if not is_instance_valid(roof):
            continue
        var instance_id := roof.get_instance_id()
        roof.material_override = _sourced_materials.get(instance_id) if enabled else _original_overrides.get(instance_id)
        roof.set_meta("slate_roof_surface_runtime", enabled)

func presentation_enabled() -> bool:
    return _enabled and _ready_complete and _applied_surface_count == TARGETS.size()

func applied_surface_count() -> int:
    return _applied_surface_count
