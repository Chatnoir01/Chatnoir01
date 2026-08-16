extends Node

const ARTICULATION_SCRIPT := preload("res://game/scripts/bourse_context_facade_articulation.gd")
var _pending_ids: Dictionary = {}

func _ready() -> void:
    get_tree().node_added.connect(_on_node_added); call_deferred("_scan_existing")

func _on_node_added(node: Node) -> void:
    if node.name == &"BrusselsOSM": _schedule(node)

func _scan_existing() -> void:
    for node: Node in get_tree().root.find_children("BrusselsOSM", "Node3D", true, false): _schedule(node)

func _schedule(city: Node) -> void:
    if city == null or not is_instance_valid(city): return
    var id := city.get_instance_id()
    if _pending_ids.has(id): return
    _pending_ids[id] = true; call_deferred("_attach", city, 0)

func _attach(city: Node, attempt: int) -> void:
    if city == null or not is_instance_valid(city): return
    var scene_root := city.get_parent()
    if scene_root == null: return
    if scene_root.get_node_or_null("BourseContextFacadeArticulation") != null:
        _pending_ids.erase(city.get_instance_id()); return
    if city.get_node_or_null("GeneratedBuildings") == null:
        if attempt < 12: call_deferred("_attach", city, attempt + 1)
        else: _pending_ids.erase(city.get_instance_id()); push_warning("Bourse context facade runtime: GeneratedBuildings not ready")
        return
    var articulation := ARTICULATION_SCRIPT.new() as Node3D
    articulation.name = "BourseContextFacadeArticulation"; scene_root.add_child(articulation)
    _pending_ids.erase(city.get_instance_id())
