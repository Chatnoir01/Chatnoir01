extends Node3D

## Atomium approach street-furniture pass.
##
## The corridor direction comes from the nearest official UrbIS StreetAxes
## segment. Synthetic trees and lane dashes are intentionally disabled now that
## authoritative City tree positions and the official orthophoto are part of the
## runtime. Lamps remain provisional until a sourced lighting inventory is added.

const DATA_PATH := "res://data/urbis/laeken_jette/street_axes.game.json"
const ATOMIUM := Vector2(224.92615906274295, -6553.143077999353)
const HALF_LENGTH_M := 260.0
const MAX_RADIUS_M := 340.0

var official_axis_distance_m: float = INF
var official_axis_origin: Vector2 = Vector2.ZERO
var official_axis_direction: Vector2 = Vector2.UP
var generated_trees: int = 0
var generated_lamps: int = 0
var generated_dashes: int = 0

var _lamp_metal: StandardMaterial3D
var _lamp_head: StandardMaterial3D


func _ready() -> void:
    call_deferred("_build")


func _build() -> void:
    _make_materials()
    if not _resolve_official_axis():
        push_warning("Atomium corridor: no official UrbIS StreetAxes segment found")
        return
    _build_lamps_only()
    print("LAEKEN_ATOMIUM_CORRIDOR_READY: axis_distance=%.2f trees=%d lamps=%d dashes=%d" % [
        official_axis_distance_m,
        generated_trees,
        generated_lamps,
        generated_dashes,
    ])


func _make_materials() -> void:
    _lamp_metal = _material(Color(0.14, 0.15, 0.16, 1.0), 0.34, 0.72)
    _lamp_head = _material(Color(0.91, 0.88, 0.74, 1.0), 0.28, 0.05)


func _material(color: Color, roughness: float, metallic: float = 0.0) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = roughness
    material.metallic = metallic
    return material


func _terrain_y(xz: Vector2) -> float:
    var terrain := get_parent().get_node_or_null("LaekenTerrain")
    if terrain != null and terrain.has_method("sample_height"):
        return float(terrain.call("sample_height", xz.x, xz.y))
    return 0.0


func _load_data() -> Dictionary:
    if not FileAccess.file_exists(DATA_PATH):
        return {}
    var file := FileAccess.open(DATA_PATH, FileAccess.READ)
    if file == null:
        return {}
    var parsed = JSON.parse_string(file.get_as_text())
    return parsed as Dictionary if typeof(parsed) == TYPE_DICTIONARY else {}


func _line_strings(geometry: Dictionary) -> Array:
    var result: Array = []
    var kind := String(geometry.get("type", ""))
    var coordinates = geometry.get("coordinates", [])
    if kind == "LineString" and coordinates is Array:
        result.append(coordinates)
    elif kind == "MultiLineString" and coordinates is Array:
        for line in coordinates:
            if line is Array:
                result.append(line)
    return result


func _closest_on_segment(point: Vector2, a: Vector2, b: Vector2) -> Vector2:
    var delta := b - a
    var denominator := delta.length_squared()
    if denominator < 0.000001:
        return a
    var t := clampf((point - a).dot(delta) / denominator, 0.0, 1.0)
    return a + delta * t


func _resolve_official_axis() -> bool:
    var data := _load_data()
    var features = data.get("features", [])
    if not (features is Array):
        return false

    for feature in features:
        if not (feature is Dictionary):
            continue
        var geometry = feature.get("geometry", {})
        if not (geometry is Dictionary):
            continue
        for line in _line_strings(geometry):
            if not (line is Array) or line.size() < 2:
                continue
            for index in range(line.size() - 1):
                var raw_a = line[index]
                var raw_b = line[index + 1]
                if not (raw_a is Array and raw_b is Array and raw_a.size() >= 2 and raw_b.size() >= 2):
                    continue
                var a := Vector2(float(raw_a[0]), float(raw_a[1]))
                var b := Vector2(float(raw_b[0]), float(raw_b[1]))
                var delta := b - a
                if delta.length_squared() < 0.01:
                    continue
                var closest := _closest_on_segment(ATOMIUM, a, b)
                var distance := closest.distance_to(ATOMIUM)
                if distance < official_axis_distance_m:
                    official_axis_distance_m = distance
                    official_axis_origin = closest
                    official_axis_direction = delta.normalized()
    return official_axis_distance_m < INF


func _build_lamps_only() -> void:
    var start := official_axis_origin - official_axis_direction * HALF_LENGTH_M
    var side := Vector2(-official_axis_direction.y, official_axis_direction.x)
    var distance := 12.0
    while distance < HALF_LENGTH_M * 2.0:
        var centre_lamp := start + official_axis_direction * distance
        if centre_lamp.distance_to(ATOMIUM) <= MAX_RADIUS_M and centre_lamp.distance_to(ATOMIUM) >= 28.0:
            for side_sign in [-1.0, 1.0]:
                var lamp_pos: Vector2 = centre_lamp + side * 8.7 * float(side_sign)
                _add_lamp(lamp_pos)
                generated_lamps += 1
        distance += 32.0


func _add_lamp(xz: Vector2) -> void:
    var lamp := Node3D.new()
    lamp.name = "ProvisionalAxisLamp"
    lamp.position = Vector3(xz.x, _terrain_y(xz), xz.y)
    add_child(lamp)

    var pole := CylinderMesh.new()
    pole.top_radius = 0.075
    pole.bottom_radius = 0.105
    pole.height = 7.4
    pole.radial_segments = 8
    pole.material = _lamp_metal
    var pole_instance := MeshInstance3D.new()
    pole_instance.mesh = pole
    pole_instance.position.y = 3.7
    lamp.add_child(pole_instance)

    var head := BoxMesh.new()
    head.size = Vector3(0.30, 0.14, 0.78)
    head.material = _lamp_head
    var head_instance := MeshInstance3D.new()
    head_instance.mesh = head
    head_instance.position.y = 7.32
    lamp.add_child(head_instance)
