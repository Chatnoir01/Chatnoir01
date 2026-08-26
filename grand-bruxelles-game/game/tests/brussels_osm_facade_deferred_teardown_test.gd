extends SceneTree

const SURFACE_SCRIPT := preload("res://game/scripts/brussels_osm_facade_surface_runtime.gd")
const ARTICULATION_SCRIPT := preload("res://game/scripts/brussels_osm_facade_articulation_runtime.gd")

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BRUSSELS_OSM_FACADE_DEFERRED_TEARDOWN_FAIL: %s" % message)
    quit(1)

func _remove_canonical(name: String) -> void:
    var node := root.get_node_or_null(name)
    if node != null:
        root.remove_child(node)
        node.queue_free()

func _build_probe_mount(with_building: bool) -> Dictionary:
    var viewport := SubViewport.new()
    viewport.name = "FacadeTeardownViewport"
    root.add_child(viewport)

    var main := Node3D.new()
    main.name = "Main"
    viewport.add_child(main)

    var osm := Node3D.new()
    osm.name = "BrusselsOSM"
    main.add_child(osm)

    var buildings := Node3D.new()
    buildings.name = "GeneratedBuildings"
    osm.add_child(buildings)

    var result := {
        "viewport": viewport,
        "buildings": buildings,
    }
    if not with_building:
        return result

    var building := CSGPolygon3D.new()
    building.name = "Building_FacadeTeardownProbe"
    building.polygon = PackedVector2Array([
        Vector2(-1.0, 0.0),
        Vector2(1.0, 0.0),
        Vector2(1.0, 2.0),
        Vector2(-1.0, 2.0),
    ])
    building.depth = 0.20
    var legacy := StandardMaterial3D.new()
    legacy.albedo_color = Color(0.42, 0.37, 0.32, 1.0)
    legacy.roughness = 0.82
    building.material = legacy
    buildings.add_child(building)
    result["building"] = building
    result["legacy"] = legacy
    return result

func _wait_ready(runtime: Node, frames: int = 8) -> bool:
    for _index in range(frames):
        await process_frame
        if bool(runtime.call("ready_complete")):
            return not bool(runtime.call("failed"))
    return false

func _run() -> void:
    _remove_canonical("BrusselsOsmFacadeArticulationRuntime")
    _remove_canonical("BrusselsOsmFacadeSurfaceRuntime")
    await process_frame

    # This script extends SceneTree, so self is the tree. get_tree() belongs
    # to Node and would fail this witness at parse time before runtime checks.
    var tree: SceneTree = self

    # Phase 1: Surface owns a SceneTree.node_added listener while waiting.
    # Teardown must synchronously disconnect it, even if its deferred bind has not run.
    var surface_probe := SURFACE_SCRIPT.new() as Node
    root.add_child(surface_probe)
    if not tree.node_added.is_connected(surface_probe._on_node_added):
        _fail("surface listener was not connected before teardown")
        return
    root.remove_child(surface_probe)
    if tree.node_added.is_connected(surface_probe._on_node_added):
        _fail("surface retained SceneTree.node_added listener after teardown")
        return
    await process_frame
    if bool(surface_probe.call("ready_complete")):
        _fail("surface became ready after teardown")
        return
    surface_probe.queue_free()

    # Phase 2: Articulation must clean both SceneTree.node_added and its
    # facade_surface_ready connection to the base Surface runtime.
    var mount := _build_probe_mount(false)
    var surface := SURFACE_SCRIPT.new() as Node
    surface.name = "BrusselsOsmFacadeSurfaceRuntime"
    root.add_child(surface)
    await process_frame
    if bool(surface.call("ready_complete")):
        _fail("surface unexpectedly ready without buildings")
        return

    var articulation := ARTICULATION_SCRIPT.new() as Node
    articulation.name = "BrusselsOsmFacadeArticulationRuntime"
    root.add_child(articulation)
    await process_frame
    if not tree.node_added.is_connected(articulation._on_node_added):
        _fail("articulation listener was not connected before teardown")
        return
    if not surface.facade_surface_ready.is_connected(articulation._on_base_surface_ready):
        _fail("articulation did not connect base-runtime signal before teardown")
        return

    root.remove_child(articulation)
    if tree.node_added.is_connected(articulation._on_node_added):
        _fail("articulation retained SceneTree.node_added listener after teardown")
        return
    if surface.facade_surface_ready.is_connected(articulation._on_base_surface_ready):
        _fail("articulation retained facade_surface_ready signal after teardown")
        return
    await process_frame
    if bool(articulation.call("ready_complete")):
        _fail("articulation became ready after teardown")
        return

    articulation.queue_free()
    root.remove_child(surface)
    surface.queue_free()
    var viewport := mount["viewport"] as SubViewport
    root.remove_child(viewport)
    viewport.queue_free()

    print("BRUSSELS_OSM_FACADE_DEFERRED_TEARDOWN_OK: surface_listener_cleanup=true articulation_listener_cleanup=true base_signal_cleanup=true post_teardown_ready=false")
    quit(0)