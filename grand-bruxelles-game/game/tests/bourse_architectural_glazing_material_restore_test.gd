extends SceneTree

const RUNTIME_SCRIPT := preload("res://game/scripts/bourse_architectural_glazing_surface_runtime.gd")
const TARGET_NAMES := ["RearCentralEntry", "RearSideEntry_00", "RearSideEntry_01", "RearOvalLight_00", "RearOvalLight_01"]

func _initialize() -> void:
    var portico := Node3D.new()
    portico.name = "BoursePorticoArticulation"

    var shared_mesh := BoxMesh.new()
    var inherited_material := StandardMaterial3D.new()
    inherited_material.resource_name = "Inherited authored mesh material"
    shared_mesh.material = inherited_material

    var inherited := MeshInstance3D.new()
    inherited.name = TARGET_NAMES[0]
    inherited.mesh = shared_mesh
    portico.add_child(inherited)

    var sibling := MeshInstance3D.new()
    sibling.name = "UntargetedSibling"
    sibling.mesh = shared_mesh
    portico.add_child(sibling)

    var overridden := MeshInstance3D.new()
    overridden.name = TARGET_NAMES[1]
    overridden.mesh = BoxMesh.new()
    var override_material := StandardMaterial3D.new()
    override_material.resource_name = "Authored override material"
    overridden.material_override = override_material
    portico.add_child(overridden)

    for index: int in range(2, TARGET_NAMES.size()):
        var filler := MeshInstance3D.new()
        filler.name = TARGET_NAMES[index]
        filler.mesh = BoxMesh.new()
        portico.add_child(filler)

    var runtime: Node = RUNTIME_SCRIPT.new()
    runtime.call("bind_portico", portico)
    if runtime.call("diagnostic_identity_failure"):
        _fail("known-good production bind unexpectedly failed")
        return
    if int(runtime.call("diagnostic_target_count")) != 5:
        _fail("production bind did not collect the five approved surfaces")
        return

    var enhanced: Material = inherited.material_override
    if enhanced == null or overridden.material_override != enhanced:
        _fail("enhanced material was not applied through override")
        return

    runtime.call("set_enhanced_material_enabled", false)

    if inherited.material_override != null:
        _fail("inherited mesh material was restored as an explicit override")
        return
    if inherited.mesh.material != inherited_material:
        _fail("inherited mesh material changed during toggle")
        return
    if sibling.material_override != null or sibling.mesh.material != inherited_material:
        _fail("sibling sharing the authored mesh was contaminated")
        return
    if overridden.material_override != override_material:
        _fail("pre-existing authored override was not restored exactly")
        return

    print("BOURSE_GLAZING_MATERIAL_RESTORE_OK")
    runtime.free()
    portico.free()
    quit(0)

func _fail(message: String) -> void:
    push_error("BOURSE_GLAZING_MATERIAL_RESTORE_FAIL: %s" % message)
    quit(1)
