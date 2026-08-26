extends SceneTree

const RUNTIME_ALIAS := "BrusselsOsmRoadSurfaceRuntime"
const RUNTIME_SCRIPT := preload("res://game/scripts/brussels_osm_road_surface_runtime.gd")
const MATERIAL_FAMILY := "brussels_osm_road_surface_v1"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BRUSSELS_OSM_ROAD_MATERIAL_TEARDOWN_FAIL: %s" % message)
    quit(1)

func _first_road(scene: Node3D) -> CSGBox3D:
    var roads_root := scene.get_node_or_null("BrusselsOSM/GeneratedRoads") as Node3D
    if roads_root == null:
        return null
    for child: Node in roads_root.get_children():
        if child is CSGBox3D and str(child.name).begins_with("Road_"):
            return child as CSGBox3D
    return null

func _remove_canonical_runtime() -> void:
    var canonical := root.get_node_or_null(RUNTIME_ALIAS)
    if canonical == null:
        return
    root.remove_child(canonical)
    canonical.queue_free()
    await process_frame

func _mount_case() -> Dictionary:
    var packed := load("res://game/main.tscn") as PackedScene
    if packed == null:
        return {}
    var scene := packed.instantiate() as Node3D
    if scene == null:
        return {}
    var road := _first_road(scene)
    if road == null:
        scene.queue_free()
        return {}
    var legacy_material: Material = road.material
    var original_transform := road.global_transform
    var original_size := road.size
    var runtime := RUNTIME_SCRIPT.new() as Node
    root.add_child(runtime)
    root.add_child(scene)
    for _frame: int in range(8):
        await process_frame
    return {
        "scene": scene,
        "runtime": runtime,
        "road": road,
        "legacy_material": legacy_material,
        "original_transform": original_transform,
        "original_size": original_size,
    }

func _assert_bound(case: Dictionary) -> bool:
    var runtime := case["runtime"] as Node
    var road := case["road"] as CSGBox3D
    if runtime == null or road == null:
        _fail("test fixture missing runtime or road")
        return false
    if not bool(runtime.call("ready_complete")) or bool(runtime.call("failed")):
        _fail("road surface runtime did not bind production roads")
        return false
    if int(runtime.call("applied_road_count")) <= 0:
        _fail("road runtime reported no owned road registry before teardown")
        return false
    var material := road.material
    if material == null or str(material.get_meta("material_family", "")) != MATERIAL_FAMILY:
        _fail("road did not receive shared road material before teardown")
        return false
    return true

func _assert_teardown_registry_cleared(runtime: Node) -> bool:
    if int(runtime.call("applied_road_count")) != 0:
        _fail("road registry survived synchronous teardown")
        return false
    if int(runtime.call("official_applied_road_count")) != 0:
        _fail("official road registry survived synchronous teardown")
        return false
    return true

func _run() -> void:
    await _remove_canonical_runtime()

    var restore_case := await _mount_case()
    if restore_case.is_empty() or not _assert_bound(restore_case):
        return
    var restore_runtime := restore_case["runtime"] as Node
    var restore_scene := restore_case["scene"] as Node3D
    var restore_road := restore_case["road"] as CSGBox3D
    var legacy_material := restore_case["legacy_material"] as Material
    root.remove_child(restore_runtime)
    if not _assert_teardown_registry_cleared(restore_runtime):
        return
    if restore_road.material != legacy_material:
        _fail("road runtime left its shared material behind after teardown")
        return
    if not restore_road.global_transform.is_equal_approx(restore_case["original_transform"] as Transform3D):
        _fail("road transform changed during material teardown")
        return
    if not restore_road.size.is_equal_approx(restore_case["original_size"] as Vector3):
        _fail("road size changed during material teardown")
        return
    restore_runtime.queue_free()
    root.remove_child(restore_scene)
    restore_scene.queue_free()
    await process_frame

    var preserve_case := await _mount_case()
    if preserve_case.is_empty() or not _assert_bound(preserve_case):
        return
    var preserve_runtime := preserve_case["runtime"] as Node
    var preserve_scene := preserve_case["scene"] as Node3D
    var preserve_road := preserve_case["road"] as CSGBox3D
    var later_owner := StandardMaterial3D.new()
    later_owner.set_meta("material_family", "test_later_owner")
    preserve_road.material = later_owner
    root.remove_child(preserve_runtime)
    if not _assert_teardown_registry_cleared(preserve_runtime):
        return
    if preserve_road.material != later_owner:
        _fail("road teardown overwrote a newer material owner")
        return
    if not preserve_road.global_transform.is_equal_approx(preserve_case["original_transform"] as Transform3D):
        _fail("road transform changed while preserving newer owner")
        return
    if not preserve_road.size.is_equal_approx(preserve_case["original_size"] as Vector3):
        _fail("road size changed while preserving newer owner")
        return
    preserve_runtime.queue_free()
    root.remove_child(preserve_scene)
    preserve_scene.queue_free()

    print("BRUSSELS_OSM_ROAD_MATERIAL_TEARDOWN_OK: legacy_restored=true newer_owner_preserved=true registries_cleared=true geometry_changed=false")
    quit(0)
