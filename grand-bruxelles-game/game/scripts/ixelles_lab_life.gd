extends Node3D

## Ixelles LABO-only life layer.
## Placement consumes the already-mounted official Ixelles StreetSurface / StreetAxis
## contracts. It does not expand geography and it does not claim surveyed lane geometry.

const CIVILIAN_VEHICLE_VISUAL := preload("res://game/scripts/civilian_vehicle_visual.gd")
const VEHICLE_AXIS_ID := "https://databrussels.be/id/streetaxe/71374:1"
const PEDESTRIAN_SURFACE_TYPE := "SW"
const DISABLE_ENV := "GB_IXELLES_LIFE"
const CIVILIAN_COUNT := 8
const MOVING_VEHICLE_COUNT := 2
const MAX_SIDEWALK_ANCHOR_DISTANCE_M := 140.0

var _slice: Node = null
var _axis := PackedVector2Array()
var _axis_length_m := 0.0
var _pedestrian_anchors: Array[Vector2] = []
var _pedestrian_source_ids: Array[String] = []
var _civilians: Array[Node3D] = []
var _moving: Array[Node3D] = []
var _vehicle_t: Array[float] = []
var _vehicle_speed_mps: Array[float] = []
var _all_pedestrian_anchors_inside_source := false
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
    if not _load_vehicle_axis():
        _stop("accepted official StreetAxis unavailable")
        return
    if not _load_pedestrian_anchors():
        _stop("insufficient official SW StreetSurface anchors")
        return
    _build_civilians()
    _build_moving_vehicles()
    if _civilians.size() != CIVILIAN_COUNT or _moving.size() != MOVING_VEHICLE_COUNT:
        _stop("life node counts incomplete")
        return
    _ready_complete = true
    set_process(true)
    print("IXELLES_LAB_LIFE_READY: civilians=%d moving=%d vehicle_axis=%s pedestrian_surface=%s geography_expanded=false lane_geometry_claimed=false" % [_civilians.size(), _moving.size(), VEHICLE_AXIS_ID, PEDESTRIAN_SURFACE_TYPE])

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
        "pedestrian_surface_type": PEDESTRIAN_SURFACE_TYPE,
        "pedestrian_anchor_count": _pedestrian_anchors.size(),
        "all_pedestrian_anchors_inside_source": _all_pedestrian_anchors_inside_source,
        "lane_geometry_claimed": false,
        "geography_expanded": false,
        "terrain_changed": false,
        "street_geometry_changed": false,
    }

func moving_probe_position() -> Vector3:
    if _moving.is_empty():
        return Vector3(NAN, NAN, NAN)
    return _moving[0].global_position

func _load_vehicle_axis() -> bool:
    var network: Dictionary = _slice.get_meta("ixelles_network_contract", {})
    var axes: Variant = network.get("street_axes", [])
    if not axes is Array:
        return false
    for raw: Variant in axes:
        if not raw is Dictionary or str((raw as Dictionary).get("id", "")) != VEHICLE_AXIS_ID:
            continue
        var points: Variant = (raw as Dictionary).get("points", [])
        if not points is Array or points.size() != 2:
            return false
        var result := PackedVector2Array()
        for point: Variant in points:
            if not point is Array or point.size() < 2:
                return false
            result.append(Vector2(float(point[0]), float(point[1])))
        if result.size() != 2:
            return false
        _axis = result
        _axis_length_m = _axis[0].distance_to(_axis[1])
        return _axis_length_m >= 8.0
    return false

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

func _source_interior_point(ring: PackedVector2Array) -> Vector2:
    var indices := Geometry2D.triangulate_polygon(ring)
    if indices.size() < 3:
        return Vector2(INF, INF)
    var best_area := -1.0
    var best_point := Vector2(INF, INF)
    for offset: int in range(0, indices.size(), 3):
        var a := ring[indices[offset]]
        var b := ring[indices[offset + 1]]
        var c := ring[indices[offset + 2]]
        var area := absf((b - a).cross(c - a)) * 0.5
        if area > best_area:
            best_area = area
            best_point = (a + b + c) / 3.0
    return best_point

func _load_pedestrian_anchors() -> bool:
    var cell: Dictionary = _slice.get_meta("ixelles_cell_contract", {})
    var surfaces: Variant = cell.get("street_surfaces", [])
    if not surfaces is Array:
        return false
    var axis_mid := (_axis[0] + _axis[1]) * 0.5
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
        var point := _source_interior_point(ring)
        if not is_finite(point.x) or not is_finite(point.y):
            continue
        if not Geometry2D.is_point_in_polygon(point, ring):
            continue
        var distance := point.distance_to(axis_mid)
        if distance > MAX_SIDEWALK_ANCHOR_DISTANCE_M:
            continue
        candidates.append({
            "point": point,
            "distance": distance,
            "source_id": str(feature.get("id", "")),
        })
    candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        var da := float(a.get("distance", 0.0))
        var db := float(b.get("distance", 0.0))
        if absf(da - db) <= 0.0001:
            return str(a.get("source_id", "")) < str(b.get("source_id", ""))
        return da < db
    )
    if candidates.size() < CIVILIAN_COUNT:
        return false
    _pedestrian_anchors.clear()
    _pedestrian_source_ids.clear()
    for i: int in range(CIVILIAN_COUNT):
        _pedestrian_anchors.append(candidates[i].get("point") as Vector2)
        _pedestrian_source_ids.append(str(candidates[i].get("source_id", "")))
    _all_pedestrian_anchors_inside_source = _verify_pedestrian_anchors_inside_source(surfaces)
    return _all_pedestrian_anchors_inside_source

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
        var toward_axis := ((_axis[0] + _axis[1]) * 0.5) - anchor
        if toward_axis.length_squared() > 0.001:
            person.rotation.y = atan2(-toward_axis.x, -toward_axis.y)
        _civilians.append(person)

func _build_moving_vehicles() -> void:
    var colors := [Color(0.08, 0.13, 0.20), Color(0.42, 0.40, 0.36)]
    var starts := [0.18, 0.72]
    var speeds := [4.2, -3.8]
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
