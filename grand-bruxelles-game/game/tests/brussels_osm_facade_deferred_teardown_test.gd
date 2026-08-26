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

func _build_probe_mount() -> Dictionary:
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

    return {
        "viewport": viewport,
        "building": building,
        "legacy": legacy,
    }

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

    # Phase 1: a queued Surface _try_apply must not mutate buildings after teardown.
    var first := _build_probe_mount()
    var first_building := first["building"] as CSGPolygon3D
    var first_legacy := first["legacy"] as Material
    var surface_probe := SURFACE_SCRIPT.new() as Node
    root.add_child(surface_probe)
    root.remove_child(surface_probe)
    await process_frame
    await process_frame
    if first_building.material != first_legacy:
        _fail("surface deferred apply mutated material after teardown")
        return
    if first_building.has_meta("material_family"):
        _fail("surface deferred apply wrote metadata after teardown")
        return
    surface_probe.queue_free()
    var first_viewport := first["viewport"] as SubViewport
    root.remove_child(first_viewport)
    first_viewport.queue_free()
    await process_frame

    # Phase 2: Articulation must not override an already-ready Surface after teardown.
    var second := _build_probe_mount()
    var second_building := second["building"] as CSGPolygon3D
    var surface := SURFACE_SCRIPT.new() as Node
    surface.name = "BrusselsOsmFacadeSurfaceRuntime"
    root.add_child(surface)
    if not await _wait_ready(surface):
        _fail("surface baseline did not become ready")
        return
    var surface_material := second_building.material
    if surface_material == null or str(surface_material.get_meta("material_family", "")) != "brussels_osm_facade_surface_v1":
        _fail("surface baseline material missing before articulation probe")
        return

    var articulation := ARTICULATION_SCRIPT.new() as Node
    articulation.name = "BrusselsOsmFacadeArticulationRuntime"
    root.add_child(articulation)
    root.remove_child(articulation)
    await process_frame
    await process_frame
    if second_building.material != surface_material:
        _fail("articulation deferred apply mutated material after teardown")
        return
    if second_building.has_meta("facade_articulation_family"):
        _fail("articulation deferred apply wrote metadata after teardown")
        return
    if surface.has_signal("facade_surface_ready") and surface.facade_surface_ready.is_connected(articulation._on_base_surface_ready):
        _fail("articulation retained base-runtime signal after teardown")
        return

    articulation.queue_free()
    root.remove_child(surface)
    surface.queue_free()
    var second_viewport := second["viewport"] as SubViewport
    root.remove_child(second_viewport)
    second_viewport.queue_free()

    print("BRUSSELS_OSM_FACADE_DEFERRED_TEARDOWN_OK: surface=true articulation=true material_mutation_after_teardown=false retained_base_signal=false")
    quit(0)
