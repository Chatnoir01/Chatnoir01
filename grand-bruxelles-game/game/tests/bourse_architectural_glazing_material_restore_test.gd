extends SceneTree

const RUNTIME_SCRIPT := preload("res://game/scripts/bourse_architectural_glazing_surface_runtime.gd")

func _initialize() -> void:
    var shared_mesh := BoxMesh.new()
    var inherited_material := StandardMaterial3D.new()
    inherited_material.resource_name = "Inherited authored mesh material"
    shared_mesh.material = inherited_material

    var inherited := MeshInstance3D.new()
    inherited.mesh = shared_mesh
    var sibling := MeshInstance3D.new()
    sibling.mesh = shared_mesh

    var overridden := MeshInstance3D.new()
    overridden.mesh = BoxMesh.new()
    var override_material := StandardMaterial3D.new()
    override_material.resource_name = "Authored override material"
    overridden.material_override = override_material

    var enhanced := ShaderMaterial.new()
    var runtime: Node = RUNTIME_SCRIPT.new()
    runtime.set("_targets", [inherited, overridden])
    runtime.set("_original_materials", {
        inherited.get_instance_id(): runtime.call("_get_authored_material", inherited),
        overridden.get_instance_id(): runtime.call("_get_authored_material", overridden)
    })
    runtime.set("_material", enhanced)

    runtime.call("set_enhanced_material_enabled", true)
    if inherited.material_override != enhanced or overridden.material_override != enhanced:
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
    inherited.free()
    sibling.free()
    overridden.free()
    quit(0)

func _fail(message: String) -> void:
    push_error("BOURSE_GLAZING_MATERIAL_RESTORE_FAIL: %s" % message)
    quit(1)
