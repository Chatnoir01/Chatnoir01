extends Node

## Low-cost collision completion layer for characters that were originally
## authored as visual/behavior-only nodes. It does not replace crowd spacing;
## it gives the player/world a final physical barrier when avoidance fails.

const WORLD_STREAMING_RUNTIME_SCRIPT := preload("res://game/scripts/brussels_world_streaming_runtime.gd")
const CHARACTER_RADIUS := 0.32
const CHARACTER_HEIGHT := 1.72

var character_shapes_added: int = 0
var ambient_shapes_added: int = 0
var traffic_shapes_added: int = 0


func _ready() -> void:
    get_tree().node_added.connect(_on_node_added)
    call_deferred("_initial_scan")
    call_deferred("_ensure_world_streaming_runtime")


func _ensure_world_streaming_runtime() -> void:
    var world := get_parent()
    if world == null or world.get_node_or_null("Player") == null:
        return
    if world.get_node_or_null("WorldStreamingRuntime") != null:
        return
    var runtime := WORLD_STREAMING_RUNTIME_SCRIPT.new()
    runtime.name = "WorldStreamingRuntime"
    world.add_child(runtime)


func _initial_scan() -> void:
    var scene := get_tree().current_scene
    if scene != null:
        _scan_branch(scene)
    print("PLAYABILITY_COLLISIONS_READY: npc=%d ambient=%d traffic=%d" % [character_shapes_added, ambient_shapes_added, traffic_shapes_added])


func _scan_branch(node: Node) -> void:
    _consider_node(node)
    for child: Node in node.get_children():
        _scan_branch(child)


func _on_node_added(node: Node) -> void:
    call_deferred("_consider_node", node)


func _consider_node(node: Node) -> void:
    if not is_instance_valid(node):
        return
    if node is NpcAgent:
        if _ensure_character_collision(node as CharacterBody3D):
            character_shapes_added += 1
        return
    if node.is_in_group("ambient_pedestrian") and node is Node3D:
        if _ensure_ambient_pedestrian_collision(node as Node3D):
            ambient_shapes_added += 1
        return
    if node.is_in_group("ambient_traffic") and node is Node3D:
        if _ensure_ambient_vehicle_collision(node as Node3D):
            traffic_shapes_added += 1


func _has_live_collision_shape(root: Node) -> bool:
    for child: Node in root.get_children():
        if child is CollisionShape3D and (child as CollisionShape3D).shape != null:
            return true
    return false


func _ensure_character_collision(body: CharacterBody3D) -> bool:
    if _has_live_collision_shape(body):
        return false
    var collision := CollisionShape3D.new()
    collision.name = "RuntimeCharacterCollision"
    var capsule := CapsuleShape3D.new()
    capsule.radius = CHARACTER_RADIUS
    capsule.height = CHARACTER_HEIGHT
    collision.shape = capsule
    collision.position.y = CHARACTER_HEIGHT * 0.5
    body.add_child(collision)
    body.collision_layer |= 1
    body.collision_mask |= 1
    body.set_meta("runtime_collision_completed", true)
    return true


func _ensure_ambient_pedestrian_collision(person: Node3D) -> bool:
    if person.get_node_or_null("RuntimeCollisionBody") != null:
        return false
    var body := AnimatableBody3D.new()
    body.name = "RuntimeCollisionBody"
    body.collision_layer = 1
    body.collision_mask = 1
    body.sync_to_physics = true
    person.add_child(body)

    var collision := CollisionShape3D.new()
    collision.name = "CollisionShape3D"
    var capsule := CapsuleShape3D.new()
    capsule.radius = CHARACTER_RADIUS
    capsule.height = CHARACTER_HEIGHT
    collision.shape = capsule
    collision.position.y = CHARACTER_HEIGHT * 0.5
    body.add_child(collision)
    person.set_meta("runtime_collision_completed", true)
    return true


func _ensure_ambient_vehicle_collision(vehicle: Node3D) -> bool:
    if vehicle.get_node_or_null("RuntimeCollisionBody") != null:
        return false
    var body := AnimatableBody3D.new()
    body.name = "RuntimeCollisionBody"
    body.collision_layer = 1
    body.collision_mask = 1
    body.sync_to_physics = true
    vehicle.add_child(body)

    var collision := CollisionShape3D.new()
    collision.name = "CollisionShape3D"
    var box := BoxShape3D.new()
    box.size = Vector3(1.82, 1.0, 4.05)
    collision.shape = box
    collision.position.y = 0.45
    body.add_child(collision)
    vehicle.set_meta("runtime_collision_completed", true)
    return true


func collision_stats() -> Dictionary:
    return {
        "npc": character_shapes_added,
        "ambient_pedestrian": ambient_shapes_added,
        "ambient_traffic": traffic_shapes_added,
    }
