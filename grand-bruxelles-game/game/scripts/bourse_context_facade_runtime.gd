extends Node

const ARTICULATION_SCRIPT := preload("res://game/scripts/bourse_context_facade_articulation.gd")

var _pending_ids: Dictionary = {}

func _ready() -> void:
    get_tree().node_added.connect(_on_node_added)
    call_deferred("_scan_existing")

func _on_node_added(node: Node) -> void:
    if node.name == &"BrusselsOSM":
        _schedule_attach(node)

func _scan_existing() -> void:
    var root_node := get_tree().root
    if root_node == null:
        return
    for node: Node in root_node.find_children("BrusselsOSM", "Node3D", true, false):
        _schedule_attach(node)

func _schedule_attach(city_builder: Node) -> void:
    if city_builder == null or not is_instance_valid(city_builder):
        return
    var instance_id := city_builder.get_instance_id()
    if _pending_ids.has(instance_id):
        return
    _pending_ids[instance_id] = true
    call_deferred("_attach", city_builder, 0)

func _attach(city_builder: Node, attempt: int) -> void:
    if city_builder == null or not is_instance_valid(city_builder):
        return
    if city_builder.get_node_or_null("ContextFacadeArticulation") != null:
        _pending_ids.erase(city_builder.get_instance_id())
        return
    if city_builder.get_node_or_null("GeneratedBuildings") == null:
        if attempt < 8:
            call_deferred("_attach", city_builder, attempt + 1)
        else:
            _pending_ids.erase(city_builder.get_instance_id())
            push_warning("Bourse facade articulation could not find generated building geometry")
        return

    var articulation := ARTICULATION_SCRIPT.new() as Node3D
    articulation.name = "ContextFacadeArticulation"
    city_builder.add_child(articulation)
    if not bool(articulation.call("build_from_city_builder", city_builder)):
        articulation.queue_free()
    _pending_ids.erase(city_builder.get_instance_id())
