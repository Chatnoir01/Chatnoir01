extends Node

@export var hero_builder_path: NodePath = NodePath("../UrbISHeroGeometry")

var _applied := false

func _ready() -> void:
    call_deferred("_apply_roof_cull")

func _apply_roof_cull() -> void:
    var builder := get_node_or_null(hero_builder_path)
    if builder == null:
        push_error("Bourse roof cull: hero builder missing")
        return
    var hero := builder.get_node_or_null("Hero_Bourse")
    if hero == null:
        push_error("Bourse roof cull: Hero_Bourse missing")
        return
    var roofs := hero.get_node_or_null("Roofs") as MeshInstance3D
    if roofs == null or roofs.mesh == null or roofs.mesh.get_surface_count() == 0:
        push_error("Bourse roof cull: roof mesh missing")
        return

    var source_material := roofs.mesh.surface_get_material(0) as StandardMaterial3D
    if source_material == null:
        push_error("Bourse roof cull: source roof material missing")
        return

    var material := source_material.duplicate() as StandardMaterial3D
    if material == null:
        push_error("Bourse roof cull: roof material duplication failed")
        return
    material.cull_mode = BaseMaterial3D.CULL_BACK
    roofs.material_override = material
    roofs.set_meta("bourse_roof_backface_cull", true)
    roofs.set_meta("bourse_roof_source_triangle_count", roofs.mesh.surface_get_array_len(0) / 3)
    set_meta("runtime_approved", false)
    set_meta("realism_complete", false)
    _applied = true
    print("Bourse roof backface cull: enabled runtime_approved=false")

func diagnostic_applied() -> bool:
    return _applied
