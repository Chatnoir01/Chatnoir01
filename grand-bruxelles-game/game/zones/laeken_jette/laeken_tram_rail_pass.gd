extends Node3D

## Geometry refinement for the authoritative UrbIS tram network.
## The centreline comes only from the committed UrbIS layer. The old 1 m-wide
## ribbon is hidden and replaced by two lightweight metallic rail heads at the
## standard 1.435 m gauge. Each rail samples the official DTM independently so
## crossfall/camber is preserved instead of forcing both rails to one elevation.

const DATA_PATH := "res://data/urbis/laeken_jette/tram_network.game.json"
const GAUGE_M := 1.435
const RAIL_HEAD_WIDTH_M := 0.075
const RAIL_HEAD_HEIGHT_M := 0.038
const RAIL_Y_OFFSET_M := 0.070
const MIN_SEGMENT_M := 0.22

var rail_ready: bool = false
var source_features: int = 0
var source_segments: int = 0
var rail_instances: int = 0
var old_ribbon_hidden: bool = false
var max_crossfall_delta_m: float = 0.0

var _rail_material: StandardMaterial3D


func _ready() -> void:
    call_deferred("_build")


func _make_material() -> void:
    _rail_material = StandardMaterial3D.new()
    _rail_material.albedo_color = Color(0.40, 0.43, 0.45, 1.0)
    _rail_material.metallic = 0.82
    _rail_material.roughness = 0.27


func _load_document() -> Dictionary:
    if not FileAccess.file_exists(DATA_PATH):
        return {}
    var file := FileAccess.open(DATA_PATH, FileAccess.READ)
    if file == null:
        return {}
    var value = JSON.parse_string(file.get_as_text())
    return value as Dictionary if typeof(value) == TYPE_DICTIONARY else {}


func _line_strings(geometry: Dictionary) -> Array:
    var result: Array = []
    var kind := str(geometry.get("type", ""))
    var coordinates = geometry.get("coordinates", [])
    if kind == "LineString" and coordinates is Array:
        result.append(coordinates)
    elif kind == "MultiLineString" and coordinates is Array:
        for line in coordinates:
            if line is Array:
                result.append(line)
    return result


func _rail_transform(midpoint: Vector2, y: float, yaw: float, length: float) -> Transform3D:
    var scale := Vector3(RAIL_HEAD_WIDTH_M, RAIL_HEAD_HEIGHT_M, length)
    return Transform3D(Basis(Vector3.UP, yaw).scaled(scale), Vector3(midpoint.x, y, midpoint.y))


func _build() -> void:
    _make_material()
    var terrain = get_parent().get_node_or_null("LaekenTerrain")
    if terrain == null or not bool(terrain.get("terrain_loaded")):
        push_warning("LaekenTramRailPass: terrain unavailable")
        return

    var document := _load_document()
    var features = document.get("features", [])
    if not features is Array or features.is_empty():
        push_warning("LaekenTramRailPass: UrbIS tram network unavailable")
        return
    source_features = features.size()

    var transforms: Array[Transform3D] = []
    for feature in features:
        if not feature is Dictionary:
            continue
        var geometry = feature.get("geometry", {})
        if not geometry is Dictionary:
            continue
        for line in _line_strings(geometry):
            if not line is Array or line.size() < 2:
                continue
            for index in range(line.size() - 1):
                var raw_a = line[index]
                var raw_b = line[index + 1]
                if not (raw_a is Array and raw_b is Array and raw_a.size() >= 2 and raw_b.size() >= 2):
                    continue
                var a := Vector2(float(raw_a[0]), float(raw_a[1]))
                var b := Vector2(float(raw_b[0]), float(raw_b[1]))
                var delta := b - a
                var length := delta.length()
                if length < MIN_SEGMENT_M:
                    continue
                var direction := delta / length
                var gauge_side := Vector2(-direction.y, direction.x) * (GAUGE_M * 0.5)
                var midpoint := (a + b) * 0.5
                var left_midpoint := midpoint + gauge_side
                var right_midpoint := midpoint - gauge_side
                if not bool(terrain.call("contains_game_point", left_midpoint.x, left_midpoint.y)):
                    continue
                if not bool(terrain.call("contains_game_point", right_midpoint.x, right_midpoint.y)):
                    continue

                var left_y := float(terrain.call("sample_height", left_midpoint.x, left_midpoint.y)) + RAIL_Y_OFFSET_M
                var right_y := float(terrain.call("sample_height", right_midpoint.x, right_midpoint.y)) + RAIL_Y_OFFSET_M
                max_crossfall_delta_m = maxf(max_crossfall_delta_m, absf(left_y - right_y))
                var yaw := atan2(direction.x, direction.y)
                transforms.append(_rail_transform(left_midpoint, left_y, yaw, length))
                transforms.append(_rail_transform(right_midpoint, right_y, yaw, length))
                source_segments += 1

    if transforms.is_empty():
        push_warning("LaekenTramRailPass: no terrain-grounded rail segments generated")
        return

    var mesh := BoxMesh.new()
    mesh.size = Vector3.ONE
    mesh.material = _rail_material
    var multimesh := MultiMesh.new()
    multimesh.transform_format = MultiMesh.TRANSFORM_3D
    multimesh.mesh = mesh
    multimesh.instance_count = transforms.size()
    for index in range(transforms.size()):
        multimesh.set_instance_transform(index, transforms[index])

    var rail_node := MultiMeshInstance3D.new()
    rail_node.name = "OfficialTwinTramRails"
    rail_node.multimesh = multimesh
    add_child(rail_node)
    rail_instances = transforms.size()

    var old_ribbon := get_parent().get_node_or_null("OfficialTramNetwork") as MeshInstance3D
    if old_ribbon != null:
        old_ribbon.visible = false
        old_ribbon_hidden = true

    rail_ready = source_segments > 0 and rail_instances == source_segments * 2 and old_ribbon_hidden
    print("LAEKEN_TRAM_RAILS_READY: features=%d segments=%d rails=%d gauge=%.3f old_ribbon_hidden=%s max_crossfall_delta=%.3f" % [
        source_features,
        source_segments,
        rail_instances,
        GAUGE_M,
        old_ribbon_hidden,
        max_crossfall_delta_m,
    ])
