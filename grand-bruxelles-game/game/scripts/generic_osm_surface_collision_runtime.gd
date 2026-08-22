extends Node

const ROAD_HEIGHT_M := 0.10
const SIDEWALK_HEIGHT_M := 0.12
const HEIGHT_EPSILON_M := 0.001
const MAX_BIND_FRAMES := 240
const BODY_NAME := "GenericOsmSurfaceCollisionBody"

var _ready_complete := false
var _road_collisions := 0
var _sidewalk_collisions := 0

func _ready() -> void:
    call_deferred("_bind_when_ready")

func _bind_when_ready() -> void:
    for _attempt: int in range(MAX_BIND_FRAMES):
        await get_tree().physics_frame
        var roads_root := get_tree().root.find_child("GeneratedRoads", true, false) as Node3D
        if roads_root == null:
            continue
        if roads_root.get_node_or_null(BODY_NAME) != null:
            return

        var collision_body := StaticBody3D.new()
        collision_body.name = BODY_NAME
        roads_root.add_child(collision_body)

        var road_count := 0
        var sidewalk_count := 0
        for child: Node in roads_root.get_children():
            if not child is CSGBox3D:
                continue
            var box := child as CSGBox3D
            var is_road := box.name.begins_with("Road_") and absf(box.size.y - ROAD_HEIGHT_M) <= HEIGHT_EPSILON_M
            var is_sidewalk := absf(box.size.y - SIDEWALK_HEIGHT_M) <= HEIGHT_EPSILON_M
            if not is_road and not is_sidewalk:
                continue

            var shape := BoxShape3D.new()
            shape.size = box.size
            var collision_shape := CollisionShape3D.new()
            collision_shape.name = "Support_%s" % box.name
            collision_shape.shape = shape
            collision_shape.transform = box.transform
            collision_body.add_child(collision_shape)

            if is_road:
                road_count += 1
            else:
                sidewalk_count += 1

        if road_count == 0:
            collision_body.queue_free()
            continue

        _road_collisions = road_count
        _sidewalk_collisions = sidewalk_count
        _ready_complete = true
        print("GENERIC_OSM_SURFACE_COLLISIONS_READY: roads=%d sidewalks=%d body_count=1 source_geometry_changed=false source_height_inferred=false" % [_road_collisions, _sidewalk_collisions])
        return
    push_error("GENERIC_OSM_SURFACE_COLLISIONS_FAIL: GeneratedRoads unavailable")

func readiness() -> Dictionary:
    return {
        "ready": _ready_complete,
        "road_collisions": _road_collisions,
        "sidewalk_collisions": _sidewalk_collisions,
        "body_count": 1 if _ready_complete else 0,
        "source_geometry_changed": false,
        "source_height_inferred": false,
    }
