extends Node

## Registry-mounted bridge for Ixelles LABO life.
## It stays idle everywhere else and never creates geography. When the existing
## IxellesDirectMicroSlice appears, it mounts the zone-local life node exactly once.

const LIFE_SCRIPT := preload("res://game/scripts/ixelles_lab_life.gd")
const DISABLE_ENV := "GB_IXELLES_LIFE"
const SLICE_NAME := "IxellesDirectMicroSlice"
const LIFE_NAME := "ZoneLife_ixelles"
const CHECK_INTERVAL_S := 0.12

var _elapsed := 0.0
var _ready_complete := false
var _failed := false
var _mounted_count := 0
var _last_world_instance_id := 0

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    if OS.get_environment(DISABLE_ENV) == "0":
        _ready_complete = true
        set_process(false)
        print("IXELLES_LAB_LIFE_RUNTIME_DISABLED: witness_only=true")
        return
    set_process(true)

func _process(delta: float) -> void:
    _elapsed += delta
    if _elapsed < CHECK_INTERVAL_S:
        return
    _elapsed = 0.0
    _try_mount()

func _try_mount() -> void:
    var slice := get_tree().root.find_child(SLICE_NAME, true, false)
    if slice == null or not bool(slice.get("runtime_loaded")):
        return
    var world := slice.get_parent()
    if world == null:
        return
    var world_id := world.get_instance_id()
    var existing := world.get_node_or_null(LIFE_NAME)
    if existing != null:
        if world_id != _last_world_instance_id:
            _validate_life(existing)
            _last_world_instance_id = world_id
        return

    var life := Node3D.new()
    life.name = LIFE_NAME
    life.set_script(LIFE_SCRIPT)
    world.add_child(life)
    if not _validate_life(life):
        life.queue_free()
        return
    _last_world_instance_id = world_id
    _mounted_count += 1
    _ready_complete = true
    print("IXELLES_LAB_LIFE_RUNTIME_READY: mounted=%d existing_slice=true geography_expanded=false" % _mounted_count)

func _validate_life(life: Node) -> bool:
    if life == null or not life.has_method("has_minimum_playable_life"):
        _fail("mounted life node has no minimum contract")
        return false
    if not bool(life.call("has_minimum_playable_life")):
        _fail("mounted life node failed minimum contract")
        return false
    var counts: Variant = life.call("get_counts") if life.has_method("get_counts") else {}
    if not counts is Dictionary or int((counts as Dictionary).get("civilians", 0)) < 1 or int((counts as Dictionary).get("moving_vehicles", 0)) < 1:
        _fail("mounted life counts failed")
        return false
    _ready_complete = true
    return true

func _fail(message: String) -> void:
    _failed = true
    _ready_complete = true
    push_error("Ixelles LABO life runtime: %s" % message)

func ready_complete() -> bool:
    return _ready_complete

func failed() -> bool:
    return _failed

func mounted_count() -> int:
    return _mounted_count
