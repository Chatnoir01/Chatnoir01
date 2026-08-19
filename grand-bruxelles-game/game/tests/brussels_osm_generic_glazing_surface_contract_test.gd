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
    for _frame: int in range(360):
        if bool(runtime.call("ready_complete")): break
        await process_frame
    if not bool(runtime.call("ready_complete")) or bool(runtime.call("failed")):
        _fail("generic glazing runtime did not bind cleanly"); return
    if int(runtime.call("shared_material_count")) != 2:
        _fail("expected exactly two shared materials"); return
    if int(runtime.call("applied_instance_count")) < 100:
        _fail("generic glazing instance coverage unexpectedly small"); return
    if int(runtime.call("render_batch_count", "window")) < 1 or int(runtime.call("render_batch_count", "shop")) < 1:
        _fail("rendered glazing batches were not targeted"); return
    if not bool(runtime.call("geometry_unchanged")):
        _fail("geometry invariant failed"); return

    var details := root.find_child("GeneratedFacadeDetails", true, false) as Node3D
    if details == null:
        _fail("GeneratedFacadeDetails missing"); return
    var source_windows := details.get_node_or_null("CorridorFacadeWindows") as MultiMeshInstance3D
    var source_shops := details.get_node_or_null("CorridorShopfronts") as MultiMeshInstance3D
    if source_windows == null or source_shops == null:
        _fail("expected generic source glazing batches missing"); return
    if source_windows.visible or source_shops.visible:
        _fail("legacy source glazing unexpectedly visible; rendered-depth contract changed"); return

    var rendered_targets := 0
    for child: Node in details.get_children():
        if not child is MultiMeshInstance3D:
            continue
        var item := child as MultiMeshInstance3D
        var node_name := str(item.name)
        if not (node_name == "CorridorWindowGlass" or node_name.begins_with("CorridorWindowGlass_") or node_name == "CorridorShopfrontGlass" or node_name.begins_with("CorridorShopfrontGlass_")):
            continue
        rendered_targets += 1
        if str(item.get_meta("source", "")) != "OpenStreetMap contributors via Overpass API":
            _fail("source provenance missing on rendered glazing"); return
        if str(item.get_meta("license", "")) != "ODbL-1.0":
            _fail("license provenance missing on rendered glazing"); return
        if bool(item.get_meta("geometry_changed_by_generic_glazing_runtime", true)):
            _fail("runtime claims geometry change"); return
        if item.material_override == null:
            _fail("candidate is not bound to active rendered material path"); return
    if rendered_targets < 2:
        _fail("rendered generic glazing target set unexpectedly small"); return

    print("BRUSSELS_OSM_GENERIC_GLAZING_OK: rendered_batches=%d instances=%d materials=2 family=brussels_osm_generic_glazing_surface_v1 source=OSM license=ODbL-1.0 geometry_changed=false" % [rendered_targets, int(runtime.call("applied_instance_count"))])
    quit(0)
