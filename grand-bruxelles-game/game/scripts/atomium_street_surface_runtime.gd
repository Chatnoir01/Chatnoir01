extends Node

const CONTEXT_SCRIPT := preload("res://game/zones/laeken_jette/atomium_street_surface_context.gd")
const TERRAIN_NODE_NAME := "AtomiumDirectTerrain"
const CONTEXT_NODE_NAME := "AtomiumStreetSurfaceContext"
const RUNTIME_APPROVED := false
const REALISM_COMPLETE := false

var _context: Node3D = null
var _terrain: Node = null
var _enhanced_enabled := true
var _ready_complete := false
var _failed := false

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    set_process(true)

func _process(_delta: float) -> void:
    if _context != null and not is_instance_valid(_context):
        _context = null
        _terrain = null
        _ready_complete = false
        _failed = false

    if is_instance_valid(_context):
        _context.visible = _enhanced_enabled
        return

    var scene := get_tree().current_scene
    if scene == null:
        return
    var terrain := scene.get_node_or_null(TERRAIN_NODE_NAME)
    if terrain == null or not bool(terrain.get("terrain_loaded")):
        return

    var context := CONTEXT_SCRIPT.new() as Node3D
    if context == null:
        _failed = true
        _ready_complete = true
        push_error("Atomium StreetSurface runtime: context script did not instantiate")
        return
    context.name = CONTEXT_NODE_NAME
    scene.add_child(context)
    if not bool(context.call("build_on_terrain", terrain)):
        context.queue_free()
        _failed = true
        _ready_complete = true
        push_error("Atomium StreetSurface runtime: source-bounded context failed to build")
        return

    context.visible = _enhanced_enabled
    context.set_meta("registry_mounted", true)
    context.set_meta("runtime_approved", RUNTIME_APPROVED)
    context.set_meta("realism_complete", REALISM_COMPLETE)
    context.set_meta("source_position_changed", false)
    context.set_meta("collision_changed", false)
    _context = context
    _terrain = terrain
    _ready_complete = true
    _failed = false
    print("ATOMIUM_STREET_SURFACE_REGISTRY_READY: mounted=true radius=160.0 runtime_approved=false realism_complete=false position_changed=false collision_changed=false")

func set_enhanced_enabled(enabled: bool) -> void:
    _enhanced_enabled = enabled
    if is_instance_valid(_context):
        _context.visible = enabled

func enhanced_enabled() -> bool:
    return _enhanced_enabled

func ready_complete() -> bool:
    return _ready_complete

func failed() -> bool:
    return _failed

func context_node() -> Node3D:
    return _context if is_instance_valid(_context) else null

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
