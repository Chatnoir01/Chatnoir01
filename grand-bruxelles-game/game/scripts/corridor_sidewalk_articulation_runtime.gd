extends Node

const ARTICULATION_SCRIPT := preload("res://game/scripts/corridor_sidewalk_articulation.gd")

var _mounted := false

func _ready() -> void:
    call_deferred("_mount")

func _mount() -> void:
    if _mounted:
        return
    var scene := get_tree().current_scene
    if scene == null:
        call_deferred("_mount")
        return
    var city_builder := scene.get_node_or_null("BrusselsOSM")
    if city_builder == null:
        return
    if city_builder.get_node_or_null("CorridorSidewalkArticulation") != null:
        _mounted = true
        return
    var articulation := ARTICULATION_SCRIPT.new()
    articulation.name = "CorridorSidewalkArticulation"
    city_builder.add_child(articulation)
    if articulation.build_from_city_builder(city_builder):
        _mounted = true
    else:
        articulation.queue_free()
