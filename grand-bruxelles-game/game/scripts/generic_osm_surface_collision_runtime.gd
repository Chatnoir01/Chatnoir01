extends Node

const ROAD_HEIGHT_M := 0.10
const SIDEWALK_HEIGHT_M := 0.12
const HEIGHT_EPSILON_M := 0.001
const MAX_BIND_FRAMES := 240

var _ready_complete := false
var _road_collisions := 0
var _sidewalk_collisions := 0

func _ready() -> void:
    call_deferred("_bind_when_ready")

func _bind_when_ready() -> void:
    for _attempt: int in range(MAX_BIND_FRAMES):
        await get_tree().physics_frame
        var roads_root := get_tree().root.find_child("GeneratedRoads", true, false)
        if roads_root == null:
            continue
        var road_count := 0
        var sidewalk_count := 0
        for child: Node in roads_root.get_children():
            if not child is CSGBox3D:
                continue
            var box := child as CSGBox3D
            if box.name.begins_with("Road_") and absf(box.size.y - ROAD_HEIGHT_M) <= HEIGHT_EPSILON_M:
                box.use_collision = true
                road_count += 1
                continue
            if absf(box.size.y - SIDEWALK_HEIGHT_M) <= HEIGHT_EPSILON_M:
                box.use_collision = true
                sidewalk_count += 1
        if road_count == 0:
            continue
        _road_collisions = road_count
        _sidewalk_collisions = sidewalk_count
        _ready_complete = true
        print("GENERIC_OSM_SURFACE_COLLISIONS_READY: roads=%d sidewalks=%d source_geometry_changed=false source_height_inferred=false" % [_road_collisions, _sidewalk_collisions])
        return
    push_error("GENERIC_OSM_SURFACE_COLLISIONS_FAIL: GeneratedRoads unavailable")

func readiness() -> Dictionary:
    return {
        "ready": _ready_complete,
        "road_collisions": _road_collisions,
        "sidewalk_collisions": _sidewalk_collisions,
        "source_geometry_changed": false,
        "source_height_inferred": false,
    }
