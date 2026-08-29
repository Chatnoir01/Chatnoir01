extends Node

## Mount the source-bounded Heysel district only for the Atomium direct-entry path.
## This keeps normal first-load world behavior unchanged while making spawn=atomium
## render the surrounding official UrbIS context instead of an isolated showcase.

const DISTRICT_RUNTIME := preload("res://game/zones/laeken_jette/atomium_heysel_district_runtime.gd")

func _ready() -> void:
    if not _wants_atomium(OS.get_cmdline_user_args()):
        return
    call_deferred("_mount_district")

func _wants_atomium(args: PackedStringArray) -> bool:
    for arg: String in args:
        if arg.strip_edges().to_lower() == "spawn=atomium":
            return true
    return false

func _world_root() -> Node3D:
    for _frame: int in range(60):
        var main := get_tree().root.find_child("Main", false, false) as Node3D
        if main != null:
            return main
        await get_tree().process_frame
    return null

func _mount_district() -> void:
    var world := await _world_root()
    if world == null:
        push_error("AtomiumHeyselDirectSpawnBootstrap: world root unavailable")
        return
    if world.get_node_or_null("AtomiumHeyselDistrictRuntime") != null:
        return
    var district := DISTRICT_RUNTIME.new()
    district.name = "AtomiumHeyselDistrictRuntime"
    district.build_collision = true
    world.add_child(district)
    await get_tree().process_frame
    if not bool(district.get("runtime_loaded")):
        push_error("AtomiumHeyselDirectSpawnBootstrap: district runtime failed to load")
        return
    var stats: Dictionary = district.get("last_stats")
    if int(stats.get("buildings", 0)) <= 0 or int(stats.get("street_surfaces", 0)) <= 0 or int(stats.get("street_axes", 0)) <= 0:
        push_error("AtomiumHeyselDirectSpawnBootstrap: required district layers are empty")
        return
    print("ATOMIUM_HEYSEL_DIRECT_CONTEXT_READY: %s" % JSON.stringify(stats))
