extends Node3D

## Immediate Atomium public-realm context from bounded official UrbIS Topo.
## Horizontal plan geometry and semantic TYPE are source-backed. Vertical/profile
## dimensions are presentation-only and deliberately carry no collision.

@export_file("*.json") var data_path := "res://data/sources/laeken_jette/atomium_topo_esplanade_context.json"

var context_built := false
var stair_feature_count := 0
var bench_feature_count := 0
var stair_segment_count := 0
var bench_polygon_count := 0
var surveyed_vertical_dimensions := false
var has_collision := false

var _terrain: Node
var _anchor := Vector3.ZERO
var _origin_e := 0.0
var _origin_n := 0.0
var _stair_width := 0.18
var _bench_height := 0.42


func build_on_terrain(terrain: Node, hero_anchor: Vector3) -> bool:
    if context_built:
        return true
    if terrain == null or not terrain.has_method("sample_height") or not bool(terrain.get("terrain_loaded")):
        push_error("AtomiumTopoEsplanadeContext: official terrain unavailable")
        return false
    if not FileAccess.file_exists(data_path):
        push_error("AtomiumTopoEsplanadeContext: locked source snapshot missing")
        return false
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(data_path))
    if typeof(parsed) != TYPE_DICTIONARY:
        push_error("AtomiumTopoEsplanadeContext: invalid source snapshot")
        return false
    var data := parsed as Dictionary
    var source: Dictionary = data.get("source", {})
    if str(source.get("crs", "")) != "EPSG:31370" or str(source.get("dataset", "")) != "UrbIS Topo":
        push_error("AtomiumTopoEsplanadeContext: source contract drifted")
        return false
    var presentation: Dictionary = data.get("presentation", {})
    if bool(presentation.get("runtime_approved", true)) or bool(presentation.get("surveyed_vertical_dimensions", true)):
        push_error("AtomiumTopoEsplanadeContext: presentation-only dimensions were promoted")
        return false
    surveyed_vertical_dimensions = false
    _stair_width = float(presentation.get("stair_line_width_authored_m", 0.18))
    _bench_height = float(presentation.get("bench_height_authored_m", 0.42))
    _terrain = terrain
    _anchor = hero_anchor
    _origin_e = float(terrain.get("origin_e"))
    _origin_n = float(terrain.get("origin_n"))

    var stair_surface := SurfaceTool.new()
    stair_surface.begin(Mesh.PRIMITIVE_TRIANGLES)
    var bench_surface := SurfaceTool.new()
    bench_surface.begin(Mesh.PRIMITIVE_TRIANGLES)
    var features: Variant = data.get("features", [])
    if not features is Array:
        return false
    for raw: Variant in features:
        if not raw is Dictionary:
            continue
        var feature := raw as Dictionary
        var topo_type := str(feature.get("topo_type", ""))
        var geometry: Dictionary = feature.get("geometry", {})
        var multi: Variant = geometry.get("coordinates", [])
        if str(geometry.get("type", "")) != "MultiLineString" or not multi is Array:
            continue
        for raw_line: Variant in multi:
            if not raw_line is Array or raw_line.size() < 2:
                continue
            var line := raw_line as Array
            if topo_type == "BB03L":
                _append_stair_line(stair_surface, line)
                stair_feature_count += 1
            elif topo_type == "CR39L":
                _append_bench_polygon(bench_surface, line)
                bench_feature_count += 1

    if stair_segment_count > 0:
        stair_surface.generate_normals()
        var stair_mesh := stair_surface.commit()
        var stair_instance := MeshInstance3D.new()
        stair_instance.name = "OfficialTopoStairs"
        stair_instance.mesh = stair_mesh
        var stair_material := StandardMaterial3D.new()
        stair_material.albedo_color = Color(0.58, 0.57, 0.53, 1.0)
        stair_material.roughness = 0.96
        stair_mesh.surface_set_material(0, stair_material)
        add_child(stair_instance)
    if bench_polygon_count > 0:
        bench_surface.generate_normals()
        var bench_mesh := bench_surface.commit()
        var bench_instance := MeshInstance3D.new()
        bench_instance.name = "OfficialTopoBenches"
        bench_instance.mesh = bench_mesh
        var bench_material := StandardMaterial3D.new()
        bench_material.albedo_color = Color(0.32, 0.31, 0.28, 1.0)
        bench_material.roughness = 0.91
        bench_mesh.surface_set_material(0, bench_material)
        add_child(bench_instance)

    context_built = stair_feature_count == 14 and bench_feature_count == 5 and stair_segment_count > 0 and bench_polygon_count == 5
    if context_built:
        print("ATOMIUM_TOPO_ESPLANADE_READY: stairs=%d stair_segments=%d benches=%d bench_polygons=%d authored_bench_height=%.2f collision=%s" % [stair_feature_count, stair_segment_count, bench_feature_count, bench_polygon_count, _bench_height, str(has_collision)])
    return context_built


func _source_to_local(pair: Variant, y_offset: float = 0.0) -> Vector3:
    if not pair is Array or pair.size() < 2:
        return Vector3.ZERO
    var game_x := float(pair[0]) - _origin_e
    var game_z := -(float(pair[1]) - _origin_n)
    var ground_y := float(_terrain.call("sample_height", game_x, game_z))
    return Vector3(game_x - _anchor.x, ground_y - _anchor.y + y_offset, game_z - _anchor.z)


func _append_stair_line(surface: SurfaceTool, line: Array) -> void:
    for i: int in range(line.size() - 1):
        var a := _source_to_local(line[i], 0.035)
        var b := _source_to_local(line[i + 1], 0.035)
        var flat := Vector3(b.x - a.x, 0.0, b.z - a.z)
        if flat.length() < 0.01:
            continue
        var side := Vector3(-flat.z, 0.0, flat.x).normalized() * (_stair_width * 0.5)
        surface.add_vertex(a - side)
        surface.add_vertex(b - side)
        surface.add_vertex(b + side)
        surface.add_vertex(a - side)
        surface.add_vertex(b + side)
        surface.add_vertex(a + side)
        stair_segment_count += 1


func _append_bench_polygon(surface: SurfaceTool, line: Array) -> void:
    var points := line.duplicate()
    if points.size() >= 2:
        var first: Variant = points[0]
        var last: Variant = points[points.size() - 1]
        if first is Array and last is Array and first.size() >= 2 and last.size() >= 2 and Vector2(float(first[0]), float(first[1])).distance_to(Vector2(float(last[0]), float(last[1]))) < 0.01:
            points.pop_back()
    if points.size() < 3:
        return
    var polygon := PackedVector2Array()
    var ground: Array[Vector3] = []
    for raw: Variant in points:
        var p := _source_to_local(raw)
        ground.append(p)
        polygon.append(Vector2(p.x, p.z))
    var triangles := Geometry2D.triangulate_polygon(polygon)
    if triangles.size() < 3:
        return
    for i: int in range(0, triangles.size(), 3):
        for j: int in range(3):
            var p := ground[triangles[i + j]]
            surface.add_vertex(Vector3(p.x, p.y + _bench_height, p.z))
    for i: int in range(ground.size()):
        var j := (i + 1) % ground.size()
        var a := ground[i]
        var b := ground[j]
        var at := Vector3(a.x, a.y + _bench_height, a.z)
        var bt := Vector3(b.x, b.y + _bench_height, b.z)
        surface.add_vertex(a)
        surface.add_vertex(b)
        surface.add_vertex(bt)
        surface.add_vertex(a)
        surface.add_vertex(bt)
        surface.add_vertex(at)
    bench_polygon_count += 1
