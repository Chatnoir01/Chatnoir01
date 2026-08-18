extends SceneTree

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("GRAND_BRUSSELS_RUNTIME_BOOTSTRAP_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var bootstrap := root.get_node_or_null(NodePath("GrandBrusselsRuntimeBootstrap"))
    if bootstrap == null:
        _fail("autoload missing")
        return
    for _attempt: int in range(180):
        if bool(bootstrap.call("ready_complete")):
            break
        await process_frame
    if not bool(bootstrap.call("ready_complete")):
        _fail("bootstrap did not complete")
        return
    if bool(bootstrap.call("failed")):
        _fail("bootstrap reported failure")
        return
    var expected := int(bootstrap.call("descriptor_count"))
    var loaded := int(bootstrap.call("loaded_count"))
    if expected != loaded:
        _fail("descriptor/load count mismatch: %d != %d" % [expected, loaded])
        return
    var names: Array = bootstrap.call("loaded_names") as Array
    for value: Variant in names:
        var module_name := str(value)
        if root.get_node_or_null(NodePath(module_name)) == null:
            _fail("registered root missing: %s" % module_name)
            return
    print("GRAND_BRUSSELS_RUNTIME_BOOTSTRAP_OK: descriptors=%d loaded=%d root_names_verified=true" % [expected, loaded])
    quit(0)
