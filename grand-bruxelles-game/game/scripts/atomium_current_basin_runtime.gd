extends Node

const BASIN_SCRIPT := preload("res://game/zones/laeken_jette/atomium_current_basin_footprint.gd")
const TERRAIN_NODE_NAME := "AtomiumDirectTerrain"
const BASIN_NODE_NAME := "AtomiumCurrentBasinFootprint"
const RUNTIME_APPROVED := false
const REALISM_COMPLETE := false

var _basin: Node3D = null
var _terrain: Node = null
var _enhanced_enabled := true
var _ready_complete := false
var _failed := false

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    set_process(true)

func _process(_delta: float) -> void:
    if _basin != null and not is_instance_valid(_basin):
        _basin = null
        _terrain = null
        _ready_complete = false
        _failed = false

    if is_instance_valid(_basin):
        _basin.visible = _enhanced_enabled
        return

    var scene := get_tree().current_scene
    if scene == null:
        return
    var terrain := scene.get_node_or_null(TERRAIN_NODE_NAME)
    if terrain == null or not bool(terrain.get("terrain_loaded")):
        return

    var basin := BASIN_SCRIPT.new() as Node3D
    if basin == null:
        _failed = true
        _ready_complete = true
        push_error("Atomium current basin runtime: footprint script did not instantiate")
        return
    basin.name = BASIN_NODE_NAME
    scene.add_child(basin)
    if not bool(basin.call("build_on_terrain", terrain)):
        basin.queue_free()
        _failed = true
        _ready_complete = true
        push_error("Atomium current basin runtime: source-bounded footprint failed to build")
        return

    basin.visible = _enhanced_enabled
    basin.set_meta("runtime_approved", RUNTIME_APPROVED)
    basin.set_meta("realism_complete", REALISM_COMPLETE)
    basin.set_meta("registry_mounted", true)
    basin.set_meta("source_position_changed", false)
    basin.set_meta("collision_changed", false)
    _basin = basin
    _terrain = terrain
    _ready_complete = true
    _failed = false
    print("ATOMIUM_CURRENT_BASIN_REGISTRY_READY: mounted=true runtime_approved=false realism_complete=false position_changed=false collision_changed=false")

func set_enhanced_enabled(enabled: bool) -> void:
    _enhanced_enabled = enabled
    if is_instance_valid(_basin):
        _basin.visible = enabled

func enhanced_enabled() -> bool:
    return _enhanced_enabled

func ready_complete() -> bool:
    return _ready_complete

func failed() -> bool:
    return _failed

func basin_node() -> Node3D:
    return _basin if is_instance_valid(_basin) else null

func terrain_node() -> Node:
    return _terrain if is_instance_valid(_terrain) else null

func runtime_approved() -> bool:
    return RUNTIME_APPROVED

func realism_complete() -> bool:
    return REALISM_COMPLETE

func source_position_changed() -> bool:
    return false

func collision_changed() -> bool:
    return false
