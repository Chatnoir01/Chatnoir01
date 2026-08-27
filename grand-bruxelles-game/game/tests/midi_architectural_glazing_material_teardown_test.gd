extends SceneTree

const RUNTIME := preload("res://game/scripts/midi_architectural_glazing_surface_runtime.gd")
const IDENTITY_PATH := "res://data/visual/midi_architectural_glazing_material_identity.json"
const EXPECTED_SURFACES := 340

var _failures: Array[String] = []

func _init() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    _failures.append(message)
    push_error(message)

func _make_material(label: String, roughness: float) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.resource_name = label
    material.albedo_color = Color(0.15, 0.18, 0.21, 0.55)
    material.roughness = roughness
    return material

func _make_target(index: int, baseline: Material) -> MeshInstance3D:
    var target := MeshInstance3D.new()
    target.name = "StationLongGlassBand" if index == 0 else "Window_%03d" % index
    var mesh := BoxMesh.new()
    mesh.size = Vector3(0.8 + float(index % 7) * 0.01, 1.2, 0.08)
    target.mesh = mesh
    target.material_override = baseline
    target.transform = Transform3D(Basis.IDENTITY, Vector3(float(index % 40) * 0.9, float(index / 40) * 1.3, -2.0))
    return target

func _load_identity() -> Dictionary:
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(IDENTITY_PATH))
    if typeof(parsed) != TYPE_DICTIONARY:
        _fail("glazing identity JSON invalid")
        return {}
    return parsed as Dictionary

func _mount_runtime(identity: Dictionary, targets: Array[MeshInstance3D]) -> Node:
    var runtime := RUNTIME.new()
    runtime.name = "GlazingOwnershipRuntimeUnderTest"
    root.add_child(runtime)
    runtime.set("_identity", identity)
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
        if targets[index].transform != transforms[index]:
            _fail("glazing target transform changed at index %d" % index)
            return
        var mesh := targets[index].mesh as BoxMesh
        if mesh == null or mesh.size != sizes[index]:
            _fail("glazing target mesh size changed at index %d" % index)
            return

func _build_targets(prefix: String) -> Dictionary:
    var targets: Array[MeshInstance3D] = []
    var baselines: Array[Material] = []
    var transforms: Array[Transform3D] = []
    var sizes: Array[Vector3] = []
    for index in range(EXPECTED_SURFACES):
        var baseline := _make_material("%s_%03d" % [prefix, index], 0.35 + float(index % 5) * 0.02)
        var target := _make_target(index, baseline)
        targets.append(target)
        baselines.append(baseline)
        transforms.append(target.transform)
        sizes.append((target.mesh as BoxMesh).size)
    return {"targets": targets, "baselines": baselines, "transforms": transforms, "sizes": sizes}

func _free_fixture(targets: Array[MeshInstance3D], runtime: Node) -> void:
    for target in targets:
        target.free()
    runtime.free()

func _scenario_restore_legacy(identity: Dictionary) -> void:
    var fixture := _build_targets("legacy_glazing")
    var targets: Array[MeshInstance3D] = fixture.targets
    var baselines: Array[Material] = fixture.baselines
    var transforms: Array[Transform3D] = fixture.transforms
    var sizes: Array[Vector3] = fixture.sizes
    var runtime := _mount_runtime(identity, targets)
    var enhanced := runtime.call("enhanced_material") as Material
    if enhanced == null:
        _fail("enhanced glazing material missing")
    for target in targets:
        if target.material_override != enhanced:
            _fail("glazing runtime did not install exact owned material")
            break

    _remove_runtime(runtime)
    for index in range(EXPECTED_SURFACES):
        if targets[index].material_override != baselines[index]:
            _fail("legacy glazing material not restored at index %d" % index)
            break
    if int(runtime.call("applied_surface_count")) != 0:
        _fail("glazing runtime retained target registry after teardown")
    _assert_geometry_unchanged(targets, transforms, sizes)
    _free_fixture(targets, runtime)

func _scenario_preserve_later_owner(identity: Dictionary) -> void:
    var fixture := _build_targets("legacy_glazing_owner")
    var targets: Array[MeshInstance3D] = fixture.targets
    var transforms: Array[Transform3D] = fixture.transforms
    var sizes: Array[Vector3] = fixture.sizes
    var runtime := _mount_runtime(identity, targets)
    var later_owner := _make_material("later_glazing_owner", 0.62)
    targets[0].material_override = later_owner

    runtime.call("set_enhanced_material_enabled", false)
    if targets[0].material_override != later_owner:
        _fail("disabling glazing presentation overwrote later material owner")

    _remove_runtime(runtime)
    if targets[0].material_override != later_owner:
        _fail("glazing teardown overwrote later material owner")
    if int(runtime.call("applied_surface_count")) != 0:
        _fail("glazing runtime retained registry after later-owner teardown")
    _assert_geometry_unchanged(targets, transforms, sizes)
    _free_fixture(targets, runtime)

func _run() -> void:
    var identity := _load_identity()
    if identity.is_empty():
        quit(1)
        return
    _scenario_restore_legacy(identity)
    _scenario_preserve_later_owner(identity)
    if not _failures.is_empty():
        print("MIDI_ARCHITECTURAL_GLAZING_MATERIAL_TEARDOWN_RED failures=%d" % _failures.size())
        quit(1)
        return
    print("MIDI_ARCHITECTURAL_GLAZING_MATERIAL_TEARDOWN_OK: surfaces=340 owner_aware_restore=true later_owner_preserved=true geometry_changed=false")
    quit(0)
