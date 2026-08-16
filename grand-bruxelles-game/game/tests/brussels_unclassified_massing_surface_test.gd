extends SceneTree

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BRUSSELS_UNCLASSIFIED_MASSING_FAIL: %s" % message)
    quit(1)

func _expect(condition: bool, message: String) -> bool:
    if not condition:
        _fail(message)
        return false
    return true

func _run() -> void:
    var runtime: Node = root.get_node_or_null("BrusselsUnclassifiedMassingSurfaceRuntime")
    if not _expect(runtime != null, "autoload missing"):
        return
    var target := MeshInstance3D.new()
    target.name = "VisualCandidateBuildingMassing"
    target.set_meta("visual_only", true)
    target.set_meta("runtime_approved", false)
    var mesh := BoxMesh.new()
    mesh.size = Vector3(20.0, 18.0, 12.0)
    target.mesh = mesh
    root.add_child(target)
    for _frame: int in range(3): await process_frame
    if not _expect(target.material_override is ShaderMaterial, "candidate presentation material was not applied"): return
    if not _expect(bool(target.get_meta("unclassified_massing_presentation", false)), "presentation metadata missing"): return
    if not _expect(not bool(target.get_meta("material_identity_claimed", true)), "runtime claimed a real material identity"): return
    runtime.call("set_presentation_enabled", false)
    await process_frame
    if not _expect(target.material_override is StandardMaterial3D, "baseline material toggle failed"): return
    var baseline := target.material_override as StandardMaterial3D
    if not _expect(baseline.albedo_color.is_equal_approx(Color(0.60, 0.53, 0.45, 1.0)), "baseline color drifted"): return
    if not _expect(is_equal_approx(baseline.roughness, 0.90), "baseline roughness drifted"): return
    runtime.call("set_presentation_enabled", true)
    await process_frame
    if not _expect(target.material_override is ShaderMaterial, "candidate material restore failed"): return
    var unsafe := MeshInstance3D.new()
    unsafe.name = "VisualCandidateBuildingMassing"
    unsafe.mesh = mesh
    unsafe.set_meta("visual_only", true)
    unsafe.set_meta("runtime_approved", true)
    root.add_child(unsafe)
    for _frame: int in range(2): await process_frame
    if not _expect(unsafe.material_override == null, "runtime-approved geometry was unexpectedly restyled"): return
    print("BRUSSELS_UNCLASSIFIED_MASSING_OK: presentation-only shader applied to source-plan visual massing, baseline toggles exactly, and runtime-approved geometry stays untouched")
    target.queue_free()
    unsafe.queue_free()
    quit(0)
