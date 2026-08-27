extends SceneTree

const RUNTIME_ALIAS := "BrusselsBaseGroundSurfaceRuntime"
const RUNTIME_SCRIPT := preload("res://game/scripts/brussels_base_ground_surface_runtime.gd")
const MATERIAL_FAMILY := "brussels_base_ground_surface_v1"
const EXPECTED_POSITION := Vector3(0.0, -0.23, 0.0)
const EXPECTED_SIZE := Vector3(1800.0, 0.4, 1800.0)

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BRUSSELS_BASE_GROUND_MATERIAL_TEARDOWN_FAIL: %s" % message)
    quit(1)

func _remove_canonical_runtime() -> void:
    var canonical := root.get_node_or_null(RUNTIME_ALIAS)
    if canonical == null:
        return
    root.remove_child(canonical)
    canonical.free()

func _build_fixture() -> Dictionary:
    var main := Node3D.new()
    main.name = "Main"

    var ground := CSGBox3D.new()
    ground.name = "Ground"
    ground.position = EXPECTED_POSITION
    ground.size = EXPECTED_SIZE
    ground.use_collision = true
    var legacy_material := StandardMaterial3D.new()
    legacy_material.set_meta("material_family", "test_legacy_base_ground")
    ground.material = legacy_material
    main.add_child(ground)

    for anchor_name: String in ["BrusselsOSM", "UrbISMidiExact", "Player"]:
        var anchor := Node3D.new()
        anchor.name = anchor_name
        main.add_child(anchor)

    return {
        "main": main,
        "ground": ground,
        "legacy_material": legacy_material,
        "ground_transform": ground.transform,
        "ground_size": ground.size,
    }

func _mount_case(label: String) -> Dictionary:
    var fixture := _build_fixture()
    var main := fixture["main"] as Node3D
    var runtime := RUNTIME_SCRIPT.new() as Node
    root.add_child(main)
    root.add_child(runtime)
    print("BRUSSELS_BASE_GROUND_MATERIAL_TEARDOWN_PHASE: case=%s phase=bind" % label)
    runtime.call("_try_bind_main", main)
    fixture["runtime"] = runtime
    fixture["owned_material"] = (fixture["ground"] as CSGBox3D).material
    return fixture

func _assert_bound(case: Dictionary) -> bool:
    var runtime := case["runtime"] as Node
    var ground := case["ground"] as CSGBox3D
    if runtime == null or ground == null:
        _fail("test fixture missing runtime or Ground")
        return false
    if not bool(runtime.call("ready_complete")) or bool(runtime.call("failed")):
        _fail("base-ground runtime did not bind deterministic production-shaped fixture")
        return false
    var owned := case["owned_material"] as Material
    if owned == null or ground.material != owned:
        _fail("base-ground runtime did not retain exact owned material identity")
        return false
    if str(owned.get_meta("material_family", "")) != MATERIAL_FAMILY:
        _fail("base-ground material family mismatch before teardown")
        return false
    return true

func _cleanup_case(case: Dictionary) -> void:
    var runtime := case["runtime"] as Node
    var main := case["main"] as Node3D
    if runtime != null and is_instance_valid(runtime):
        if runtime.get_parent() != null:
            runtime.get_parent().remove_child(runtime)
        runtime.free()
    if main != null and is_instance_valid(main):
        if main.get_parent() != null:
            main.get_parent().remove_child(main)
        main.free()

func _run() -> void:
    _remove_canonical_runtime()

    var restore_case := _mount_case("restore")
    if not _assert_bound(restore_case):
        return
    var restore_runtime := restore_case["runtime"] as Node
    var restore_ground := restore_case["ground"] as CSGBox3D
    var restore_transform: Transform3D = restore_case["ground_transform"]
    var restore_size: Vector3 = restore_case["ground_size"]
    print("BRUSSELS_BASE_GROUND_MATERIAL_TEARDOWN_PHASE: case=restore phase=remove")
    root.remove_child(restore_runtime)
    if restore_ground.material != restore_case["legacy_material"]:
        _fail("base-ground runtime left its V6 material behind after teardown")
        return
    if not restore_ground.transform.is_equal_approx(restore_transform):
        _fail("Ground transform changed during material ownership teardown")
        return
    if not restore_ground.size.is_equal_approx(restore_size):
        _fail("Ground size changed during material ownership teardown")
        return
    if not restore_ground.use_collision:
        _fail("Ground collision changed during material ownership teardown")
        return
    _cleanup_case(restore_case)

    var preserve_case := _mount_case("preserve")
    if not _assert_bound(preserve_case):
        return
    var preserve_runtime := preserve_case["runtime"] as Node
    var preserve_ground := preserve_case["ground"] as CSGBox3D
    var preserve_transform: Transform3D = preserve_case["ground_transform"]
    var preserve_size: Vector3 = preserve_case["ground_size"]
    var later_owner := StandardMaterial3D.new()
    later_owner.set_meta("material_family", "test_later_base_ground_owner")
    preserve_ground.material = later_owner
    print("BRUSSELS_BASE_GROUND_MATERIAL_TEARDOWN_PHASE: case=preserve phase=remove")
    root.remove_child(preserve_runtime)
    if preserve_ground.material != later_owner:
        _fail("base-ground teardown overwrote a newer material owner")
        return
    if not preserve_ground.transform.is_equal_approx(preserve_transform):
        _fail("Ground transform changed while preserving newer owner")
        return
    if not preserve_ground.size.is_equal_approx(preserve_size):
        _fail("Ground size changed while preserving newer owner")
        return
    if not preserve_ground.use_collision:
        _fail("Ground collision changed while preserving newer owner")
        return
    _cleanup_case(preserve_case)

    print("BRUSSELS_BASE_GROUND_MATERIAL_TEARDOWN_OK: legacy_restored=true newer_owner_preserved=true geometry_changed=false collision_changed=false family=%s" % MATERIAL_FAMILY)
    quit(0)
