extends SceneTree

const RUNTIME_ALIAS := "BrusselsOsmRoadSurfaceRuntime"
const RUNTIME_SCRIPT := preload("res://game/scripts/brussels_osm_road_surface_runtime.gd")
const MATERIAL_FAMILY := "brussels_osm_road_surface_v1"
const TEST_OSM_ID := 359177328

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BRUSSELS_OSM_ROAD_MATERIAL_TEARDOWN_FAIL: %s" % message)
    quit(1)

func _remove_canonical_runtime() -> void:
    var canonical := root.get_node_or_null(RUNTIME_ALIAS)
    if canonical == null:
        return
    root.remove_child(canonical)
    canonical.free()

func _build_fixture() -> Dictionary:
    var scene := Node3D.new()
    scene.name = "RoadMaterialOwnershipFixture"

    var osm_root := Node3D.new()
    osm_root.name = "BrusselsOSM"
    scene.add_child(osm_root)

    var roads_root := Node3D.new()
    roads_root.name = "GeneratedRoads"
    osm_root.add_child(roads_root)

    var road := CSGBox3D.new()
    road.name = "Road_%d_0_0" % TEST_OSM_ID
    road.size = Vector3(12.0, 0.15, 4.0)
    road.position = Vector3(3.0, 0.075, -2.0)
    var legacy_material := StandardMaterial3D.new()
    legacy_material.set_meta("material_family", "test_legacy_road")
    road.material = legacy_material
    roads_root.add_child(road)

    var official_parent := Node3D.new()
    official_parent.name = "OfficialIxellesStreetSurfaces"
    scene.add_child(official_parent)

    var official := MeshInstance3D.new()
    official.name = "StreetSurfaces_S"
    var official_legacy := StandardMaterial3D.new()
    official_legacy.set_meta("material_family", "test_legacy_official")
    official.material_override = official_legacy
    official_parent.add_child(official)

    return {
        "scene": scene,
        "roads_root": roads_root,
        "road": road,
        "legacy_material": legacy_material,
        "road_transform": road.transform,
        "road_size": road.size,
        "official": official,
        "official_legacy": official_legacy,
    }

func _mount_case(label: String) -> Dictionary:
    var fixture := _build_fixture()
    var scene := fixture["scene"] as Node3D
    var roads_root := fixture["roads_root"] as Node3D
    var runtime := RUNTIME_SCRIPT.new() as Node
    root.add_child(scene)
    root.add_child(runtime)
    print("BRUSSELS_OSM_ROAD_MATERIAL_TEARDOWN_PHASE: case=%s phase=bind" % label)
    runtime.call("_bind_roads_root", roads_root)
    fixture["runtime"] = runtime
    return fixture

func _assert_bound(case: Dictionary) -> bool:
    var runtime := case["runtime"] as Node
    var road := case["road"] as CSGBox3D
    var official := case["official"] as MeshInstance3D
    if runtime == null or road == null or official == null:
        _fail("test fixture missing runtime, generic road, or official road surface")
        return false
    if not bool(runtime.call("ready_complete")) or bool(runtime.call("failed")):
        _fail("road surface runtime did not bind deterministic source-backed road fixture")
        return false
    if int(runtime.call("applied_road_count")) != 1:
        _fail("generic road ownership registry mismatch before teardown")
        return false
    if int(runtime.call("official_applied_road_count")) != 1:
        _fail("official road ownership registry mismatch before teardown")
        return false
    var material := road.material
    if material == null or str(material.get_meta("material_family", "")) != MATERIAL_FAMILY:
        _fail("generic road did not receive shared road material before teardown")
        return false
    if str(official.get_meta("ground_network_presentation_family", "")).is_empty():
        _fail("official road surface did not receive owned presentation before teardown")
        return false
    return true

func _assert_teardown_registry_cleared(runtime: Node) -> bool:
    if int(runtime.call("applied_road_count")) != 0:
        _fail("generic road registry survived synchronous teardown")
        return false
    if int(runtime.call("official_applied_road_count")) != 0:
        _fail("official road registry survived synchronous teardown")
        return false
    return true

func _cleanup_case(case: Dictionary) -> void:
    var runtime := case["runtime"] as Node
    var scene := case["scene"] as Node3D
    if runtime != null and is_instance_valid(runtime):
        if runtime.get_parent() != null:
            runtime.get_parent().remove_child(runtime)
        runtime.free()
    if scene != null and is_instance_valid(scene):
        if scene.get_parent() != null:
            scene.get_parent().remove_child(scene)
        scene.free()

func _run() -> void:
    _remove_canonical_runtime()

    var restore_case := _mount_case("restore")
    if not _assert_bound(restore_case):
        return
    var restore_runtime := restore_case["runtime"] as Node
    var restore_road := restore_case["road"] as CSGBox3D
    var restore_official := restore_case["official"] as MeshInstance3D
    var restore_transform: Transform3D = restore_case["road_transform"]
    var restore_size: Vector3 = restore_case["road_size"]
    print("BRUSSELS_OSM_ROAD_MATERIAL_TEARDOWN_PHASE: case=restore phase=remove")
    root.remove_child(restore_runtime)
    if not _assert_teardown_registry_cleared(restore_runtime):
        return
    if restore_road.material != restore_case["legacy_material"] as Material:
        _fail("generic road runtime left its shared material behind after teardown")
        return
    if restore_official.material_override != restore_case["official_legacy"] as Material:
        _fail("official road runtime left its presentation material behind after teardown")
        return
    if restore_official.has_meta("ground_network_presentation_family"):
        _fail("official presentation ownership metadata survived teardown")
        return
    if not restore_road.transform.is_equal_approx(restore_transform):
        _fail("generic road transform changed during material teardown")
        return
    if not restore_road.size.is_equal_approx(restore_size):
        _fail("generic road size changed during material teardown")
        return
    _cleanup_case(restore_case)

    var preserve_case := _mount_case("preserve")
    if not _assert_bound(preserve_case):
        return
    var preserve_runtime := preserve_case["runtime"] as Node
    var preserve_road := preserve_case["road"] as CSGBox3D
    var preserve_official := preserve_case["official"] as MeshInstance3D
    var preserve_transform: Transform3D = preserve_case["road_transform"]
    var preserve_size: Vector3 = preserve_case["road_size"]
    var later_road_owner := StandardMaterial3D.new()
    later_road_owner.set_meta("material_family", "test_later_road_owner")
    preserve_road.material = later_road_owner
    var later_official_owner := StandardMaterial3D.new()
    later_official_owner.set_meta("material_family", "test_later_official_owner")
    preserve_official.material_override = later_official_owner
    preserve_official.set_meta("ground_network_presentation_family", "test_later_official_owner")
    print("BRUSSELS_OSM_ROAD_MATERIAL_TEARDOWN_PHASE: case=preserve phase=remove")
    root.remove_child(preserve_runtime)
    if not _assert_teardown_registry_cleared(preserve_runtime):
        return
    if preserve_road.material != later_road_owner:
        _fail("generic road teardown overwrote a newer material owner")
        return
    if preserve_official.material_override != later_official_owner:
        _fail("official road teardown overwrote a newer material owner")
        return
    if str(preserve_official.get_meta("ground_network_presentation_family", "")) != "test_later_official_owner":
        _fail("official road teardown removed a newer ownership marker")
        return
    if not preserve_road.transform.is_equal_approx(preserve_transform):
        _fail("generic road transform changed while preserving newer owner")
        return
    if not preserve_road.size.is_equal_approx(preserve_size):
        _fail("generic road size changed while preserving newer owner")
        return
    _cleanup_case(preserve_case)

    print("BRUSSELS_OSM_ROAD_MATERIAL_TEARDOWN_OK: fixture_osm_id=%d legacy_restored=true official_restored=true newer_owners_preserved=true registries_cleared=true geometry_changed=false deterministic_bind=true" % TEST_OSM_ID)
    quit(0)
