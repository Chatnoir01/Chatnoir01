extends Node

const MATERIAL_FACTORY := preload("res://game/scripts/brussels_blue_stone_material.gd")
const TARGET_NAME := "OfficialBourseSidewalkMesh"

var _target: MeshInstance3D = null
var _material: ShaderMaterial = null
var _ready_complete := false
var _failed := false

func _ready() -> void:
    call_deferred("_apply_when_ready")

func _apply_when_ready() -> void:
    for _attempt: int in range(180):
        await get_tree().process_frame
        var candidate := get_tree().root.find_child(TARGET_NAME, true, false)
        if candidate is MeshInstance3D:
            _target = candidate as MeshInstance3D
            break
    if _target == null:
        push_error("Bourse paving runtime: official sidewalk mesh missing")
        _failed = true
        _ready_complete = true
        return

    # Clone the already-approved Midi blue-stone recipe. No new commune-specific
    # art direction, geometry, curb height or masonry pattern is introduced.
    _material = MATERIAL_FACTORY.create(
        Color(0.095, 0.125, 0.145, 1.0),
        Color(0.255, 0.275, 0.285, 1.0),
        0.78,
        "Midi blue-stone recipe reused for Bourse official sidewalk LABO surface"
    )
    _material.set_meta("recipe_source", "midi")
    _material.set_meta("zone", "bourse")
    _material.set_meta("presentation_only", true)
    _target.material_override = _material
    _ready_complete = true
    print("BOURSE_BLUE_STONE_PAVING_READY: surfaces=1 recipe=midi geometry_changed=false")

func ready_complete() -> bool:
    return _ready_complete

func failed() -> bool:
    return _failed

func applied_surface_count() -> int:
    return 1 if _ready_complete and not _failed and _target != null and _target.material_override == _material else 0

func enhanced_material() -> ShaderMaterial:
    return _material
