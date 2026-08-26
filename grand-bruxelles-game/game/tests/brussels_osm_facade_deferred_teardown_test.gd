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

func _cleanup_runtime(runtime: Node) -> void:
    if runtime != null and is_instance_valid(runtime):
        if runtime.get_parent() != null:
            runtime.get_parent().remove_child(runtime)
        runtime.queue_free()

func _cleanup_viewport(viewport: SubViewport) -> void:
    if viewport != null and is_instance_valid(viewport):
        if viewport.get_parent() != null:
            viewport.get_parent().remove_child(viewport)
        viewport.queue_free()

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
    # facade_surface_ready connection to the base Surface runtime on teardown.
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
    _cleanup_runtime(surface)
    _cleanup_viewport(mount["viewport"] as SubViewport)
    await process_frame

    # Phase 3: a terminal successful bind must also release the cross-runtime
    # facade_surface_ready subscription. It must additionally surrender the
    # material it owns when Articulation is removed while Surface remains alive.
    var success_mount := _build_probe_mount(true)
    var success_building := success_mount["building"] as CSGPolygon3D
    var success_legacy := success_mount["legacy"] as Material
    var success_surface := SURFACE_SCRIPT.new() as Node
    success_surface.name = "BrusselsOsmFacadeSurfaceRuntime"
    root.add_child(success_surface)
    if not await _wait_ready(success_surface, 12):
        _fail("surface did not reach terminal success for signal-cleanup probe")
        return
    var surface_owned_material := success_building.material

    var success_articulation := ARTICULATION_SCRIPT.new() as Node
    success_articulation.name = "BrusselsOsmFacadeArticulationRuntime"
    root.add_child(success_articulation)
    if not await _wait_ready(success_articulation, 12):
        _fail("articulation did not reach terminal success for signal-cleanup probe")
        return
    if success_surface.facade_surface_ready.is_connected(success_articulation._on_base_surface_ready):
        _fail("articulation retained facade_surface_ready after terminal success")
        return
    if tree.node_added.is_connected(success_articulation._on_node_added):
        _fail("articulation retained SceneTree.node_added after terminal success")
        return
    if not bool(success_articulation.call("geometry_unchanged")):
        _fail("terminal signal cleanup changed facade geometry")
        return
    if success_building.material == surface_owned_material:
        _fail("articulation never took material ownership in successful probe")
        return

    root.remove_child(success_articulation)
    if success_building.material != surface_owned_material:
        _fail("articulation material ownership survived teardown")
        return
    if success_building.has_meta("facade_articulation_family"):
        _fail("articulation ownership metadata survived teardown")
        return
    success_articulation.queue_free()

    # Phase 4: articulation teardown must be owner-aware. If a later owner replaces
    # its material before this runtime exits, teardown must not stomp it.
    var owner_aware_articulation := ARTICULATION_SCRIPT.new() as Node
    owner_aware_articulation.name = "BrusselsOsmFacadeArticulationRuntime"
    root.add_child(owner_aware_articulation)
    if not await _wait_ready(owner_aware_articulation, 12):
        _fail("articulation did not reach terminal success for owner-aware probe")
        return
    var later_owner_material := StandardMaterial3D.new()
    later_owner_material.albedo_color = Color(0.17, 0.22, 0.31, 1.0)
    later_owner_material.roughness = 0.67
    success_building.material = later_owner_material
    success_building.set_meta("facade_articulation_family", "later_owner_probe")

    root.remove_child(owner_aware_articulation)
    if success_building.material != later_owner_material:
        _fail("articulation teardown overwrote a later material owner")
        return
    if str(success_building.get_meta("facade_articulation_family", "")) != "later_owner_probe":
        _fail("articulation teardown removed later owner metadata")
        return
    owner_aware_articulation.queue_free()

    # Return the synthetic probe to Surface ownership before testing Surface teardown.
    success_building.material = surface_owned_material
    success_building.remove_meta("facade_articulation_family")

    # Phase 5: Surface itself is also a presentation owner. Removing Surface after
    # a successful bind must restore the exact legacy material and clear only its
    # own metadata. This is deliberately RED on production until Surface gains an
    # owner-aware teardown release path.
    root.remove_child(success_surface)
    if success_building.material != success_legacy:
        _fail("surface material ownership survived teardown")
        return
    if success_building.has_meta("material_family"):
        _fail("surface material-family ownership metadata survived teardown")
        return
    success_surface.queue_free()

    # Phase 6: Surface teardown must also preserve a later material owner.
    var later_surface := SURFACE_SCRIPT.new() as Node
    later_surface.name = "BrusselsOsmFacadeSurfaceRuntime"
    root.add_child(later_surface)
    if not await _wait_ready(later_surface, 12):
        _fail("surface did not reach terminal success for owner-aware teardown probe")
        return
    var later_surface_owner_material := StandardMaterial3D.new()
    later_surface_owner_material.albedo_color = Color(0.28, 0.19, 0.16, 1.0)
    later_surface_owner_material.roughness = 0.73
    success_building.material = later_surface_owner_material
    success_building.set_meta("material_family", "later_surface_owner_probe")
    root.remove_child(later_surface)
    if success_building.material != later_surface_owner_material:
        _fail("surface teardown overwrote a later material owner")
        return
    if str(success_building.get_meta("material_family", "")) != "later_surface_owner_probe":
        _fail("surface teardown removed later owner metadata")
        return
    later_surface.queue_free()

    _cleanup_viewport(success_mount["viewport"] as SubViewport)

    print("BRUSSELS_OSM_FACADE_DEFERRED_TEARDOWN_OK: surface_listener_cleanup=true articulation_listener_cleanup=true base_signal_cleanup=true terminal_signal_cleanup=true articulation_material_owner_cleanup=true surface_material_owner_cleanup=true later_owners_preserved=true post_teardown_ready=false geometry_changed=false")
    quit(0)