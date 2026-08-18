extends Node3D

## Ixelles LABO-only life layer.
## Placement consumes the already-mounted official Ixelles StreetSurface / StreetAxis
## contracts. It does not expand geography and it does not claim surveyed lane geometry.

const CIVILIAN_VEHICLE_VISUAL := preload("res://game/scripts/civilian_vehicle_visual.gd")
const VEHICLE_AXIS_ID := "https://databrussels.be/id/streetaxe/71374:1"
const TARGET_AXIS_ID := "https://databrussels.be/id/streetaxe/71306:2"
const CAMERA_AXIS_T := 0.68
const PEDESTRIAN_SURFACE_TYPE := "SW"
const DISABLE_ENV := "GB_IXELLES_LIFE"
const CIVILIAN_COUNT := 8
const MOVING_VEHICLE_COUNT := 2
const MIN_PEDESTRIAN_DISTANCE_M := 5.0
const MAX_PEDESTRIAN_DISTANCE_M := 42.0
const MIN_FORWARD_DOT := 0.54
const MIN_ANCHOR_SEPARATION_M := 2.4

var _slice: Node = null
var _axis := PackedVector2Array()
var _target_axis := PackedVector2Array()
var _axis_length_m := 0.0
var _camera_xz := Vector2.ZERO
var _camera_forward := Vector2.ZERO
var _pedestrian_anchors: Array[Vector2] = []
var _pedestrian_source_ids: Array[String] = []
var _civilians: Array[Node3D] = []
var _moving: Array[Node3D] = []
var _vehicle_t: Array[float] = []
var _vehicle_speed_mps: Array[float] = []
var _all_pedestrian_anchors_inside_source := false
var _all_pedestrian_anchors_in_spawn_view := false
var _ready_complete := false
var _failed := false

func _ready() -> void:
    add_to_group("zone_life")
    if OS.get_environment(DISABLE_ENV) == "0":
        _ready_complete = true
        set_process(false)
        print("IXELLES_LAB_LIFE_DISABLED: witness_only=true")
        return
    _slice = get_parent().get_node_or_null("IxellesDirectMicroSlice")
    if _slice == null or not bool(_slice.get("runtime_loaded")):
        _stop("source Ixelles micro-slice missing")
        return
    if not _load_spawn_axes():
        _stop("accepted official StreetAxis witnesses unavailable")
        return
    if not _load_pedestrian_anchors():
        _stop("insufficient official SW StreetSurface anchors in direct-spawn sightline")
        return
    _build_civilians()
    _build_moving_vehicles()
    if _civilians.size() != CIVILIAN_COUNT or _moving.size() != MOVING_VEHICLE_COUNT:
        _stop("life node counts incomplete")
        return
    _ready_complete = true
    set_process(true)
    print("IXELLES_LAB_LIFE_READY: civilians=%d moving=%d vehicle_axis=%s pedestrian_surface=%s anchors_in_spawn_view=%s geography_expanded=false lane_geometry_claimed=false" % [_civilians.size(), _moving.size(), VEHICLE_AXIS_ID, PEDESTRIAN_SURFACE_TYPE, str(_all_pedestrian_anchors_in_spawn_view).to_lower()])

func _stop(message: String) -> void:
    _failed = true
    _ready_complete = true
    set_process(false)
    push_error("Ixelles LABO life: %s" % message)

func _process(delta: float) -> void:
    if not _ready_complete or _failed or _moving.is_empty():
        return
    for i: int in range(_moving.size()):
        _vehicle_t[i] = fposmod(_vehicle_t[i] + (_vehicle_speed_mps[i] * delta / _axis_length_m), 1.0)
        _place_vehicle(i)

func ready_complete() -> bool:
    return _ready_complete

func failed() -> bool:
    return _failed

func get_counts() -> Dictionary:
    return {
        "civilians": _civilians.size(),
        "moving_vehicles": _moving.size(),
    }

func has_minimum_playable_life() -> bool:
    return _ready_complete and not _failed and _civilians.size() > 0 and _moving.size() > 0

func source_contract() -> Dictionary:
    return {
        "vehicle_axis_id": VEHICLE_AXIS_ID,
        "target_axis_id": TARGET_AXIS_ID,
        "pedestrian_surface_type": PEDESTRIAN_SURFACE_TYPE,
        "pedestrian_anchor_count": _pedestrian_anchors.size(),
        "all_pedestrian_anchors_inside_source": _all_pedestrian_anchors_inside_source,
        "all_pedestrian_anchors_in_spawn_view": _all_pedestrian_anchors_in_spawn_view,
        "lane_geometry_claimed": false,
        "geography_expanded": false,
        "terrain_changed": false,
        "street_geometry_changed": false,
    }

func moving_probe_position() -> Vector3:
    if _moving.is_empty():
        return Vector3(NAN, NAN, NAN)
    return _moving[0].global_position

func _axis_segment(axis_id: String) -> PackedVector2Array:
    var network: Dictionary = _slice.get_meta("ixelles_network_contract", {})
    var axes: Variant = network.get("street_axes", [])
    if not axes is Array:
        return PackedVector2Array()
    for raw: Variant in axes:
        if not raw is Dictionary or str((raw as Dictionary).get("id", "")) != axis_id:
            continue
        var points: Variant = (raw as Dictionary).get("points", [])
        if not points is Array or points.size() != 2:
            return PackedVector2Array()
        var result := PackedVector2Array()
        for point: Variant in points:
            if not point is Array or point.size() < 2:
                return PackedVector2Array()
            result.append(Vector2(float(point[0]), float(point[1])))
        return result
    return PackedVector2Array()

func _load_spawn_axes() -> bool:
    _axis = _axis_segment(VEHICLE_AXIS_ID)
    _target_axis = _axis_segment(TARGET_AXIS_ID)
    if _axis.size() != 2 or _target_axis.size() != 2:
        return false
    _axis_length_m = _axis[0].distance_to(_axis[1])
    if _axis_length_m < 8.0:
        return false
    _camera_xz = _axis[0].lerp(_axis[1], CAMERA_AXIS_T)
    _camera_forward = (_target_axis[1] - _camera_xz).normalized()
    return _camera_forward.length_squared() > 0.99

func _ring(raw: Variant) -> PackedVector2Array:
    var ring := PackedVector2Array()
    if not raw is Array:
        return ring
    for pair: Variant in raw:
        if pair is Array and pair.size() >= 2:
            ring.append(Vector2(float(pair[0]), float(pair[1])))
    if ring.size() >= 2 and ring[0].is_equal_approx(ring[ring.size() - 1]):
        ring.remove_at(ring.size() - 1)
    return ring

func _candidate_in_spawn_view(point: Vector2) -> Dictionary:
    var delta := point - _camera_xz
    var distance := delta.length()
    if distance < MIN_PEDESTRIAN_DISTANCE_M or distance > MAX_PEDESTRIAN_DISTANCE_M:
        return {}
    var forward_dot := delta.normalized().dot(_camera_forward)
    if forward_dot < MIN_FORWARD_DOT:
        return {}
    # Prioritize close anchors and the centre of the accepted source-backed view.
    var score := distance + (1.0 - forward_dot) * 28.0
    return {
        "distance": distance,
        "forward_dot": forward_dot,
        "score": score,
    }

func _append_surface_candidates(feature: Dictionary, ring: PackedVector2Array, out: Array[Dictionary]) -> void:
    var indices := Geometry2D.triangulate_polygon(ring)
    if indices.size() < 3:
        return
    var source_id := str(feature.get("id", ""))
    for offset: int in range(0, indices.size(), 3):
        var a := ring[indices[offset]]
        var b := ring[indices[offset + 1]]
        var c := ring[indices[offset + 2]]
        var point := (a + b + c) / 3.0
        if not Geometry2D.is_point_in_polygon(point, ring):
            continue
        var view := _candidate_in_spawn_view(point)
        if view.is_empty():
            continue
        out.append({
            "point": point,
            "distance": float(view.get("distance", 0.0)),
            "forward_dot": float(view.get("forward_dot", 0.0)),
            "score": float(view.get("score", 0.0)),
            "source_id": source_id,
        })

func _load_pedestrian_anchors() -> bool:
    var cell: Dictionary = _slice.get_meta("ixelles_cell_contract", {})
    var surfaces: Variant = cell.get("street_surfaces", [])
    if not surfaces is Array:
        return false
    var candidates: Array[Dictionary] = []
    for raw: Variant in surfaces:
        if not raw is Dictionary:
            continue
        var feature := raw as Dictionary
        if str(feature.get("type", "")) != PEDESTRIAN_SURFACE_TYPE:
            continue
        var ring := _ring(feature.get("polygon", []))
        if ring.size() < 3:
            continue
        _append_surface_candidates(feature, ring, candidates)
    candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        var sa := float(a.get("score", 0.0))
        var sb := float(b.get("score", 0.0))
        if absf(sa - sb) <= 0.0001:
            return str(a.get("source_id", "")) < str(b.get("source_id", ""))
        return sa < sb
    )
    if candidates.size() < CIVILIAN_COUNT:
        print("IXELLES_LAB_LIFE_VIEW_CANDIDATES: count=%d required=%d" % [candidates.size(), CIVILIAN_COUNT])
        return false

    _pedestrian_anchors.clear()
    _pedestrian_source_ids.clear()
    for candidate: Dictionary in candidates:
        var point := candidate.get("point") as Vector2
        var separated := true
        for selected: Vector2 in _pedestrian_anchors:
            if point.distance_to(selected) < MIN_ANCHOR_SEPARATION_M:
                separated = false
                break
        if not separated:
            continue
        _pedestrian_anchors.append(point)
        _pedestrian_source_ids.append(str(candidate.get("source_id", "")))
        if _pedestrian_anchors.size() == CIVILIAN_COUNT:
            break
    if _pedestrian_anchors.size() != CIVILIAN_COUNT:
        print("IXELLES_LAB_LIFE_VIEW_DIVERSITY_FAIL: selected=%d candidates=%d" % [_pedestrian_anchors.size(), candidates.size()])
        return false
    _all_pedestrian_anchors_inside_source = _verify_pedestrian_anchors_inside_source(surfaces)
    _all_pedestrian_anchors_in_spawn_view = _verify_pedestrian_anchors_in_spawn_view()
    print("IXELLES_LAB_LIFE_VIEW_ANCHORS: candidates=%d selected=%d nearest=%.2f farthest=%.2f min_forward_dot=%.3f" % [candidates.size(), _pedestrian_anchors.size(), _pedestrian_anchors[0].distance_to(_camera_xz), _pedestrian_anchors[_pedestrian_anchors.size() - 1].distance_to(_camera_xz), _minimum_selected_forward_dot()])
    return _all_pedestrian_anchors_inside_source and _all_pedestrian_anchors_in_spawn_view

func _verify_pedestrian_anchors_inside_source(surfaces: Array) -> bool:
    for point: Vector2 in _pedestrian_anchors:
        var inside_sw := false
        for raw: Variant in surfaces:
            if not raw is Dictionary or str((raw as Dictionary).get("type", "")) != PEDESTRIAN_SURFACE_TYPE:
                continue
            var ring := _ring((raw as Dictionary).get("polygon", []))
            if ring.size() >= 3 and Geometry2D.is_point_in_polygon(point, ring):
                inside_sw = true
                break
        if not inside_sw:
            return false
    return true

func _verify_pedestrian_anchors_in_spawn_view() -> bool:
    if _pedestrian_anchors.size() != CIVILIAN_COUNT:
        return false
    for point: Vector2 in _pedestrian_anchors:
        if _candidate_in_spawn_view(point).is_empty():
            return false
    return true

func _minimum_selected_forward_dot() -> float:
    var minimum := 1.0
    for point: Vector2 in _pedestrian_anchors:
        var delta := point - _camera_xz
        if delta.length_squared() > 0.001:
            minimum = minf(minimum, delta.normalized().dot(_camera_forward))
    return minimum

func _build_civilians() -> void:
    var clothing := [
        Color(0.12, 0.16, 0.22), Color(0.31, 0.13, 0.11), Color(0.13, 0.25, 0.18), Color(0.28, 0.25, 0.21),
        Color(0.20, 0.12, 0.25), Color(0.10, 0.24, 0.29), Color(0.36, 0.31, 0.16), Color(0.17, 0.17, 0.18)
    ]
    var skin := [Color(0.84,0.65,0.50), Color(0.65,0.45,0.31), Color(0.43,0.28,0.20), Color(0.29,0.19,0.14)]
    for i: int in range(CIVILIAN_COUNT):
        var person := Node3D.new()
        person.name = "IxellesCivilian_%02d" % i
        person.add_to_group("ambient_pedestrian")
        person.set_meta("source_surface_type", PEDESTRIAN_SURFACE_TYPE)
        person.set_meta("source_surface_id", _pedestrian_source_ids[i])
        person.set_meta("source_point_inside_official_surface", true)
        person.set_meta("source_point_in_direct_spawn_view", true)
        add_child(person)
        var jacket := _material(clothing[i % clothing.size()], 0.88)
        var pants := _material(clothing[(i + 3) % clothing.size()].darkened(0.30), 0.92)
        var face := _material(skin[(i * 3) % skin.size()], 0.82)
        _box(person, Vector3(0.46, 0.62, 0.27), Vector3(0.0, 1.14, 0.0), jacket)
        _box(person, Vector3(0.16, 0.66, 0.19), Vector3(-0.12, 0.47, 0.0), pants)
        _box(person, Vector3(0.16, 0.66, 0.19), Vector3(0.12, 0.47, 0.0), pants)
        var head := MeshInstance3D.new()
        var sphere := SphereMesh.new()
        sphere.radius = 0.21
        sphere.height = 0.42
        head.mesh = sphere
        head.material_override = face
        head.position = Vector3(0.0, 1.65, 0.0)
        person.add_child(head)
        var anchor := _pedestrian_anchors[i]
        var ground_y := float(_slice.call("sample_height", anchor.x, anchor.y))
        person.position = Vector3(anchor.x, ground_y + 0.03, anchor.y)
        var toward_camera := _camera_xz - anchor
        if toward_camera.length_squared() > 0.001:
            person.rotation.y = atan2(-toward_camera.x, -toward_camera.y)
        _civilians.append(person)

func _build_moving_vehicles() -> void:
    var colors := [Color(0.08, 0.13, 0.20), Color(0.42, 0.40, 0.36)]
    var axis_forward := (_axis[1] - _axis[0]).normalized()
    var toward_endpoint_one := axis_forward.dot(_camera_forward)
    var forward_sign := 1.0 if toward_endpoint_one >= 0.0 else -1.0
    var first_delta := minf(12.0 / _axis_length_m, 0.12)
    var second_delta := minf(23.0 / _axis_length_m, 0.22)
    var starts := [
        clampf(CAMERA_AXIS_T + forward_sign * first_delta, 0.04, 0.96),
        clampf(CAMERA_AXIS_T + forward_sign * second_delta, 0.04, 0.96),
    ]
    var speeds := [4.2 * forward_sign, -3.8 * forward_sign]
    for i: int in range(MOVING_VEHICLE_COUNT):
        var car := Node3D.new()
        car.name = "IxellesTraffic_%02d" % i
        car.add_to_group("ambient_traffic")
        car.set_meta("source_axis_id", VEHICLE_AXIS_ID)
        car.set_meta("lane_geometry_claimed", false)
        var visual := Node3D.new()
        visual.name = "ProductionVisual"
        visual.set_script(CIVILIAN_VEHICLE_VISUAL)
        visual.set("paint_color", colors[i % colors.size()])
        car.add_child(visual)
        add_child(car)
        _moving.append(car)
        _vehicle_t.append(starts[i])
        _vehicle_speed_mps.append(speeds[i])
        _place_vehicle(i)

func _place_vehicle(i: int) -> void:
    var t := _vehicle_t[i]
    var xz := _axis[0].lerp(_axis[1], t)
    var ground_y := float(_slice.call("sample_height", xz.x, xz.y))
    var car := _moving[i]
    car.position = Vector3(xz.x, ground_y + 0.46, xz.y)
    var direction := (_axis[1] - _axis[0]).normalized() * signf(_vehicle_speed_mps[i])
    car.rotation.y = atan2(-direction.x, -direction.y)

func _material(color: Color, roughness: float) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = roughness
    return material

func _box(parent: Node3D, size: Vector3, position: Vector3, material: Material) -> void:
    var mesh_instance := MeshInstance3D.new()
    var mesh := BoxMesh.new()
    mesh.size = size
    mesh_instance.mesh = mesh
    mesh_instance.material_override = material
    mesh_instance.position = position
    parent.add_child(mesh_instance)