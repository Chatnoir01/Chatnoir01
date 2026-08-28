extends SceneTree

const RUNTIME_SCRIPT := preload("res://game/scripts/midi_fonsny_full_entrance_runtime.gd")
const VISIBILITY_OWNER_META := "fonsny_visibility_owner"

class ParentRuntime:
    extends Node
    var parent_ready := false
    func ready_complete() -> bool:
        return parent_ready
    func identity_failure() -> bool:
        return false

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    if not _prove_owned_root_is_released_without_unhiding_prehidden_baseline():
        return
    if not _prove_later_visibility_owner_survives_teardown():
        return
    if not await _prove_deferred_wait_stops_after_teardown():
        return
    print("MIDI_FONSNY_FULL_ENTRANCE_TEARDOWN_OK")
    quit(0)

func _prove_owned_root_is_released_without_unhiding_prehidden_baseline() -> bool:
    var parent := ParentRuntime.new()
    parent.name = "ConcreteOwner"
    get_root().add_child(parent)
    var entrance := Node3D.new()
    entrance.name = "MidiMainEntranceFonsny"
    get_root().add_child(entrance)
    var baseline := Node3D.new()
    baseline.name = "EntranceConcreteCanopy"
    baseline.visible = false
    entrance.add_child(baseline)
    var replacement := Node3D.new()
    replacement.name = "EntranceSourceBackedFonsnyPorch"
    entrance.add_child(replacement)
    var runtime := RUNTIME_SCRIPT.new()
    parent.add_child(runtime)
    runtime.set("_entrance", entrance)
    runtime.set("_replacement", replacement)
    var superseded: Array = runtime.get("_superseded") as Array
    superseded.append(baseline)
    runtime.set("_built", true)
    runtime.set_replacement_enabled(true)
    print("FONSNY_TEARDOWN_FIXTURE: removing built runtime with pre-hidden baseline")
    parent.remove_child(runtime)
    if replacement.get_parent() != null:
        return _fail("owned Fonsny replacement root survived runtime teardown")
    if baseline.visible:
        return _fail("pre-hidden baseline Fonsny entrance was incorrectly forced visible at teardown")
    if baseline.has_meta(VISIBILITY_OWNER_META):
        return _fail("Fonsny visibility ownership metadata survived runtime teardown")
    runtime.queue_free()
    parent.queue_free()
    entrance.queue_free()
    return true

func _prove_later_visibility_owner_survives_teardown() -> bool:
    var parent := ParentRuntime.new()
    parent.name = "ConcreteOwnerLaterVisibility"
    get_root().add_child(parent)
    var entrance := Node3D.new()
    entrance.name = "MidiMainEntranceFonsny"
    get_root().add_child(entrance)
    var baseline := Node3D.new()
    baseline.name = "EntranceConcreteCanopy"
    baseline.visible = true
    entrance.add_child(baseline)
    var replacement := Node3D.new()
    replacement.name = "EntranceSourceBackedFonsnyPorch"
    entrance.add_child(replacement)
    var runtime := RUNTIME_SCRIPT.new()
    parent.add_child(runtime)
    runtime.set("_entrance", entrance)
    runtime.set("_replacement", replacement)
    var superseded: Array = runtime.get("_superseded") as Array
    superseded.append(baseline)
    runtime.set("_built", true)
    runtime.set_replacement_enabled(true)
    baseline.set_meta(VISIBILITY_OWNER_META, "later_owner")
    baseline.visible = false
    print("FONSNY_TEARDOWN_FIXTURE: removing runtime after later visibility owner")
    parent.remove_child(runtime)
    if baseline.visible:
        return _fail("later visibility owner was overwritten during Fonsny teardown")
    if str(baseline.get_meta(VISIBILITY_OWNER_META, "")) != "later_owner":
        return _fail("later visibility owner metadata was overwritten during Fonsny teardown")
    runtime.queue_free()
    parent.queue_free()
    entrance.queue_free()
    return true

func _prove_deferred_wait_stops_after_teardown() -> bool:
    var parent := ParentRuntime.new()
    parent.name = "ConcreteOwnerDeferred"
    get_root().add_child(parent)
    var runtime := RUNTIME_SCRIPT.new()
    parent.add_child(runtime)
    await process_frame
    print("FONSNY_TEARDOWN_FIXTURE: removing waiting runtime")
    parent.remove_child(runtime)
    await process_frame
    await process_frame
    if runtime.build_failure():
        return _fail("deferred Fonsny wait mutated failure state after teardown")
    if runtime.built():
        return _fail("deferred Fonsny wait built after teardown")
    runtime.queue_free()
    parent.queue_free()
    return true

func _fail(message: String) -> bool:
    push_error("MIDI_FONSNY_FULL_ENTRANCE_TEARDOWN_FAIL: " + message)
    quit(1)
    return false
