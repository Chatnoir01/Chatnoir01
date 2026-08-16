extends SceneTree

const RUNTIME_SCRIPT := preload("res://game/scripts/bourse_architectural_glazing_surface_runtime.gd")

func _initialize() -> void:
    var portico := Node3D.new()

    var shared_mesh := BoxMesh.new()
    var inherited_material := StandardMaterial3D.new()
    inherited_material.resource_name = "Inherited authored mesh material"
    shared_mesh.material = inherited_material

    var inherited := MeshInstance3D.new()
    inherited.name = "RearCentralEntry"
    inherited.mesh = shared_mesh
    portico.add_child(inherited)

    var sibling := MeshInstance3D.new()
    sibling.name = "UnrelatedSharedMeshSibling"
    sibling.mesh = shared_mesh
    portico.add_child(sibling)

    var overridden := MeshInstance3D.new()
    overridden.name = "RearSideEntry_00"
    overridden.mesh = BoxMesh.new()
    var override_material := StandardMaterial3D.new()
    override_material.resource_name = "Authored override material"
    overridden.material_override = override_material
    portico.add_child(overridden)

    for target_name: String in ["RearSideEntry_01", "RearOvalLight_00", "RearOvalLight_01"]:
        var filler := MeshInstance3D.new()
        filler.name = target_name
        filler.mesh = BoxMesh.new()
        portico.add_child(filler)

    var runtime: Node = RUNTIME_SCRIPT.new()
    runtime.call("bind_portico", portico)

    var enhanced := inherited.material_override
    if enhanced == null or overridden.material_override != enhanced:
        _fail("production bind did not apply one enhanced override to both targets")
        portico.free()
        runtime.free()
        return

    runtime.call("set_enhanced_material_enabled", false)

    if inherited.material_override != null:
        _fail("inherited mesh material was restored as an explicit override")
        portico.free()
        runtime.free()
        return
    if inherited.mesh.material != inherited_material:
        _fail("inherited mesh material changed during toggle")
        portico.free()
        runtime.free()
        return
    if sibling.material_override != null or sibling.mesh.material != inherited_material:
        _fail("sibling sharing the authored mesh was contaminated")
        portico.free()
        runtime.free()
        return
    if overridden.material_override != override_material:
        _fail("pre-existing authored override was not restored exactly")
        portico.free()
        runtime.free()
        return

    print("BOURSE_GLAZING_MATERIAL_RESTORE_OK")
    portico.free()
    runtime.free()
    quit(0)

func _fail(message: String) -> void:
    push_error("BOURSE_GLAZING_MATERIAL_RESTORE_FAIL: %s" % message)
    quit(1)
