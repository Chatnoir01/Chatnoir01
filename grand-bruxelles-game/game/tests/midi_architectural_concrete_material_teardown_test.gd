extends SceneTree

const RUNTIME := preload("res://game/scripts/midi_architectural_concrete_surface_runtime.gd")
const IDENTITY_PATH := "res://data/visual/midi_architectural_concrete_material_identity.json"
const EXPECTED_SURFACES := 74

var _failures: Array[String] = []

func _init() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    _failures.append(message)
    push_error(message)

func _make_material(label: String, roughness: float) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.resource_name = label
    material.albedo_color = Color(0.36, 0.38, 0.40)
    material.roughness = roughness
    return material

func _make_target(index: int, baseline: Material) -> MeshInstance3D:
    var target := MeshInstance3D.new()
    if index == 0:
        target.name = "VerticalGlassTowerFrame"
    elif index == 1:
        target.name = "EntranceConcreteCanopy"
    else:
        target.name = "HorizontalBand_%02d" % [index - 2]
    var mesh := BoxMesh.new()
    mesh.size = Vector3(1.0 + float(index % 3) * 0.1, 0.25, 0.40)
    target.mesh = mesh
    target.material_override = baseline
    target.transform = Transform3D(Basis.IDENTITY, Vector3(float(index % 12), float(index / 12), -2.0))
    return target

func _load_identity() -> Dictionary:
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(IDENTITY_PATH))
    if typeof(parsed) != TYPE_DICTIONARY:
        _fail("architectural concrete identity JSON invalid")
        return {}
    return parsed as Dictionary

func _mount_runtime(identity: Dictionary, targets: Array[MeshInstance3D]) -> Node:
    var runtime := RUNTIME.new()
    runtime.name = "ConcreteOwnershipRuntimeUnderTest"
    root.add_child(runtime)
    runtime.set("_identity", identity)
    # The runtime owns and clears its registry at teardown. Keep the fixture's
    # observation array independent so post-teardown assertions inspect the
    # real target objects instead of a container intentionally emptied by the
    # owner cleanup.
    var runtime_targets: Array[MeshInstance3D] = []
    runtime_targets.append_array(targets)
    runtime.set("_targets", runtime_targets)
    runtime.call("_apply_material")
    return runtime

func _remove_runtime(runtime: Node) -> void:
    if runtime.get_parent() != null:
        runtime.get_parent().remove_child(runtime)

func _assert_geometry_unchanged(targets: Array[MeshInstance3D], transforms: Array[Transform3D], sizes: Array[Vector3]) -> void:
    for index in range(targets.size()):
        var target := targets[index]
        if target.transform != transforms[index]:
            _fail("concrete target transform changed at index %d" % index)
        var mesh := target.mesh as BoxMesh
        if mesh == null or mesh.size != sizes[index]:
            _fail("concrete target mesh size changed at index %d" % index)

func _scenario_restore_legacy(identity: Dictionary) -> void:
    print("CONCRETE_TEARDOWN_TRACE scenario=restore phase=build")
    var targets: Array[MeshInstance3D] = []
    var baselines: Array[Material] = []
    var transforms: Array[Transform3D] = []
    var sizes: Array[Vector3] = []

    for index in range(EXPECTED_SURFACES):
        var baseline := _make_material("legacy_concrete_%02d" % index, 0.74)
        var target := _make_target(index, baseline)
        targets.append(target)
        baselines.append(baseline)
        transforms.append(target.transform)
        sizes.append((target.mesh as BoxMesh).size)

    var runtime := _mount_runtime(identity, targets)
    if not bool(runtime.call("ready_complete")):
        _fail("concrete runtime did not complete material binding")
    if int(runtime.call("applied_surface_count")) != EXPECTED_SURFACES:
        _fail("concrete runtime did not own exactly 74 surfaces")

    var enhanced := runtime.call("enhanced_material") as Material
    if enhanced == null:
        _fail("enhanced architectural concrete material missing")
    for target in targets:
        if target.material_override != enhanced:
            _fail("concrete runtime did not install the exact owned material")
            break

    print("CONCRETE_TEARDOWN_TRACE scenario=restore phase=remove")
    _remove_runtime(runtime)
    for index in range(EXPECTED_SURFACES):
        if targets[index].material_override != baselines[index]:
            _fail("legacy concrete material was not restored at index %d" % index)
            break
    if int(runtime.call("applied_surface_count")) != 0:
        _fail("concrete runtime retained target registry after teardown")
    _assert_geometry_unchanged(targets, transforms, sizes)

    for target in targets:
        target.free()
    runtime.free()

func _scenario_preserve_later_owner(identity: Dictionary) -> void:
    print("CONCRETE_TEARDOWN_TRACE scenario=later_owner phase=build")
    var targets: Array[MeshInstance3D] = []
    var transforms: Array[Transform3D] = []
    var sizes: Array[Vector3] = []

    for index in range(EXPECTED_SURFACES):
        var baseline := _make_material("legacy_concrete_owner_%02d" % index, 0.76)
        var target := _make_target(index, baseline)
        targets.append(target)
        transforms.append(target.transform)
        sizes.append((target.mesh as BoxMesh).size)

    var runtime := _mount_runtime(identity, targets)
    var later_owner := _make_material("later_concrete_owner", 0.51)
    targets[0].material_override = later_owner

    runtime.call("set_enhanced_material_enabled", false)
    if targets[0].material_override != later_owner:
        _fail("disabling concrete presentation overwrote a later material owner")

    print("CONCRETE_TEARDOWN_TRACE scenario=later_owner phase=remove")
    _remove_runtime(runtime)
    if targets[0].material_override != later_owner:
        _fail("concrete teardown overwrote a later material owner")
    if int(runtime.call("applied_surface_count")) != 0:
        _fail("concrete runtime retained target registry after later-owner teardown")
    _assert_geometry_unchanged(targets, transforms, sizes)

    for target in targets:
        target.free()
    runtime.free()

func _run() -> void:
    var identity := _load_identity()
    if identity.is_empty():
        quit(1)
        return

    _scenario_restore_legacy(identity)
    _scenario_preserve_later_owner(identity)

    if not _failures.is_empty():
        print("MIDI_ARCHITECTURAL_CONCRETE_MATERIAL_TEARDOWN_RED failures=%d" % _failures.size())
        quit(1)
        return

    print("MIDI_ARCHITECTURAL_CONCRETE_MATERIAL_TEARDOWN_OK: surfaces=74 owner_aware_restore=true later_owner_preserved=true geometry_changed=false real_tree_remove=true")
    quit(0)
