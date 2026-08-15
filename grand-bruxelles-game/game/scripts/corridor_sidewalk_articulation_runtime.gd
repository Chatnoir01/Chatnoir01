extends Node

const ARTICULATION_SCRIPT := preload("res://game/scripts/corridor_sidewalk_articulation.gd")
const MAX_MOUNT_FRAMES := 120

var _mounted := false

func _ready() -> void:
    call_deferred("_mount_when_ready")

func _find_scene_with_city() -> Node:
    var current := get_tree().current_scene
    if current != null and current.get_node_or_null("BrusselsOSM") != null:
        return current
    for child: Node in get_tree().root.get_children():
        if child == self:
            continue
        if child.get_node_or_null("BrusselsOSM") != null:
            return child
    return null

func _mount_when_ready() -> void:
    for _attempt: int in range(MAX_MOUNT_FRAMES):
        if _mounted:
            return
        var scene := _find_scene_with_city()
        if scene != null:
            mount_into_scene(scene)
            return
        await get_tree().process_frame
    push_warning("Corridor sidewalk articulation did not find a production BrusselsOSM scene within %d frames" % MAX_MOUNT_FRAMES)

func mount_into_scene(scene: Node) -> bool:
    if scene == null:
        return false
    var city_builder := scene.get_node_or_null("BrusselsOSM")
    if city_builder == null:
        return false
    if city_builder.get_node_or_null("CorridorSidewalkArticulation") != null:
        _mounted = true
        return true
    var articulation := ARTICULATION_SCRIPT.new()
    articulation.name = "CorridorSidewalkArticulation"
    city_builder.add_child(articulation)
    if articulation.build_from_city_builder(city_builder):
        _mounted = true
        return true
    articulation.queue_free()
    return false
