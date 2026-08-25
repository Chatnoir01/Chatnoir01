extends SceneTree

const EXPECTED_SURFACES := 3

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("MIDI_FAUQUENBERG_DORMANT_MOUNT_FAIL: %s" % message)
    quit(1)

func _make_target(index: int) -> MeshInstance3D:
    var target := MeshInstance3D.new()
    target.name = "FauquenbergBrick"
    target.set_meta("dormant_mount_probe_index", index)
    target.mesh = BoxMesh.new()
    return target

func _run() -> void:
    var runtime := root.get_node_or_null("MidiFauquenbergBrickSurfaceRuntime")
    if runtime == null:
        _fail("MidiFauquenbergBrickSurfaceRuntime autoload missing")
        return

    # The runtime must tolerate a legitimate partial/delayed mount for longer
    # than the historical 120-frame polling budget.
    for _frame: int in range(125):
        await process_frame
    if bool(runtime.call("identity_failure")):
        _fail("Fauquenberg runtime treated absent BruxellesMidiStation as failure")
        return
    if bool(runtime.call("ready_complete")):
        _fail("Fauquenberg runtime completed without a legitimate station mount")
        return

    # Reproduce a nested development/player mount. The station node enters the
    # tree before its material surfaces, so an event-driven runtime must wait a
    # bounded number of frames for subtree population rather than fail on 0/3.
    var viewport := SubViewport.new()
    viewport.name = "DormantFauquenbergMountViewport"
    root.add_child(viewport)
    var main_mount := Node3D.new()
    main_mount.name = "Main"
    viewport.add_child(main_mount)
    var station := Node3D.new()
    station.name = "BruxellesMidiStation"
    main_mount.add_child(station)

    await process_frame
    # Keep the three target names exact without sibling-name auto-renaming by
    # placing each authored surface under its own structural subgroup.
    for index: int in range(EXPECTED_SURFACES):
        var group := Node3D.new()
        group.name = "FauquenbergSurfaceGroup_%d" % index
        station.add_child(group)
        group.add_child(_make_target(index))

    for _frame: int in range(40):
        if bool(runtime.call("ready_complete")):
            break
        await process_frame

    if bool(runtime.call("identity_failure")) or not bool(runtime.call("ready_complete")):
        _fail("Fauquenberg runtime did not bind after legitimate nested station mount")
        return
    if int(runtime.call("applied_surface_count")) != EXPECTED_SURFACES:
        _fail("Fauquenberg target surface count drifted")
        return
    var material := runtime.call("enhanced_material") as ShaderMaterial
    if material == null:
        _fail("Fauquenberg authored material was not restored")
        return

    print("MIDI_FAUQUENBERG_DORMANT_MOUNT_OK: surfaces=%d nested_mount=true dormant_absence=true delayed_subtree=true material_only=true" % EXPECTED_SURFACES)
    quit(0)
