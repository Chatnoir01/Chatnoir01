extends Node

@export var radius_m: float = 610.0

const MIDI_WORLD := Vector3(-668.5, 0.0, 627.84)


func _ready() -> void:
    call_deferred("_apply_mask")


func _inside(position: Vector3) -> bool:
    return Vector2(position.x - MIDI_WORLD.x, position.z - MIDI_WORLD.z).length() <= radius_m


func _mask_children(root: Node) -> int:
    var hidden: int = 0
    for child: Node in root.get_children():
        if child is Node3D:
            var node_3d: Node3D = child as Node3D
            if _inside(node_3d.global_position):
                if node_3d is GeometryInstance3D:
                    var geometry: GeometryInstance3D = node_3d as GeometryInstance3D
                    geometry.visible = false
                    hidden += 1
    return hidden


func _has_materialized_geometry(root: Node) -> bool:
    if root == null:
        return false
    var stack: Array[Node] = [root]
    while not stack.is_empty():
        var node: Node = stack.pop_back()
        if node is MeshInstance3D:
            var mesh_instance := node as MeshInstance3D
            if mesh_instance.mesh != null and mesh_instance.mesh.get_surface_count() > 0 and mesh_instance.is_visible_in_tree():
                return true
        for child: Node in node.get_children():
            stack.append(child)
    return false


func _apply_mask() -> void:
    var osm: Node = get_node_or_null("../BrusselsOSM")
    if osm == null:
        return

    var urbis: Node = get_node_or_null("../UrbISMidiExact")
    var streets_ready := false
    var buildings_ready := false
    if urbis != null:
        streets_ready = _has_materialized_geometry(urbis.get_node_or_null("UrbISStreetSurfaces"))
        buildings_ready = _has_materialized_geometry(urbis.get_node_or_null("UrbISExactBuildings"))

    var hidden: int = 0
    var roads: Node = osm.get_node_or_null("GeneratedRoads")
    if roads != null and streets_ready:
        hidden += _mask_children(roads)

    var buildings: Node = osm.get_node_or_null("GeneratedBuildings")
    if buildings != null and buildings_ready:
        hidden += _mask_children(buildings)

    # These procedural facade instances only belonged to the old Midi OSM
    # massing. Keep them as fallback unless authoritative building geometry
    # has actually materialized and is visible in the player scene.
    if buildings_ready:
        var details: Node = osm.get_node_or_null("GeneratedFacadeDetails")
        if details is CanvasItem:
            var canvas_item: CanvasItem = details as CanvasItem
            canvas_item.visible = false
        elif details is Node3D:
            var details_3d: Node3D = details as Node3D
            details_3d.visible = false

    print(
        "Grand Bruxelles UrbIS mask: %d approximate OSM geometry nodes hidden near Midi (streets_ready=%s buildings_ready=%s)" %
        [hidden, str(streets_ready), str(buildings_ready)]
    )
