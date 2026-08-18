extends Node

## Registry-mounted bridge for Ixelles LABO life.
## It stays idle everywhere else and never creates geography. When the existing
## IxellesDirectMicroSlice appears, it mounts the zone-local life node exactly once.

const LIFE_SCRIPT := preload("res://game/scripts/ixelles_lab_life.gd")
const HUMANOID_VISUAL_SCRIPT := preload("res://game/scripts/humanoid_visual.gd")
const DISABLE_ENV := "GB_IXELLES_LIFE"
const SLICE_NAME := "IxellesDirectMicroSlice"
const LIFE_NAME := "ZoneLife_ixelles"
const CHECK_INTERVAL_S := 0.12
const CIVILIAN_VISUAL_VERSION := "profiled_humanoid_v2"

var _elapsed := 0.0
var _ready_complete := false
var _failed := false
var _mounted_count := 0
var _upgraded_civilian_count := 0
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

func _selector_owns_current_transition() -> bool:
    var selector := get_tree().root.get_node_or_null("ZoneSelectorRuntime")
    return selector != null and bool(selector.get("_busy"))

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
    # The zone selector already owns life_script mounting during a menu travel.
    # Yield to it so the registry bridge never races it into a duplicate node.
    if _selector_owns_current_transition():
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
    print("IXELLES_LAB_LIFE_RUNTIME_READY: mounted=%d civilians_upgraded=%d existing_slice=true geography_expanded=false" % [_mounted_count, _upgraded_civilian_count])

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
    var expected_civilians := int((counts as Dictionary).get("civilians", 0))
    _upgraded_civilian_count = _upgrade_civilian_visuals(life)
    if _upgraded_civilian_count != expected_civilians:
        _fail("Ixelles civilian visual upgrade incomplete: %d/%d" % [_upgraded_civilian_count, expected_civilians])
        return false
    _ready_complete = true
    return true

func _upgrade_civilian_visuals(life: Node) -> int:
    var civilians := life.find_children("IxellesCivilian_*", "Node3D", true, false)
    var upgraded := 0
    for i: int in range(civilians.size()):
        var person := civilians[i] as Node3D
        if person == null:
            continue
        var existing_proxy := person.get_node_or_null("VisualAgent") as NpcAgent
        if existing_proxy != null:
            if str(person.get_meta("visual_profile", "")) == CIVILIAN_VISUAL_VERSION:
                upgraded += 1
            continue

        # Keep the original lightweight boxes as a fail-safe, but hide them once
        # the shared profiled humanoid pipeline has been mounted successfully.
        var legacy_visuals: Array[VisualInstance3D] = []
        for child: Node in person.get_children():
            if child is VisualInstance3D:
                legacy_visuals.append(child as VisualInstance3D)

        var proxy := NpcAgent.new()
        proxy.name = "VisualAgent"
        proxy.role = NpcBehaviorModel.Role.CIVILIAN
        proxy.variation_seed = 1709 + i * 137
        proxy.active = false
        proxy.position = Vector3(0.0, 0.90, 0.0)
        person.add_child(proxy)
        proxy.add_to_group("npc_agent")

        var visual := Node3D.new()
        visual.name = "HumanoidVisual"
        visual.set_script(HUMANOID_VISUAL_SCRIPT)
        proxy.add_child(visual)
        if visual.get_node_or_null("Torso") == null or visual.get_node_or_null("Head") == null:
            proxy.queue_free()
            continue

        for legacy: VisualInstance3D in legacy_visuals:
            legacy.visible = false
        person.set_meta("visual_profile", CIVILIAN_VISUAL_VERSION)
        person.set_meta("legacy_visuals_hidden", legacy_visuals.size())
        person.set_meta("shared_humanoid_pipeline", true)
        upgraded += 1
    return upgraded

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

func upgraded_civilian_count() -> int:
    return _upgraded_civilian_count
