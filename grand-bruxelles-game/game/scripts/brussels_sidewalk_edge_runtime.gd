extends Node

const MATERIAL_FAMILY := "brussels_sidewalk_edge_v1"
const EXPECTED_WIDTHS := [1.85, 2.55]
const WIDTH_TOLERANCE := 0.02
const HEIGHT := 0.12
const HEIGHT_TOLERANCE := 0.005
const EDGE_WIDTH := 0.12
const EDGE_HEIGHT := 0.10
const ROAD_LENGTH_TOLERANCE := 0.02
const ROAD_AXIS_DOT_MIN := 0.999
const ROAD_MATCH_MAX_M := 8.0
const CROSSING_AXIS_DOT_MAX := 0.92
const CROSSING_CLEARANCE_M := 0.22
const MIN_EDGE_SEGMENT_M := 0.80
const placement_provenance := "authored_presentation_from_existing_sidewalk_geometry_and_crossing_road_envelopes"
const source_height_claimed := false

var _visual: MultiMeshInstance3D
var _sidewalks: Array[CSGBox3D] = []
var _original_transforms: Dictionary = {}
var _original_sizes: Dictionary = {}
var _edge_segment_count := 0
var _crossing_clip_count := 0
var _ready_complete := false
var _failed := false
var _enhanced_enabled := true

func _ready() -> void:
    call_deferred("_apply_production_when_ready")

func _apply_production_when_ready() -> void:
    for _attempt: int in range(180):
        await get_tree().process_frame
        var scene := get_tree().current_scene as Node3D
        if scene != null and scene.find_child("GeneratedRoads", true, false) != null:
            bind_scene(scene)
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

func _clip_axis(start: float, delta: float, minimum: float, maximum: float, interval: Vector2) -> Vector2:
    if interval.x > interval.y:
        return interval
    if absf(delta) < 0.000001:
        return interval if start >= minimum and start <= maximum else Vector2(1.0, -1.0)
    var t1 := (minimum - start) / delta
    var t2 := (maximum - start) / delta
    var low := minf(t1, t2)
    var high := maxf(t1, t2)
    return Vector2(maxf(interval.x, low), minf(interval.y, high))

func _line_road_interval(world_start: Vector3, world_end: Vector3, road: CSGBox3D) -> Vector2:
    var inverse := road.global_transform.affine_inverse()
    var p0 := inverse * world_start
    var p1 := inverse * world_end
    var delta := p1 - p0
    var half_x := road.size.x * 0.5 + EDGE_WIDTH * 0.5 + CROSSING_CLEARANCE_M
    var half_z := road.size.z * 0.5 + CROSSING_CLEARANCE_M
    var interval := Vector2(0.0, 1.0)
    interval = _clip_axis(p0.x, delta.x, -half_x, half_x, interval)
    interval = _clip_axis(p0.z, delta.z, -half_z, half_z, interval)
    if interval.x > interval.y or interval.y < 0.0 or interval.x > 1.0:
        return Vector2(1.0, -1.0)
    return Vector2(clampf(interval.x, 0.0, 1.0), clampf(interval.y, 0.0, 1.0))

func _blocked_intervals(sidewalk: CSGBox3D, matched_road: CSGBox3D, roads: Array[CSGBox3D], local_x: float) -> Array[Vector2]:
    var half_length := sidewalk.size.z * 0.5
    var world_start := sidewalk.global_transform * Vector3(local_x, 0.0, -half_length)
    var world_end := sidewalk.global_transform * Vector3(local_x, 0.0, half_length)
    var sidewalk_axis := sidewalk.global_transform.basis.z.normalized()
    var blocked: Array[Vector2] = []
    for road: CSGBox3D in roads:
        if road == matched_road:
            continue
        var road_axis := road.global_transform.basis.z.normalized()
        if absf(sidewalk_axis.dot(road_axis)) > CROSSING_AXIS_DOT_MAX:
            continue
        var interval := _line_road_interval(world_start, world_end, road)
        if interval.x > interval.y:
            continue
        var z0 := lerpf(-half_length, half_length, interval.x) - CROSSING_CLEARANCE_M
        var z1 := lerpf(-half_length, half_length, interval.y) + CROSSING_CLEARANCE_M
        blocked.append(Vector2(clampf(z0, -half_length, half_length), clampf(z1, -half_length, half_length)))
    blocked.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
    var merged: Array[Vector2] = []
    for interval: Vector2 in blocked:
        if merged.is_empty() or interval.x > merged[-1].y:
            merged.append(interval)
        else:
            var last := merged[-1]
            last.y = maxf(last.y, interval.y)
            merged[-1] = last
    return merged

func _append_edge_segment(transforms: Array[Transform3D], sidewalk: CSGBox3D, local_x: float, z0: float, z1: float) -> void:
    var segment_length := z1 - z0
    if segment_length < MIN_EDGE_SEGMENT_M:
        return
    var midpoint := (z0 + z1) * 0.5
    var edge_basis := sidewalk.global_transform.basis.scaled(Vector3(EDGE_WIDTH, EDGE_HEIGHT, segment_length))
    var edge_origin := sidewalk.global_transform * Vector3(local_x, 0.0, midpoint)
    transforms.append(Transform3D(edge_basis, edge_origin))

func _append_clipped_edge(transforms: Array[Transform3D], sidewalk: CSGBox3D, matched_road: CSGBox3D, roads: Array[CSGBox3D], local_x: float) -> int:
    var half_length := sidewalk.size.z * 0.5
    var blocked := _blocked_intervals(sidewalk, matched_road, roads, local_x)
    var clips := blocked.size()
    var cursor := -half_length
    for interval: Vector2 in blocked:
        _append_edge_segment(transforms, sidewalk, local_x, cursor, interval.x)
        cursor = maxf(cursor, interval.y)
    _append_edge_segment(transforms, sidewalk, local_x, cursor, half_length)
    return clips

func _make_material() -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = Color(0.225, 0.235, 0.240, 1.0)
    material.roughness = 0.96
    material.metallic = 0.0
    material.set_meta("material_family", MATERIAL_FAMILY)
    material.set_meta("visual_recipe_provenance", "authored_presentation_not_source_measurement")
    material.set_meta("crossing_clearance_source", "existing_generated_road_envelopes")
    return material

func bind_scene(scene: Node3D) -> void:
    _clear_visual()
    _sidewalks.clear()
    _original_transforms.clear()
    _original_sizes.clear()
    _edge_segment_count = 0
    _crossing_clip_count = 0
    _failed = false
    _ready_complete = false
    var roads_root := scene.find_child("GeneratedRoads", true, false) as Node3D
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
        sidewalk.set_meta("sidewalk_edge_material_family", MATERIAL_FAMILY)
        sidewalk.set_meta("sidewalk_edge_placement_provenance", placement_provenance)
        sidewalk.set_meta("sidewalk_edge_source_height_claimed", source_height_claimed)
        sidewalk.set_meta("sidewalk_edge_crossing_clipped", true)
        sidewalk.set_meta("geometry_changed_by_sidewalk_edge_runtime", false)
        var toward_road := road.global_position - sidewalk.global_position
        var local_x_axis := sidewalk.global_transform.basis.x.normalized()
        var road_side := 1.0 if toward_road.dot(local_x_axis) >= 0.0 else -1.0
        var local_x := road_side * (sidewalk.size.x * 0.5 - EDGE_WIDTH * 0.5)
        _crossing_clip_count += _append_clipped_edge(transforms, sidewalk, road, roads, local_x)
    if _sidewalks.is_empty() or transforms.is_empty():
        _failed = true
        _ready_complete = true
        return
    _edge_segment_count = transforms.size()
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
    _visual.set_meta("source_height_claimed", source_height_claimed)
    _visual.set_meta("crossing_clipped", true)
    _visual.set_meta("crossing_clip_count", _crossing_clip_count)
    _visual.set_meta("collision_count", 0)
    scene.add_child(_visual)
    _visual.visible = _enhanced_enabled
    _ready_complete = true
    print("BRUSSELS_SIDEWALK_EDGE_READY: sidewalks=%d edge_segments=%d crossing_clips=%d batches=1 collisions=0 road_facing_only=true crossing_clipped=true family=%s source_height_claimed=false" % [_sidewalks.size(), _edge_segment_count, _crossing_clip_count, MATERIAL_FAMILY])

func _clear_visual() -> void:
    if is_instance_valid(_visual):
        _visual.queue_free()
    _visual = null

func set_enhanced_enabled(enabled: bool) -> void:
    _enhanced_enabled = enabled
    if is_instance_valid(_visual):
        _visual.visible = enabled

func enhanced_enabled() -> bool: return _enhanced_enabled
func ready_complete() -> bool: return _ready_complete
func failed() -> bool: return _failed
func sidewalk_count() -> int: return _sidewalks.size() if _ready_complete and not _failed else 0
func edge_count() -> int: return sidewalk_count()
func edge_segment_count() -> int: return _edge_segment_count if _ready_complete and not _failed else 0
func crossing_clip_count() -> int: return _crossing_clip_count if _ready_complete and not _failed else 0
func batch_count() -> int: return 1 if is_instance_valid(_visual) else 0
func collision_count() -> int: return 0
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
func edge_visual_within_sidewalk_envelope() -> bool: return EDGE_WIDTH <= minf(EXPECTED_WIDTHS[0], EXPECTED_WIDTHS[1]) and EDGE_HEIGHT <= HEIGHT
func crossing_clipping_enabled() -> bool: return true
