extends Node

const MATERIAL_FACTORY := preload("res://game/scripts/brussels_blue_stone_material.gd")
const SLICE_NAME := "IxellesDirectMicroSlice"
const SOURCE_PARENT_NAME := "OfficialIxellesStreetSurfaces"
const LEGACY_TARGET_NAME := "StreetSurfaces_SW"
const LEGACY_SOURCE_CONTRACT := "Paradigm UrbIS WFS cell.game street_surfaces.type"
const LEGACY_SURFACE_TYPE := "SW"
const CURRENT_OFFICIAL_LAYER := "bm_urbis:urbadm_ssw"
const DISABLE_ENV := "GB_IXELLES_MIDI_SIDEWALK"

var _target: MeshInstance3D = null
var _material: ShaderMaterial = null
var _ready_complete := false
var _failed := false
var _dormant := true

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    get_tree().node_added.connect(_on_node_added)
    call_deferred("_try_bind")

func _on_node_added(node: Node) -> void:
    if node.name == SLICE_NAME or node.name == SOURCE_PARENT_NAME or node.name == LEGACY_TARGET_NAME:
        call_deferred("_try_bind")

func _try_bind() -> void:
    if is_instance_valid(_target):
        return
    var scene := get_tree().current_scene
    if scene == null:
        _dormant = true
        return
    var slice := scene.find_child(SLICE_NAME, true, false)
    if slice == null:
        _dormant = true
        return
    var source_parent := slice.get_node_or_null(SOURCE_PARENT_NAME)
    if source_parent == null:
        _dormant = true
        return
    var candidate := source_parent.get_node_or_null(LEGACY_TARGET_NAME)
    if not candidate is MeshInstance3D:
        _dormant = true
        return

    _target = candidate as MeshInstance3D
    _material = MATERIAL_FACTORY.create(
        Color(0.095, 0.125, 0.145, 1.0),
        Color(0.255, 0.275, 0.285, 1.0),
        0.78,
        "Authored Midi blue-stone presentation on legacy Ixelles UrbIS cell surface; material identity not source-backed"
    )
    _material.set_meta("recipe_source", "midi")
    _material.set_meta("zone", "ixelles")
    _material.set_meta("presentation_only", true)
    _material.set_meta("material_identity_source_backed", false)
    _material.set_meta("legacy_source_contract", LEGACY_SOURCE_CONTRACT)
    _material.set_meta("legacy_surface_type", LEGACY_SURFACE_TYPE)
    _material.set_meta("current_official_layer", CURRENT_OFFICIAL_LAYER)
    _material.set_meta("uses_current_official_ssft_filter", false)

    if OS.get_environment(DISABLE_ENV) != "0":
        _target.material_override = _material
    _dormant = false
    _ready_complete = true
    print("IXELLES_MIDI_SIDEWALK_READY: surfaces=1 recipe=midi legacy_cell_type=SW current_official_ssft_filter=false geometry_changed=false enabled=%s" % str(OS.get_environment(DISABLE_ENV) != "0"))

func ready_complete() -> bool:
    return _ready_complete

func failed() -> bool:
    return _failed

func dormant() -> bool:
    return _dormant

func applied_surface_count() -> int:
    return 1 if _ready_complete and not _failed and _target != null and _target.material_override == _material else 0

func enhanced_material() -> ShaderMaterial:
    return _material
