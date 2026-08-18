extends SceneTree

func _fail(message: String) -> void:
    push_error("BRUSSELS_OSM_GENERIC_GLAZING_FAIL: %s" % message)
    quit(1)

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var packed := load("res://game/main.tscn") as PackedScene
    if packed == null:
        _fail("production main scene missing"); return
    var scene := packed.instantiate()
    root.add_child(scene)

    var bootstrap := root.get_node_or_null("GrandBrusselsRuntimeBootstrap")
    if bootstrap == null:
        _fail("runtime bootstrap missing"); return
    for _frame: int in range(300):
        if bool(bootstrap.call("ready_complete")): break
        await process_frame
    if bool(bootstrap.call("failed")):
        _fail("runtime bootstrap failed"); return

    var runtime := root.get_node_or_null("BrusselsOsmGenericGlazingSurfaceRuntime")
    if runtime == null:
        _fail("generic glazing runtime missing"); return
    for _frame: int in range(300):
        if bool(runtime.call("ready_complete")): break
        await process_frame
    if not bool(runtime.call("ready_complete")) or bool(runtime.call("failed")):
        _fail("generic glazing runtime did not bind cleanly"); return
    if int(runtime.call("shared_material_count")) != 2:
        _fail("expected exactly two shared materials"); return
    if int(runtime.call("applied_instance_count")) < 100:
        _fail("generic glazing instance coverage unexpectedly small"); return
    if not bool(runtime.call("geometry_unchanged")):
        _fail("geometry invariant failed"); return

    var details := root.find_child("GeneratedFacadeDetails", true, false) as Node3D
    if details == null:
        _fail("GeneratedFacadeDetails missing"); return
    var windows := details.get_node_or_null("CorridorFacadeWindows") as MultiMeshInstance3D
    var shops := details.get_node_or_null("CorridorShopfronts") as MultiMeshInstance3D
    if windows == null or shops == null:
        _fail("expected generic glazing batches missing"); return
    for item: MultiMeshInstance3D in [windows, shops]:
        if str(item.get_meta("source", "")) != "OpenStreetMap contributors via Overpass API":
            _fail("source provenance missing"); return
        if str(item.get_meta("license", "")) != "ODbL-1.0":
            _fail("license provenance missing"); return
        if bool(item.get_meta("geometry_changed_by_generic_glazing_runtime", true)):
            _fail("runtime claims geometry change"); return

    print("BRUSSELS_OSM_GENERIC_GLAZING_OK: windows=%d shops=%d materials=2 family=brussels_osm_generic_glazing_surface_v1 source=OSM license=ODbL-1.0 geometry_changed=false" % [windows.multimesh.instance_count, shops.multimesh.instance_count])
    quit(0)
