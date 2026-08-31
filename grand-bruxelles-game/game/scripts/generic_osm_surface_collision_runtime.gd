extends Node

const ROAD_HEIGHT_M := 0.10
const SIDEWALK_HEIGHT_M := 0.12
const HEIGHT_EPSILON_M := 0.001
const MAX_BIND_FRAMES := 240
const BODY_NAME := "GenericOsmSurfaceCollisionBody"
const SHAPE_NAME := "GenericOsmTopSupport"
const OWNER_META := "grand_bruxelles_owner"
const OWNER_ID := "generic_osm_surface_collision_runtime"
# Dedicated layer 20 keeps the generic player-support mesh out of shared
# traffic/NPC/camera collision queries. The canonical Player opts in at runtime.
const SUPPORT_COLLISION_LAYER := 1 << 19
const SUPPORT_COLLISION_MASK := 0

var _ready_complete := false
var _road_surfaces := 0
var _sidewalk_surfaces := 0
var _triangle_count := 0

func _ready() -> void:
    call_deferred("_bind_when_ready")

func _append_top_face(faces: PackedVector3Array, box: CSGBox3D) -> void:
    var half_x := box.size.x * 0.5
    var half_y := box.size.y * 0.5
    var half_z := box.size.z * 0.5
    var p00 := box.transform * Vector3(-half_x, half_y, -half_z)
    var p10 := box.transform * Vector3(half_x, half_y, -half_z)
    var p11 := box.transform * Vector3(half_x, half_y, half_z)
    var p01 := box.transform * Vector3(-half_x, half_y, half_z)

    # Godot's concave front face for this X/Z plane uses this winding when
    # backface_collision is disabled. Keep only the rendered top plane: no
    # authored curb walls or underside volume are manufactured here.
    faces.append(p00)
    faces.append(p10)
    faces.append(p11)
    faces.append(p00)
    faces.append(p11)
    faces.append(p01)

func _scene_root_for(node: Node) -> Node:
    var current := node
    while current.get_parent() != null and current.get_parent() != get_tree().root:
        current = current.get_parent()
    return current

func _find_owned_body(roads_root: Node) -> StaticBody3D:
    for child: Node in roads_root.get_children():
        if child is StaticBody3D and str(child.get_meta(OWNER_META, "")) == OWNER_ID:
            return child as StaticBody3D
    return null

func _bind_when_ready() -> void:
    for _attempt: int in range(MAX_BIND_FRAMES):
        await get_tree().physics_frame
        var roads_root := get_tree().root.find_child("GeneratedRoads", true, false) as Node3D
        if roads_root == null:
            continue
        # Authority is explicit ownership, never a shared child name. A foreign
        # node may legitimately use BODY_NAME and must neither suppress nor be
        # mutated by this runtime.
        if _find_owned_body(roads_root) != null:
            return

        var scene_root := _scene_root_for(roads_root)
        var player := scene_root.get_node_or_null("Player") as CharacterBody3D
        if player == null:
            continue

        var support_faces := PackedVector3Array()
        var road_count := 0
        var sidewalk_count := 0
        for child: Node in roads_root.get_children():
            if not child is CSGBox3D:
                continue
            var box := child as CSGBox3D
            # This support is defined as a physical mirror of the *currently
            # rendered* generic OSM surfaces. Exact-zone masks intentionally
            # hide approximate OSM slabs; colliding against those hidden slabs
            # would reintroduce superseded geometry into player grounding.
            if not box.is_visible_in_tree():
                continue
            var is_road := box.name.begins_with("Road_") and absf(box.size.y - ROAD_HEIGHT_M) <= HEIGHT_EPSILON_M
            var is_sidewalk := absf(box.size.y - SIDEWALK_HEIGHT_M) <= HEIGHT_EPSILON_M
            if not is_road and not is_sidewalk:
                continue
            _append_top_face(support_faces, box)
            if is_road:
                road_count += 1
            else:
                sidewalk_count += 1

        if road_count == 0 or support_faces.is_empty():
            continue

        var support_shape := ConcavePolygonShape3D.new()
        support_shape.backface_collision = false
        support_shape.set_faces(support_faces)

        var collision_shape := CollisionShape3D.new()
        collision_shape.name = SHAPE_NAME
        collision_shape.shape = support_shape

        var collision_body := StaticBody3D.new()
        collision_body.name = BODY_NAME
        collision_body.set_meta(OWNER_META, OWNER_ID)
        # The support is a Player-only grounding query surface. Keeping it on a
        # dedicated layer prevents traffic, NPCs, SpringArm and other layer-1
        # consumers from being perturbed by a physics-only Environment fix.
        collision_body.collision_layer = SUPPORT_COLLISION_LAYER
        collision_body.collision_mask = SUPPORT_COLLISION_MASK
        player.collision_mask |= SUPPORT_COLLISION_LAYER
        collision_body.set_meta("road_support_surfaces", road_count)
        collision_body.set_meta("sidewalk_support_surfaces", sidewalk_count)
        collision_body.set_meta("support_shape_count", 1)
        collision_body.set_meta("support_triangle_count", int(support_faces.size() / 3))
        collision_body.set_meta("support_mode", "top_surfaces_only")
        collision_body.set_meta("visible_surfaces_only", true)
        collision_body.set_meta("player_only_collision", true)
        collision_body.set_meta("support_collision_layer", SUPPORT_COLLISION_LAYER)
        collision_body.set_meta("support_collision_mask", SUPPORT_COLLISION_MASK)
        collision_body.set_meta("source_geometry_changed", false)
        collision_body.set_meta("source_height_inferred", false)
        collision_body.set_meta("visual_output_changed", false)
        collision_body.set_meta("render_geometry_count", 0)
        collision_body.add_child(collision_shape)
        roads_root.add_child(collision_body)

        _road_surfaces = road_count
        _sidewalk_surfaces = sidewalk_count
        _triangle_count = int(support_faces.size() / 3)
        _ready_complete = true
        print("GENERIC_OSM_SURFACE_COLLISIONS_READY: roads=%d sidewalks=%d body_count=1 shape_count=1 triangles=%d support_mode=top_surfaces_only visible_surfaces_only=true player_only_collision=true collision_layer=%d collision_mask=%d source_geometry_changed=false source_height_inferred=false visual_output_changed=false render_geometry_count=0 owner=%s" % [_road_surfaces, _sidewalk_surfaces, _triangle_count, SUPPORT_COLLISION_LAYER, SUPPORT_COLLISION_MASK, OWNER_ID])
        return
    push_error("GENERIC_OSM_SURFACE_COLLISIONS_FAIL: GeneratedRoads or canonical Player unavailable")

func readiness() -> Dictionary:
    return {
        "ready": _ready_complete,
        "road_collisions": _road_surfaces,
        "sidewalk_collisions": _sidewalk_surfaces,
        "body_count": 1 if _ready_complete else 0,
        "shape_count": 1 if _ready_complete else 0,
        "triangle_count": _triangle_count,
        "support_mode": "top_surfaces_only",
        "visible_surfaces_only": true,
        "player_only_collision": true,
        "support_collision_layer": SUPPORT_COLLISION_LAYER,
        "support_collision_mask": SUPPORT_COLLISION_MASK,
        "source_geometry_changed": false,
        "source_height_inferred": false,
        "visual_output_changed": false,
        "render_geometry_count": 0,
        "owner": OWNER_ID,
    }
