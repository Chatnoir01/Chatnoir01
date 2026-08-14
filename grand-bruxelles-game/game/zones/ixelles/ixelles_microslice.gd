extends Node3D

## First bounded Ixelles runtime micro-slice.
## Terrain, collision, streets and selected building massing are source-backed.
## Legacy temporary building-height heuristics are never rendered.

@export_file("*.json") var terrain_path := "res://data/terrain/ixelles/bxl-e149000-n169000-s500_dtm_2m.game.json"
@export_file("*.json") var height_candidates_path := "res://data/terrain/ixelles/bxl-e149000-n169000-s500_strong_heights.game.json"
@export_file("*.json") var cell_path := "res://data/urbis/remaining_brussels/cells/bxl-e149000-n169000-s500/runtime/cell.game.json"
@export_file("*.json") var network_path := "res://data/urbis/remaining_brussels/cells/bxl-e149000-n169000-s500/runtime/network.game.json"
@export var build_collision := true

var runtime_loaded := false
var cell_id := ""
var terrain_sample_count := 0
var terrain_triangle_count := 0
var street_surface_count := 0
var street_segment_count := 0
var building_count := 0
var eligible_height_count := 0
var skipped_unapproved_height_buildings := 0
var vertical_reference_absolute_m := 0.0

var _width := 0
var _height := 0
var _spacing := 0.0
var _bbox := Rect2()
var _heights_relative := PackedFloat32Array()
var _origin_e := 0.0
var _origin_n := 0.0
var _world_anchor_x := 0.0
var _world_anchor_z := 0.0

var _terrain_material: StandardMaterial3D
var _road_material: StandardMaterial3D
var _sidewalk_material: StandardMaterial3D
var _paved_material: StandardMaterial3D
var _other_material: StandardMaterial3D
var _building_materials: Array[StandardMaterial3D] = []

func _ready() -> void:
    if not _load_contracts():
        push_error("IxellesMicroSlice: runtime contracts unavailable")
        return
    _make_materials()
    _build_terrain()
    if build_collision:
        _build_collision()
    _build_street_surfaces()
    _build_strong_height_candidate_buildings()
    runtime_loaded = terrain_triangle_count == 125000 and street_surface_count == 309 and street_segment_count == 277 and building_count == eligible_height_count and building_count == 260 and skipped_unapproved_height_buildings == 460
    if runtime_loaded:
        print("IXELLES_MICROSLICE_READY: cell=%s samples=%d triangles=%d streets=%d buildings=%d skipped_heights=%d" % [cell_id, terrain_sample_count, terrain_triangle_count, street_surface_count, building_count, skipped_unapproved_height_buildings])

func _read_json(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        push_error("IxellesMicroSlice: missing %s" % path)
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    if typeof(parsed) != TYPE_DICTIONARY:
        push_error("IxellesMicroSlice: invalid JSON %s" % path)
        return {}
    return parsed as Dictionary

func _load_contracts() -> bool:
    var terrain := _read_json(terrain_path)
    var height_candidates := _read_json(height_candidates_path)
    var cell := _read_json(cell_path)
    var network := _read_json(network_path)
    if terrain.is_empty() or height_candidates.is_empty() or cell.is_empty() or network.is_empty():
        return false
    cell_id = str(terrain.get("cell_id", ""))
    if cell_id != "bxl-e149000-n169000-s500" or str(cell.get("cell_id", "")) != cell_id or str(network.get("cell_id", "")) != cell_id or str(height_candidates.get("cell_id", "")) != cell_id:
        push_error("IxellesMicroSlice: selected cell contract drifted")
        return false
    var bbox_raw: Variant = terrain.get("bbox_epsg31370", [])
    if not bbox_raw is Array or bbox_raw.size() != 4:
        return false
    if absf(float(bbox_raw[0]) - 149000.0) > 0.001 or absf(float(bbox_raw[1]) - 169000.0) > 0.001 or absf(float(bbox_raw[2]) - 149500.0) > 0.001 or absf(float(bbox_raw[3]) - 169500.0) > 0.001:
        push_error("IxellesMicroSlice: bbox drifted")
        return false
    _bbox = Rect2(float(bbox_raw[0]), float(bbox_raw[1]), float(bbox_raw[2]) - float(bbox_raw[0]), float(bbox_raw[3]) - float(bbox_raw[1]))
    _spacing = float(terrain.get("spacing_m", 0.0))
    var shape: Variant = terrain.get("shape", [])
    if not shape is Array or shape.size() != 2:
        return false
    _height = int(shape[0])
    _width = int(shape[1])
    terrain_sample_count = int(terrain.get("sample_count", 0))
    if _width != 251 or _height != 251 or absf(_spacing - 2.0) > 0.0001 or terrain_sample_count != 63001:
        push_error("IxellesMicroSlice: 2 m terrain topology drifted")
        return false
    var source: Variant = terrain.get("source", {})
    if not source is Dictionary or str(source.get("crs", "")) != "EPSG:31370":
        push_error("IxellesMicroSlice: terrain CRS drifted")
        return false
    if bool(terrain.get("runtime_approved", true)) or bool(terrain.get("promote_runtime", true)):
        push_error("IxellesMicroSlice: provisional terrain incorrectly marked approved")
        return false
    var raw_heights: Variant = terrain.get("heights_row_major_m", [])
    if not raw_heights is Array or raw_heights.size() != terrain_sample_count:
        return false
    _heights_relative.resize(terrain_sample_count)
    vertical_reference_absolute_m = float(raw_heights[0])
    for i: int in range(terrain_sample_count):
        var value := float(raw_heights[i])
        if not is_finite(value):
            push_error("IxellesMicroSlice: non-finite terrain sample")
            return false
        _heights_relative[i] = value - vertical_reference_absolute_m
    if bool(height_candidates.get("runtime_approved", true)):
        push_error("IxellesMicroSlice: strong-height evidence incorrectly globally approved")
        return false
    eligible_height_count = int(height_candidates.get("eligible_count", 0))
    if eligible_height_count != 260:
        push_error("IxellesMicroSlice: strong-height candidate count drifted")
        return false
    var policy: Variant = height_candidates.get("policy", {})
    if not policy is Dictionary or int(policy.get("source_pr", 0)) != 103 or float(policy.get("max_abs_delta_m", 99.0)) != 2.0 or str(policy.get("required_dsm_confidence", "")) != "high":
        push_error("IxellesMicroSlice: height evidence policy drifted")
        return false
    var coords: Variant = cell.get("coordinate_system", {})
    if not coords is Dictionary or not bool(coords.get("coordinates_are_current_game_world", false)):
        push_error("IxellesMicroSlice: current-game-world coordinate contract missing")
        return false
    _origin_e = float(coords.get("lambert_origin_e", 0.0))
    _origin_n = float(coords.get("lambert_origin_n", 0.0))
    _world_anchor_x = float(coords.get("world_anchor_x", 0.0))
    _world_anchor_z = float(coords.get("world_anchor_z", 0.0))
    set_meta("ixelles_cell_contract", cell)
    set_meta("ixelles_network_contract", network)
    set_meta("ixelles_height_contract", height_candidates)
    return true

func _make_material(color: Color, roughness: float) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = roughness
    material.cull_mode = BaseMaterial3D.CULL_DISABLED
    return material

func _make_materials() -> void:
    _terrain_material = _make_material(Color(0.17, 0.25, 0.13, 1.0), 0.98)
    _road_material = _make_material(Color(0.075, 0.078, 0.082, 1.0), 0.97)
    _sidewalk_material = _make_material(Color(0.45, 0.435, 0.405, 1.0), 0.94)
    _paved_material = _make_material(Color(0.39, 0.375, 0.345, 1.0), 0.95)
    _other_material = _make_material(Color(0.28, 0.285, 0.28, 1.0), 0.95)
    _building_materials = [_make_material(Color(0.49, 0.34, 0.27, 1.0), 0.92), _make_material(Color(0.62, 0.56, 0.46, 1.0), 0.91), _make_material(Color(0.45, 0.44, 0.41, 1.0), 0.93)]

func _index(row: int, col: int) -> int:
    return row * _width + col

func lambert_to_game(e: float, n: float) -> Vector3:
    return Vector3(_world_anchor_x + (e - _origin_e), 0.0, _world_anchor_z - (n - _origin_n))

func _grid_game_position(row: int, col: int) -> Vector3:
    var e := _bbox.position.x + float(col) * _spacing
    var n := _bbox.position.y + float(row) * _spacing
    var p := lambert_to_game(e, n)
    p.y = _heights_relative[_index(row, col)]
    return p

func _normal(row: int, col: int) -> Vector3:
    var left := _heights_relative[_index(row, maxi(col - 1, 0))]
    var right := _heights_relative[_index(row, mini(col + 1, _width - 1))]
    var south := _heights_relative[_index(maxi(row - 1, 0), col)]
    var north := _heights_relative[_index(mini(row + 1, _height - 1), col)]
    var dhdx := (right - left) / (2.0 * _spacing)
    var dhdz := -(north - south) / (2.0 * _spacing)
    return Vector3(-dhdx, 1.0, -dhdz).normalized()

func _build_terrain() -> void:
    var vertices := PackedVector3Array()
    var normals := PackedVector3Array()
    vertices.resize(terrain_sample_count)
    normals.resize(terrain_sample_count)
    for row: int in range(_height):
        for col: int in range(_width):
            var i := _index(row, col)
            vertices[i] = _grid_game_position(row, col)
            normals[i] = _normal(row, col)
    var indices := PackedInt32Array()
    indices.resize((_width - 1) * (_height - 1) * 6)
    var cursor := 0
    for row: int in range(_height - 1):
        for col: int in range(_width - 1):
            var i0 := _index(row, col)
            var i1 := _index(row + 1, col)
            var i2 := _index(row, col + 1)
            var i3 := _index(row + 1, col + 1)
            indices[cursor] = i0; indices[cursor + 1] = i1; indices[cursor + 2] = i2
            indices[cursor + 3] = i2; indices[cursor + 4] = i1; indices[cursor + 5] = i3
            cursor += 6
    terrain_triangle_count = indices.size() / 3
    var arrays: Array = []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = vertices
    arrays[Mesh.ARRAY_NORMAL] = normals
    arrays[Mesh.ARRAY_INDEX] = indices
    var mesh := ArrayMesh.new()
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    mesh.surface_set_material(0, _terrain_material)
    var instance := MeshInstance3D.new()
    instance.name = "OfficialIxellesDTMMesh"
    instance.mesh = mesh
    add_child(instance)

func _build_collision() -> void:
    var shape := HeightMapShape3D.new()
    shape.map_width = _width
    shape.map_depth = _height
    shape.map_data = _heights_relative
    var collision := CollisionShape3D.new()
    collision.name = "OfficialIxellesDTMHeightMapCollision"
    collision.shape = shape
    collision.scale = Vector3(_spacing, 1.0, _spacing)
    var sw := lambert_to_game(_bbox.position.x, _bbox.position.y)
    var ne := lambert_to_game(_bbox.end.x, _bbox.end.y)
    collision.position = Vector3((sw.x + ne.x) * 0.5, 0.0, (sw.z + ne.z) * 0.5)
    var body := StaticBody3D.new()
    body.name = "OfficialIxellesDTMCollision"
    body.add_child(collision)
    add_child(body)

func sample_height(game_x: float, game_z: float) -> float:
    var e := _origin_e + (game_x - _world_anchor_x)
    var n := _origin_n - (game_z - _world_anchor_z)
    var col_f := (e - _bbox.position.x) / _spacing
    var row_f := (n - _bbox.position.y) / _spacing
    if col_f < 0.0 or row_f < 0.0 or col_f > float(_width - 1) or row_f > float(_height - 1): return 0.0
    var c0 := clampi(int(floor(col_f)), 0, _width - 1); var r0 := clampi(int(floor(row_f)), 0, _height - 1)
    var c1 := mini(c0 + 1, _width - 1); var r1 := mini(r0 + 1, _height - 1)
    var tx := col_f - float(c0); var ty := row_f - float(r0)
    return lerpf(lerpf(_heights_relative[_index(r0,c0)], _heights_relative[_index(r0,c1)], tx), lerpf(_heights_relative[_index(r1,c0)], _heights_relative[_index(r1,c1)], tx), ty)

func _ring(raw: Variant) -> PackedVector2Array:
    var ring := PackedVector2Array()
    if not raw is Array: return ring
    for item: Variant in raw:
        if item is Array and item.size() >= 2: ring.append(Vector2(float(item[0]), float(item[1])))
    if ring.size() >= 2 and ring[0].is_equal_approx(ring[ring.size()-1]): ring.remove_at(ring.size()-1)
    return ring

func _surface_material(surface_type: String) -> StandardMaterial3D:
    if surface_type == "S": return _road_material
    if surface_type == "SW": return _sidewalk_material
    if surface_type == "P" or surface_type == "I": return _paved_material
    return _other_material

func _build_street_surfaces() -> void:
    var cell: Dictionary = get_meta("ixelles_cell_contract", {})
    var surfaces: Variant = cell.get("street_surfaces", [])
    if not surfaces is Array: return
    var grouped := {}
    for feature: Variant in surfaces:
        if not feature is Dictionary: continue
        var ring := _ring(feature.get("polygon", [])); if ring.size() < 3: continue
        var indices := Geometry2D.triangulate_polygon(ring); if indices.size() < 3: continue
        var key := str(feature.get("type", ""))
        if not grouped.has(key):
            var tool := SurfaceTool.new(); tool.begin(Mesh.PRIMITIVE_TRIANGLES); tool.set_material(_surface_material(key)); grouped[key] = tool
        var target: SurfaceTool = grouped[key]
        for raw_index: int in indices:
            var p := ring[raw_index]; target.set_normal(Vector3.UP); target.add_vertex(Vector3(p.x, sample_height(p.x,p.y)+0.035, p.y))
        street_surface_count += 1
    var root := Node3D.new(); root.name = "OfficialIxellesStreetSurfaces"; add_child(root)
    for key: Variant in grouped.keys():
        var mesh: ArrayMesh = (grouped[key] as SurfaceTool).commit()
        if mesh.get_surface_count() == 0: continue
        var instance := MeshInstance3D.new(); instance.name = "StreetSurfaces_%s" % str(key); instance.mesh = mesh; root.add_child(instance)
    var network: Dictionary = get_meta("ixelles_network_contract", {})
    var stats: Variant = network.get("stats", {})
    if stats is Dictionary: street_segment_count = int(stats.get("street_segments", 0))

func _building_bucket(id_text: String) -> int:
    var hash_value := 0
    for character: int in id_text.to_utf8_buffer(): hash_value = (hash_value * 31 + character) & 0x7fffffff
    return hash_value % _building_materials.size()

func _append_building(tool: SurfaceTool, polygon: PackedVector2Array, semantic_height: float) -> bool:
    if polygon.size() < 3 or semantic_height < 2.0 or semantic_height > 100.0: return false
    var centroid := Vector2.ZERO
    for point: Vector2 in polygon: centroid += point
    centroid /= float(polygon.size())
    var base_y := sample_height(centroid.x, centroid.y) + 0.05
    var top_y := base_y + semantic_height
    for index: int in range(polygon.size()):
        var a := polygon[index]; var b := polygon[(index+1)%polygon.size()]; var edge := b-a
        if edge.length_squared() < 0.01: continue
        var normal := Vector3(-edge.y,0.0,edge.x).normalized()
        var a0:=Vector3(a.x,base_y,a.y); var b0:=Vector3(b.x,base_y,b.y); var a1:=Vector3(a.x,top_y,a.y); var b1:=Vector3(b.x,top_y,b.y)
        for vertex: Vector3 in [a0,b0,b1,a0,b1,a1]: tool.set_normal(normal); tool.add_vertex(vertex)
    for raw_index: int in Geometry2D.triangulate_polygon(polygon): tool.set_normal(Vector3.UP); tool.add_vertex(Vector3(polygon[raw_index].x,top_y,polygon[raw_index].y))
    return true

func _build_strong_height_candidate_buildings() -> void:
    var contract: Dictionary = get_meta("ixelles_height_contract", {})
    var heights := {}
    var records: Variant = contract.get("records", [])
    if records is Array:
        for record: Variant in records:
            if not record is Dictionary: continue
            if not bool(record.get("visual_runtime_eligible",false)) or bool(record.get("runtime_approved",true)): continue
            if float(record.get("abs_delta_m",99.0))>2.0 or float(record.get("semantic_match_score",0.0))<0.90 or float(record.get("semantic_match_margin",0.0))<0.25: continue
            heights[str(record.get("building_id",""))] = float(record.get("semantic_height_m",0.0))
    if heights.size() != eligible_height_count: push_error("IxellesMicroSlice: eligible height map incomplete"); return
    var tools: Array[SurfaceTool] = []
    for material: StandardMaterial3D in _building_materials:
        var tool := SurfaceTool.new(); tool.begin(Mesh.PRIMITIVE_TRIANGLES); tool.set_material(material); tools.append(tool)
    var cell: Dictionary = get_meta("ixelles_cell_contract", {})
    var buildings: Variant = cell.get("buildings", [])
    if not buildings is Array: return
    for feature: Variant in buildings:
        if not feature is Dictionary: continue
        var id_text := str(feature.get("id",""))
        if not heights.has(id_text): skipped_unapproved_height_buildings += 1; continue
        var polygon := _ring(feature.get("footprint",[])); var h := float(heights[id_text]); var bucket := _building_bucket(id_text)
        if _append_building(tools[bucket],polygon,h): building_count += 1
        else: skipped_unapproved_height_buildings += 1
    var root := Node3D.new(); root.name="StrongSourceBackedIxellesBuildings"; add_child(root)
    for index: int in range(tools.size()):
        var mesh: ArrayMesh = tools[index].commit()
        if mesh.get_surface_count()==0: continue
        var instance:=MeshInstance3D.new(); instance.name="StrongBuildings_%d"%index; instance.mesh=mesh; root.add_child(instance)