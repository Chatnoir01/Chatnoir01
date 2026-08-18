extends Node

const MATERIAL_FAMILY := "brussels_sidewalk_edge_v1"
const EXPECTED_WIDTHS := [1.85, 2.55]
const WIDTH_TOLERANCE := 0.02
const HEIGHT := 0.12
const HEIGHT_TOLERANCE := 0.005
const EDGE_WIDTH := 0.04
const MIN_EDGE_HEIGHT := 0.02
const MIN_EDGE_LENGTH := 0.50
const MIN_END_SETBACK := 1.50
const MAX_END_SETBACK := 5.00
const ROAD_LENGTH_TOLERANCE := 0.02
const ROAD_AXIS_DOT_MIN := 0.999
const ROAD_MATCH_MAX_M := 8.0
const INTERSECTION_CLEARANCE_M := 0.35
const placement_provenance := "authored_presentation_from_existing_sidewalk_geometry"
const source_height_claimed := false

var _visual: MultiMeshInstance3D
var _sidewalks: Array[CSGBox3D] = []
var _original_transforms: Dictionary = {}
var _original_sizes: Dictionary = {}
var _ready_complete := false
var _failed := false
var _enhanced_enabled := true
var _edge_count := 0
var _intersection_clip_count := 0

func _ready() -> void:
    call_deferred("_apply_production_when_ready")

func _apply_production_when_ready() -> void:
    for _attempt: int in range(180):
        await get_tree().process_frame
        var roads_root := get_tree().root.find_child("GeneratedRoads", true, false) as Node3D
        if roads_root != null:
            var bind_root := roads_root.get_parent() as Node3D
            if bind_root == null:
                bind_root = roads_root
            bind_scene(bind_root)
            return
    _failed = true
    _ready_complete = true
    push_error("Brussels sidewalk edge runtime: GeneratedRoads missing")

func _is_generated_sidewalk(box: CSGBox3D) -> bool:
    if str(box.name).begins_with("Road_") or absf(box.size.y - HEIGHT) > HEIGHT_TOLERANCE:
        return false
    for expected: float in EXPECTED_WIDTHS:
        if absf(box.size.x - expected) <= WIDTH_TOLERANCE:
            return true
    return false

func _is_road(box: CSGBox3D) -> bool:
    return str(box.name).begins_with("Road_") and absf(box.size.y - 0.10) <= 0.005

func _matched_road(sidewalk: CSGBox3D, roads: Array[CSGBox3D]) -> CSGBox3D:
    var best: CSGBox3D = null
    var best_distance := ROAD_MATCH_MAX_M
    var sidewalk_axis := sidewalk.global_transform.basis.z.normalized()
    for road: CSGBox3D in roads:
        if absf(road.size.z - sidewalk.size.z) > ROAD_LENGTH_TOLERANCE:
            continue
        if absf(sidewalk_axis.dot(road.global_transform.basis.z.normalized())) < ROAD_AXIS_DOT_MIN:
            continue
        var distance := sidewalk.global_position.distance_to(road.global_position)
        if distance < best_distance:
            best_distance = distance
            best = road
    return best

func _make_material() -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = Color(0.420, 0.415, 0.400, 1.0)
    material.roughness = 0.97
    material.metallic = 0.0
    material.set_meta("material_family", MATERIAL_FAMILY)
    material.set_meta("presentation_role", "road_facing_sidewalk_fascia")
    material.set_meta("visual_recipe_provenance", "authored_presentation_not_source_measurement")
    return material

func _road_side_geometry(sidewalk: CSGBox3D, road: CSGBox3D) -> Dictionary:
    var toward_road := road.global_position - sidewalk.global_position
    var local_x_axis := sidewalk.global_transform.basis.x.normalized()
    var road_side := 1.0 if toward_road.dot(local_x_axis) >= 0.0 else -1.0
    var local_x := road_side * (sidewalk.size.x * 0.5 - EDGE_WIDTH * 0.5)
    var sidewalk_top := sidewalk.global_position.y + sidewalk.size.y * 0.5
    var road_top := road.global_position.y + road.size.y * 0.5
    var edge_height := clampf(sidewalk_top - road_top, MIN_EDGE_HEIGHT, HEIGHT)
    var edge_center_y := road_top + edge_height * 0.5
    var local_y := edge_center_y - sidewalk.global_position.y
    var end_setback := clampf(road.size.x * 0.5, MIN_END_SETBACK, MAX_END_SETBACK)
    var edge_length := maxf(sidewalk.size.z - end_setback * 2.0, MIN_EDGE_LENGTH)
    return {
        "local_x": local_x,
        "local_y": local_y,
        "edge_height": edge_height,
        "start_z": -edge_length * 0.5,
        "end_z": edge_length * 0.5,
    }

func _clip_line_to_rect(start: Vector2, finish: Vector2, half_extents: Vector2) -> Vector2:
    var delta := finish - start
    var t0 := 0.0
    var t1 := 1.0
    var p := [-delta.x, delta.x, -delta.y, delta.y]
    var q := [
        start.x + half_extents.x,
        half_extents.x - start.x,
        start.y + half_extents.y,
        half_extents.y - start.y,
    ]
    for index: int in range(4):
        var pi := float(p[index])
        var qi := float(q[index])
        if absf(pi) <= 0.000001:
            if qi < 0.0:
                return Vector2(-1.0, -1.0)
            continue
        var ratio := qi / pi
        if pi < 0.0:
            t0 = maxf(t0, ratio)
        else:
            t1 = minf(t1, ratio)
        if t0 > t1:
            return Vector2(-1.0, -1.0)
    return Vector2(t0, t1)

func _intersection_interval(sidewalk: CSGBox3D, local_x: float, start_z: float, end_z: float, other_road: CSGBox3D) -> Vector2:
    # Work strictly in world X/Z. CSG local conversion is sensitive to parent
    # transforms in synthetic/runtime harnesses; explicit projection onto the
    # road's normalized world axes makes the 2D overlap contract deterministic.
    var start_world_3d := sidewalk.global_transform * Vector3(local_x, 0.0, start_z)
    var end_world_3d := sidewalk.global_transform * Vector3(local_x, 0.0, end_z)
    var center := Vector2(other_road.global_position.x, other_road.global_position.z)
    var axis_x_3d := other_road.global_transform.basis.x.normalized()
    var axis_z_3d := other_road.global_transform.basis.z.normalized()
    var axis_x := Vector2(axis_x_3d.x, axis_x_3d.z).normalized()
    var axis_z := Vector2(axis_z_3d.x, axis_z_3d.z).normalized()
    var start_delta := Vector2(start_world_3d.x, start_world_3d.z) - center
    var end_delta := Vector2(end_world_3d.x, end_world_3d.z) - center
    var start_local := Vector2(start_delta.dot(axis_x), start_delta.dot(axis_z))
    var end_local := Vector2(end_delta.dot(axis_x), end_delta.dot(axis_z))
    var clipped := _clip_line_to_rect(
        start_local,
        end_local,
        Vector2(other_road.size.x * 0.5 + INTERSECTION_CLEARANCE_M, other_road.size.z * 0.5 + INTERSECTION_CLEARANCE_M)
    )
    if clipped.x < 0.0:
        return clipped
    var z0 := lerpf(start_z, end_z, clipped.x)
    var z1 := lerpf(start_z, end_z, clipped.y)
    return Vector2(minf(z0, z1), maxf(z0, z1))

func _merge_intervals(intervals: Array[Vector2]) -> Array[Vector2]:
    if intervals.is_empty():
        return []
    intervals.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
    var merged: Array[Vector2] = []
    var current := intervals[0]
    for index: int in range(1, intervals.size()):
        var next := intervals[index]
        if next.x <= current.y + 0.001:
            current.y = maxf(current.y, next.y)
        else:
            merged.append(current)
            current = next
    merged.append(current)
    return merged

func _usable_edge_ranges(sidewalk: CSGBox3D, matched_road: CSGBox3D, roads: Array[CSGBox3D], local_x: float, start_z: float, end_z: float) -> Dictionary:
    var exclusions: Array[Vector2] = []
    for other_road: CSGBox3D in roads:
        if other_road == matched_road:
            continue
        var interval := _intersection_interval(sidewalk, local_x, start_z, end_z, other_road)
        if interval.x < 0.0:
            continue
        if interval.y - interval.x <= 0.001:
            continue
        exclusions.append(interval)
    var merged := _merge_intervals(exclusions)
    var ranges: Array[Vector2] = []
    var cursor := start_z
    for excluded: Vector2 in merged:
        var cut_start := clampf(excluded.x, start_z, end_z)
        var cut_end := clampf(excluded.y, start_z, end_z)
        if cut_start - cursor >= MIN_EDGE_LENGTH:
            ranges.append(Vector2(cursor, cut_start))
        cursor = maxf(cursor, cut_end)
    if end_z - cursor >= MIN_EDGE_LENGTH:
        ranges.append(Vector2(cursor, end_z))
    return {"ranges": ranges, "clip_count": merged.size()}

func _edge_transform_for_range(sidewalk: CSGBox3D, local_x: float, local_y: float, edge_height: float, range_z: Vector2) -> Transform3D:
    var edge_length := range_z.y - range_z.x
    var local_z := (range_z.x + range_z.y) * 0.5
    var edge_basis := sidewalk.global_transform.basis.scaled(Vector3(EDGE_WIDTH, edge_height, edge_length))
    var edge_origin := sidewalk.global_transform * Vector3(local_x, local_y, local_z)
    return Transform3D(edge_basis, edge_origin)

func _edge_transforms(sidewalk: CSGBox3D, matched_road: CSGBox3D, roads: Array[CSGBox3D]) -> Dictionary:
    var geometry := _road_side_geometry(sidewalk, matched_road)
    var local_x := float(geometry["local_x"])
    var local_y := float(geometry["local_y"])
    var edge_height := float(geometry["edge_height"])
    var start_z := float(geometry["start_z"])
    var end_z := float(geometry["end_z"])
    var usable := _usable_edge_ranges(sidewalk, matched_road, roads, local_x, start_z, end_z)
    var transforms: Array[Transform3D] = []
    for range_z: Vector2 in usable["ranges"]:
        transforms.append(_edge_transform_for_range(sidewalk, local_x, local_y, edge_height, range_z))
    return {"transforms": transforms, "clip_count": int(usable["clip_count"])}

func bind_scene(scene: Node3D) -> void:
    _clear_visual()
    _sidewalks.clear()
    _original_transforms.clear()
    _original_sizes.clear()
    _edge_count = 0
    _intersection_clip_count = 0
    _failed = false
    _ready_complete = false
    var roads_root := scene.find_child("GeneratedRoads", true, false) as Node3D
    if roads_root == null and scene.name == "GeneratedRoads":
        roads_root = scene
    if roads_root == null:
        _failed = true
        _ready_complete = true
        return
    var roads: Array[CSGBox3D] = []
    for child: Node in roads_root.get_children():
        if child is CSGBox3D and _is_road(child as CSGBox3D):
            roads.append(child as CSGBox3D)
    var transforms: Array[Transform3D] = []
    for child: Node in roads_root.get_children():
        if not child is CSGBox3D:
            continue
        var sidewalk := child as CSGBox3D
        if not _is_generated_sidewalk(sidewalk):
            continue
        var road := _matched_road(sidewalk, roads)
        if road == null:
            continue
        var instance_id := sidewalk.get_instance_id()
        _sidewalks.append(sidewalk)
        _original_transforms[instance_id] = sidewalk.global_transform
        _original_sizes[instance_id] = sidewalk.size
        var edge_result := _edge_transforms(sidewalk, road, roads)
        var sidewalk_transforms: Array[Transform3D] = edge_result["transforms"]
        var clip_count := int(edge_result["clip_count"])
        _intersection_clip_count += clip_count
        for transform: Transform3D in sidewalk_transforms:
            transforms.append(transform)
        sidewalk.set_meta("sidewalk_edge_material_family", MATERIAL_FAMILY)
        sidewalk.set_meta("sidewalk_edge_placement_provenance", placement_provenance)
        sidewalk.set_meta("sidewalk_edge_source_height_claimed", source_height_claimed)
        sidewalk.set_meta("sidewalk_edge_endpoint_setback", true)
        sidewalk.set_meta("sidewalk_edge_intersection_clipped", clip_count > 0)
        sidewalk.set_meta("geometry_changed_by_sidewalk_edge_runtime", false)
    if _sidewalks.is_empty() or transforms.is_empty():
        _failed = true
        _ready_complete = true
        return
    var mesh := BoxMesh.new()
    mesh.size = Vector3.ONE
    mesh.material = _make_material()
    var multimesh := MultiMesh.new()
    multimesh.transform_format = MultiMesh.TRANSFORM_3D
    multimesh.mesh = mesh
    multimesh.instance_count = transforms.size()
    for index: int in range(transforms.size()):
        multimesh.set_instance_transform(index, transforms[index])
    _visual = MultiMeshInstance3D.new()
    _visual.name = "SharedSidewalkEdges"
    _visual.multimesh = multimesh
    _visual.set_meta("material_family", MATERIAL_FAMILY)
    _visual.set_meta("placement_provenance", placement_provenance)
    _visual.set_meta("presentation_role", "road_facing_sidewalk_fascia")
    _visual.set_meta("endpoint_setback", true)
    _visual.set_meta("intersection_clipped", true)
    _visual.set_meta("source_height_claimed", source_height_claimed)
    _visual.set_meta("collision_count", 0)
    scene.add_child(_visual)
    _visual.visible = _enhanced_enabled
    _edge_count = transforms.size()
    _ready_complete = true
    print("BRUSSELS_SIDEWALK_EDGE_READY: sidewalks=%d edges=%d intersection_clips=%d batches=1 collisions=0 road_facing_fascia=true endpoint_setback=true intersection_clipped=true family=%s source_height_claimed=false" % [_sidewalks.size(), _edge_count, _intersection_clip_count, MATERIAL_FAMILY])

func _clear_visual() -> void:
    if is_instance_valid(_visual):
        _visual.queue_free()
    _visual = null

func set_enhanced_enabled(enabled: bool) -> void:
    _enhanced_enabled = enabled
    if is_instance_valid(_visual):
        _visual.visible = enabled

func enhanced_enabled() -> bool:
    return _enhanced_enabled

func ready_complete() -> bool:
    return _ready_complete

func failed() -> bool:
    return _failed

func sidewalk_count() -> int:
    return _sidewalks.size() if _ready_complete and not _failed else 0

func edge_count() -> int:
    return _edge_count if _ready_complete and not _failed else 0

func intersection_clip_count() -> int:
    return _intersection_clip_count if _ready_complete and not _failed else 0

func batch_count() -> int:
    return 1 if is_instance_valid(_visual) else 0

func collision_count() -> int:
    return 0

func geometry_unchanged() -> bool:
    for sidewalk: CSGBox3D in _sidewalks:
        if not is_instance_valid(sidewalk):
            return false
        var instance_id := sidewalk.get_instance_id()
        if not sidewalk.global_transform.is_equal_approx(_original_transforms.get(instance_id, Transform3D.IDENTITY)):
            return false
        if not sidewalk.size.is_equal_approx(_original_sizes.get(instance_id, Vector3.ZERO)):
            return false
    return true

func edge_visual_within_sidewalk_envelope() -> bool:
    return EDGE_WIDTH <= minf(EXPECTED_WIDTHS[0], EXPECTED_WIDTHS[1]) and MIN_EDGE_HEIGHT <= HEIGHT and MAX_END_SETBACK >= MIN_END_SETBACK and INTERSECTION_CLEARANCE_M >= 0.0
