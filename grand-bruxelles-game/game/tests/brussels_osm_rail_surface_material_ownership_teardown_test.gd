extends SceneTree

const RUNTIME_ALIAS := "BrusselsOsmRailSurfaceRuntime"
const RUNTIME_SCRIPT := preload("res://game/scripts/brussels_osm_rail_surface_runtime.gd")
const MATERIAL_FAMILY := "brussels_osm_rail_surface_v1"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BRUSSELS_OSM_RAIL_MATERIAL_TEARDOWN_FAIL: %s" % message)
    quit(1)

func _remove_canonical_runtime() -> void:
    var canonical := root.get_node_or_null(RUNTIME_ALIAS)
    if canonical == null:
        return
    root.remove_child(canonical)
    canonical.free()

func _build_fixture() -> Dictionary:
    var scene := Node3D.new()
    scene.name = "RailMaterialOwnershipFixture"

    var osm_root := Node3D.new()
    osm_root.name = "BrusselsOSM"
    scene.add_child(osm_root)

    var rails_root := Node3D.new()
    rails_root.name = "GeneratedRails"
    osm_root.add_child(rails_root)

    var rail := CSGBox3D.new()
    rail.name = "Rail_359177328_0_0"
    rail.size = Vector3(0.11, 0.08, 8.0)
    rail.position = Vector3(2.0, 0.04, -3.0)
    var legacy_material := StandardMaterial3D.new()
    legacy_material.set_meta("material_family", "test_legacy_rail")
    rail.material = legacy_material
    rails_root.add_child(rail)

    var official := MeshInstance3D.new()
    official.name = "JetteOfficialTramNetwork"
    var official_legacy := StandardMaterial3D.new()
    official_legacy.set_meta("material_family", "test_legacy_official_rail")
    official.material_override = official_legacy
    scene.add_child(official)

    return {
        "scene": scene,
        "rails_root": rails_root,
        "rail": rail,
        "legacy_material": legacy_material,
        "rail_transform": rail.transform,
        "rail_size": rail.size,
        "official": official,
        "official_legacy": official_legacy,
    }

func _mount_case(label: String) -> Dictionary:
    var fixture := _build_fixture()
    var scene := fixture["scene"] as Node3D
    var rails_root := fixture["rails_root"] as Node3D
    var runtime := RUNTIME_SCRIPT.new() as Node
    root.add_child(scene)
    root.add_child(runtime)
    print("BRUSSELS_OSM_RAIL_MATERIAL_TEARDOWN_PHASE: case=%s phase=bind" % label)
    runtime.call("_bind_rails_root", rails_root)
    fixture["runtime"] = runtime
    return fixture

func _assert_bound(case: Dictionary) -> bool:
    var runtime := case["runtime"] as Node
    var rail := case["rail"] as CSGBox3D
    var official := case["official"] as MeshInstance3D
    if runtime == null or rail == null or official == null:
        _fail("test fixture missing runtime, generic rail, or official rail surface")
        return false
    if not bool(runtime.call("ready_complete")) or bool(runtime.call("failed")):
        _fail("rail surface runtime did not bind deterministic fixture")
        return false
    if int(runtime.call("applied_rail_count")) != 1:
        _fail("generic rail ownership registry mismatch before teardown")
        return false
    if int(runtime.call("official_applied_rail_count")) != 1:
        _fail("official rail ownership registry mismatch before teardown")
        return false
    var material := rail.material
    if material == null or str(material.get_meta("material_family", "")) != MATERIAL_FAMILY:
        _fail("generic rail did not receive shared material before teardown")
        return false
    if str(official.get_meta("ground_network_presentation_family", "")).is_empty():
        _fail("official rail did not receive owned presentation before teardown")
        return false
    return true

func _assert_registry_cleared(runtime: Node) -> bool:
    if int(runtime.call("applied_rail_count")) != 0:
        _fail("generic rail ownership registry survived teardown")
        return false
    if int(runtime.call("official_applied_rail_count")) != 0:
        _fail("official rail ownership registry survived teardown")
        return false
    return true

func _cleanup_case(case: Dictionary) -> void:
    var scene := case["scene"] as Node3D
    if scene != null and is_instance_valid(scene):
        if scene.get_parent() != null:
            scene.get_parent().remove_child(scene)
        scene.free()

func _run() -> void:
    _remove_canonical_runtime()

    var restore_case := _mount_case("restore_legacy")
    if not _assert_bound(restore_case):
        return
    var runtime := restore_case["runtime"] as Node
    var rail := restore_case["rail"] as CSGBox3D
    var official := restore_case["official"] as MeshInstance3D
    var legacy_material := restore_case["legacy_material"] as Material
    var official_legacy := restore_case["official_legacy"] as Material
    var original_transform: Transform3D = restore_case["rail_transform"]
    var original_size: Vector3 = restore_case["rail_size"]

    root.remove_child(runtime)
    if not _assert_registry_cleared(runtime):
        return
    if rail.material != legacy_material:
        _fail("generic rail legacy material was not restored synchronously at teardown")
        return
    if official.material_override != official_legacy:
        _fail("official rail legacy presentation was not restored synchronously at teardown")
        return
    if rail.has_meta("material_family"):
        _fail("generic rail material ownership metadata survived teardown")
        return
    if official.has_meta("ground_network_presentation_family"):
        _fail("official rail presentation ownership metadata survived teardown")
        return
    if not rail.transform.is_equal_approx(original_transform) or not rail.size.is_equal_approx(original_size):
        _fail("rail geometry changed during teardown ownership restoration")
        return
    runtime.free()
    _cleanup_case(restore_case)

    var preserve_case := _mount_case("preserve_later_owner")
    if not _assert_bound(preserve_case):
        return
    runtime = preserve_case["runtime"] as Node
    rail = preserve_case["rail"] as CSGBox3D
    official = preserve_case["official"] as MeshInstance3D
    original_transform = preserve_case["rail_transform"]
    original_size = preserve_case["rail_size"]

    var later_generic := StandardMaterial3D.new()
    later_generic.set_meta("material_family", "test_later_generic_owner")
    rail.material = later_generic
    rail.set_meta("material_family", "test_later_generic_owner")
    var later_official := StandardMaterial3D.new()
    later_official.set_meta("material_family", "test_later_official_owner")
    official.material_override = later_official
    official.set_meta("ground_network_presentation_family", "test_later_official_owner")

    root.remove_child(runtime)
    if not _assert_registry_cleared(runtime):
        return
    if rail.material != later_generic or str(rail.get_meta("material_family", "")) != "test_later_generic_owner":
        _fail("generic rail teardown overwrote a later material owner")
        return
    if official.material_override != later_official or str(official.get_meta("ground_network_presentation_family", "")) != "test_later_official_owner":
        _fail("official rail teardown overwrote a later presentation owner")
        return
    if not rail.transform.is_equal_approx(original_transform) or not rail.size.is_equal_approx(original_size):
        _fail("rail geometry changed while preserving later owner")
        return

    runtime.free()
    _cleanup_case(preserve_case)
    print("BRUSSELS_OSM_RAIL_MATERIAL_TEARDOWN_OK: generic=1 official=1 legacy_restored=true later_owner_preserved=true geometry_changed=false source=OSM license=ODbL-1.0")
    quit(0)
