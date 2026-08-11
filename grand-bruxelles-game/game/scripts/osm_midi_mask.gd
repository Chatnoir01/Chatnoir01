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


func _apply_mask() -> void:
    var osm: Node = get_node_or_null("../BrusselsOSM")
    if osm == null:
        return

    var hidden: int = 0
    var roads: Node = osm.get_node_or_null("GeneratedRoads")
    if roads != null:
        hidden += _mask_children(roads)

    var buildings: Node = osm.get_node_or_null("GeneratedBuildings")
    if buildings != null:
        hidden += _mask_children(buildings)

    # These procedural facade instances only existed for the old Midi OSM massing.
    var details: Node = osm.get_node_or_null("GeneratedFacadeDetails")
    if details is CanvasItem:
        var canvas_item: CanvasItem = details as CanvasItem
        canvas_item.visible = false
    elif details is Node3D:
        var details_3d: Node3D = details as Node3D
        details_3d.visible = false

    print("Grand Bruxelles UrbIS mask: %d approximate OSM geometry nodes hidden near Midi" % hidden)
