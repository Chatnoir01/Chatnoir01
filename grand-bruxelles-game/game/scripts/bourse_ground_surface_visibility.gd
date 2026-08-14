extends Node

var _applied_scene_id: int = 0
var _ground_triangle_count: int = 0


func _process(_delta: float) -> void:
    var scene := get_tree().current_scene
    if scene == null:
        return
    var scene_id := int(scene.get_instance_id())
    if scene_id == _applied_scene_id:
        return
    if apply_to_scene(scene):
        _applied_scene_id = scene_id
        set_process(false)


func apply_to_scene(scene: Node) -> bool:
    if scene == null:
        return false
    var hero := scene.get_node_or_null("UrbISHeroGeometry/Hero_Bourse")
    if hero == null:
        return false
    var ground := hero.get_node_or_null("Ground") as MeshInstance3D
    var walls := hero.get_node_or_null("Walls") as MeshInstance3D
    var roofs := hero.get_node_or_null("Roofs") as MeshInstance3D
    if ground == null or ground.mesh == null or ground.mesh.get_surface_count() == 0:
        push_error("Bourse ground visibility: official GROUNDSURFACE mesh missing")
        return false
    if walls == null or walls.mesh == null or roofs == null or roofs.mesh == null:
        push_error("Bourse ground visibility: official WALL/ROOF surfaces missing")
        return false

    var arrays: Array = ground.mesh.surface_get_arrays(0)
    var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
    if vertices.is_empty() or vertices.size() % 3 != 0:
        push_error("Bourse ground visibility: invalid official GROUNDSURFACE triangle buffer")
        return false

    # CityGML/UrbIS GROUNDSURFACE is the exterior base boundary of the LoD2 solid,
    # not evidence for an exposed interior floor. Keep every source vertex and
    # triangle in memory, but do not present that bottom cap as visible architecture.
    _ground_triangle_count = vertices.size() / 3
    ground.visible = false
    ground.set_meta("bourse_groundsurface_source_preserved", true)
    ground.set_meta("bourse_groundsurface_hidden_as_exterior_base", true)
    ground.set_meta("bourse_groundsurface_triangle_count_preserved", _ground_triangle_count)
    set_meta("runtime_approved", false)
    set_meta("realism_complete", false)
    print("Bourse ground visibility: hidden exterior-base GROUNDSURFACE; preserved_triangles=%d" % _ground_triangle_count)
    return true


func diagnostic_ground_triangle_count() -> int:
    return _ground_triangle_count
