extends Node

const MATERIAL_FACTORY := preload("res://game/scripts/brussels_white_stone_material.gd")

const TARGETS := [
    {
        "root_path": NodePath("/root/GrandPlaceOfficialLod2"),
        "wall_name": "GrandPlace1655673_WALLSURFACE",
        "identity_path": "res://data/visual/grand_place_1655673_material_identity.json",
        "building_id": "https://databrussels.be/id/building/1655673",
        "cool": Color(0.70, 0.685, 0.64, 1.0),
        "warm": Color(0.84, 0.82, 0.755, 1.0),
        "roughness": 0.82,
    },
    {
        "root_path": NodePath("/root/GrandPlaceOfficialLod2Next"),
        "wall_name": "GrandPlace1786758_WALLSURFACE",
        "identity_path": "res://data/visual/grand_place_1786758_material_identity.json",
        "building_id": "https://databrussels.be/id/building/1786758",
        "cool": Color(0.76, 0.74, 0.69, 1.0),
        "warm": Color(0.88, 0.855, 0.79, 1.0),
        "roughness": 0.76,
    },
]

var _walls: Array[MeshInstance3D] = []
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
        push_error("Grand-Place white-stone runtime: identity missing %s" % path)
        _identity_failure = true
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    if typeof(parsed) != TYPE_DICTIONARY:
        push_error("Grand-Place white-stone runtime: identity invalid %s" % path)
        _identity_failure = true
        return {}
    var identity := parsed as Dictionary
    var target := identity.get("target", {}) as Dictionary
    var contract := identity.get("presentation_contract", {}) as Dictionary
    if str(target.get("urbis_building_id", "")) != expected_building_id:
        push_error("Grand-Place white-stone runtime: building identity drifted %s" % path)
        _identity_failure = true
        return {}
    # The older 1655673 evidence predates the explicit applies_to field. Treat
    # an absent field as legacy-compatible, but reject any contradictory scope.
    if contract.has("applies_to") and str(contract.get("applies_to", "")) != "WALLSURFACE":
        push_error("Grand-Place white-stone runtime: wall-only contract drifted %s" % path)
        _identity_failure = true
        return {}
    if bool(contract.get("geometry_changed", true)) or bool(contract.get("exact_rgb_is_photometric_measurement", true)):
        push_error("Grand-Place white-stone runtime: source/presentation boundary drifted %s" % path)
        _identity_failure = true
        return {}
    return identity

func _apply_when_ready() -> void:
    for _frame: int in range(30):
        if _try_apply_all():
            _ready_complete = true
            print("GRAND_PLACE_WHITE_STONE_SURFACE_READY: surfaces=%d procedural=true geometry_changed=false" % _applied_surface_count)
            return
        if _identity_failure:
            return
        await get_tree().process_frame
    push_error("Grand-Place white-stone runtime: target LoD2 walls did not become ready")

func _try_apply_all() -> bool:
    if _applied_surface_count == TARGETS.size():
        return true
    for target_variant: Variant in TARGETS:
        var target := target_variant as Dictionary
        var root_node := get_node_or_null(target.get("root_path", NodePath("")))
        if root_node == null:
            return false
        var wall := root_node.get_node_or_null(str(target.get("wall_name", ""))) as MeshInstance3D
        if wall == null:
            return false
        if _walls.has(wall):
            continue
        var identity_path := str(target.get("identity_path", ""))
        var building_id := str(target.get("building_id", ""))
        if _read_identity(identity_path, building_id).is_empty():
            return false
        var cool: Color = target.get("cool", Color.WHITE)
        var warm: Color = target.get("warm", Color.WHITE)
        var material := MATERIAL_FACTORY.create(
            cool,
            warm,
            float(target.get("roughness", 0.8)),
            identity_path
        )
        var instance_id := wall.get_instance_id()
        _original_overrides[instance_id] = wall.material_override
        _sourced_materials[instance_id] = material
        wall.material_override = material
        wall.set_meta("white_stone_surface_runtime", true)
        wall.set_meta("material_identity_path", identity_path)
        wall.set_meta("geometry_changed", false)
        wall.set_meta("openings_authored", false)
        _walls.append(wall)
        _applied_surface_count += 1
    return _applied_surface_count == TARGETS.size()

func set_enabled(enabled: bool) -> void:
    _enabled = enabled
    for wall: MeshInstance3D in _walls:
        if not is_instance_valid(wall):
            continue
        var instance_id := wall.get_instance_id()
        wall.material_override = _sourced_materials.get(instance_id) if enabled else _original_overrides.get(instance_id)
        wall.set_meta("white_stone_surface_runtime", enabled)

func presentation_enabled() -> bool:
    return _enabled and _ready_complete and _applied_surface_count == TARGETS.size()

func applied_surface_count() -> int:
    return _applied_surface_count
