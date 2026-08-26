extends SceneTree

const RUNTIME_ALIAS := "BrusselsOsmSidewalkSurfaceRuntime"
const RUNTIME_SCRIPT := preload("res://game/scripts/brussels_osm_sidewalk_surface_runtime.gd")
const MATERIAL_FAMILY := "brussels_osm_sidewalk_surface_v1"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BRUSSELS_OSM_SIDEWALK_MATERIAL_TEARDOWN_FAIL: %s" % message)
    quit(1)

func _remove_canonical_runtime() -> void:
    var canonical := root.get_node_or_null(RUNTIME_ALIAS)
    if canonical == null:
        return
    root.remove_child(canonical)
    canonical.free()

func _build_fixture() -> Dictionary:
    var scene := Node3D.new()
    scene.name = "SidewalkMaterialOwnershipFixture"

    var osm_root := Node3D.new()
    osm_root.name = "BrusselsOSM"
    scene.add_child(osm_root)

    var roads_root := Node3D.new()
    roads_root.name = "GeneratedRoads"
    osm_root.add_child(roads_root)

    var sidewalk := CSGBox3D.new()
    sidewalk.name = "Sidewalk_359177328_0_left"
    sidewalk.size = Vector3(1.85, 0.12, 12.0)
    sidewalk.position = Vector3(4.0, 0.06, -1.0)
    var legacy_material := StandardMaterial3D.new()
    legacy_material.set_meta("material_family", "test_legacy_sidewalk")
    sidewalk.material = legacy_material
    roads_root.add_child(sidewalk)

    var official_parent := Node3D.new()
    official_parent.name = "OfficialIxellesStreetSurfaces"
    scene.add_child(official_parent)

    var official := MeshInstance3D.new()
    official.name = "StreetSurfaces_SW"
    var official_legacy := StandardMaterial3D.new()
    official_legacy.set_meta("material_family", "test_legacy_official_sidewalk")
    official.material_override = official_legacy
    official_parent.add_child(official)

    return {
        "scene": scene,
        "roads_root": roads_root,
        "sidewalk": sidewalk,
        "legacy_material": legacy_material,
        "sidewalk_transform": sidewalk.transform,
        "sidewalk_size": sidewalk.size,
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
    print("BRUSSELS_OSM_SIDEWALK_MATERIAL_TEARDOWN_PHASE: case=%s phase=bind" % label)
    runtime.call("_bind_sidewalks_root", roads_root)
    fixture["runtime"] = runtime
    return fixture

func _assert_bound(case: Dictionary) -> bool:
    var runtime := case["runtime"] as Node
    var sidewalk := case["sidewalk"] as CSGBox3D
    var official := case["official"] as MeshInstance3D
    if runtime == null or sidewalk == null or official == null:
        _fail("test fixture missing runtime, generic sidewalk, or official sidewalk surface")
        return false
    if not bool(runtime.call("ready_complete")) or bool(runtime.call("failed")):
        _fail("sidewalk surface runtime did not bind deterministic fixture")
        return false
    if int(runtime.call("applied_sidewalk_count")) != 1:
        _fail("generic sidewalk ownership registry mismatch before teardown")
        return false
    if int(runtime.call("official_applied_sidewalk_count")) != 1:
        _fail("official sidewalk ownership registry mismatch before teardown")
        return false
    var material := sidewalk.material
    if material == null or str(material.get_meta("material_family", "")) != MATERIAL_FAMILY:
        _fail("generic sidewalk did not receive shared material before teardown")
        return false
    if str(official.get_meta("ground_network_presentation_family", "")).is_empty():
        _fail("official sidewalk did not receive owned presentation before teardown")
        return false
    return true

func _assert_registry_cleared(runtime: Node) -> bool:
    if int(runtime.call("applied_sidewalk_count")) != 0:
        _fail("generic sidewalk registry survived synchronous teardown")
        return false
    if int(runtime.call("official_applied_sidewalk_count")) != 0:
        _fail("official sidewalk registry survived synchronous teardown")
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
    var restore_sidewalk := restore_case["sidewalk"] as CSGBox3D
    var restore_official := restore_case["official"] as MeshInstance3D
    var restore_transform: Transform3D = restore_case["sidewalk_transform"]
    var restore_size: Vector3 = restore_case["sidewalk_size"]
    root.remove_child(restore_runtime)
    if not _assert_registry_cleared(restore_runtime):
        return
    if restore_sidewalk.material != restore_case["legacy_material"]:
        _fail("generic sidewalk runtime left its material behind after teardown")
        return
    if restore_sidewalk.has_meta("material_family"):
        _fail("generic sidewalk material ownership metadata survived teardown")
        return
    if restore_official.material_override != restore_case["official_legacy"]:
        _fail("official sidewalk runtime left its material behind after teardown")
        return
    if restore_official.has_meta("ground_network_presentation_family"):
        _fail("official sidewalk ownership metadata survived teardown")
        return
    if not restore_sidewalk.transform.is_equal_approx(restore_transform) or not restore_sidewalk.size.is_equal_approx(restore_size):
        _fail("generic sidewalk geometry changed during teardown")
        return
    _cleanup_case(restore_case)

    var preserve_case := _mount_case("preserve")
    if not _assert_bound(preserve_case):
        return
    var preserve_runtime := preserve_case["runtime"] as Node
    var preserve_sidewalk := preserve_case["sidewalk"] as CSGBox3D
    var preserve_official := preserve_case["official"] as MeshInstance3D
    var later_sidewalk_owner := StandardMaterial3D.new()
    later_sidewalk_owner.set_meta("material_family", "test_later_sidewalk_owner")
    preserve_sidewalk.material = later_sidewalk_owner
    preserve_sidewalk.set_meta("material_family", "test_later_sidewalk_owner")
    var later_official_owner := StandardMaterial3D.new()
    preserve_official.material_override = later_official_owner
    preserve_official.set_meta("ground_network_presentation_family", "test_later_official_owner")
    root.remove_child(preserve_runtime)
    if not _assert_registry_cleared(preserve_runtime):
        return
    if preserve_sidewalk.material != later_sidewalk_owner or str(preserve_sidewalk.get_meta("material_family", "")) != "test_later_sidewalk_owner":
        _fail("generic sidewalk teardown overwrote a newer material owner")
        return
    if preserve_official.material_override != later_official_owner or str(preserve_official.get_meta("ground_network_presentation_family", "")) != "test_later_official_owner":
        _fail("official sidewalk teardown overwrote a newer material owner")
        return
    _cleanup_case(preserve_case)

    print("BRUSSELS_OSM_SIDEWALK_MATERIAL_TEARDOWN_OK: generic_restored=true official_restored=true newer_owners_preserved=true registries_cleared=true geometry_changed=false deterministic_bind=true")
    quit(0)
