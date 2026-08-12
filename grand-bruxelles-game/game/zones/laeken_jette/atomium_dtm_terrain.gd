extends Node3D

## Bounded official UrbIS DTM runtime component for the Atomium 1 km evidence tile.
## EPSG:31370 X/Z remain project-local metres. Y is elevation relative to the
## sampled Atomium ground reference. Invalid UrbIS samples remain holes.

@export_file("*.json") var data_path: String = "res://data/terrain/laeken_jette/atomium_dtm.game.json"
@export var build_collision: bool = true

const LEGACY_NODATA_THRESHOLD := -1.0e20

var terrain_loaded := false
var width := 0
var height := 0
var first_e := 0.0
var first_n := 0.0
var step_e := 0.0
var step_n := 0.0
var origin_e := 0.0
var origin_n := 0.0
var heights := PackedFloat32Array()
var valid_mask := PackedByteArray()
var valid_sample_count := 0
var invalid_sample_count := 0
var triangle_count := 0
var atomium_game_position := Vector3.ZERO
var atomium_absolute_elevation_m := 0.0


func _ready() -> void:
    if not _load_runtime():
        push_error("AtomiumDTMTerrain: official DTM runtime unavailable")
        return
    _build_mesh()
    if build_collision:
        _build_collision()
    terrain_loaded = triangle_count > 0
    if terrain_loaded:
        print("ATOMIUM_DTM_RUNTIME_READY: %dx%d valid=%d holes=%d triangles=%d atomium=(%.3f, %.3f, %.3f)" % [width, height, valid_sample_count, invalid_sample_count, triangle_count, atomium_game_position.x, atomium_game_position.y, atomium_game_position.z])


func _load_runtime() -> bool:
    if not FileAccess.file_exists(data_path):
        return false
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(data_path))
    if typeof(parsed) != TYPE_DICTIONARY:
        return false
    var data := parsed as Dictionary
    if int(data.get("schema", 0)) != 2 or str(data.get("format", "")) != "grand-bruxelles-dtm-grid-v2":
        push_error("AtomiumDTMTerrain: unsupported DTM schema")
        return false
    if str(data.get("source_crs", "")) != "EPSG:31370":
        push_error("AtomiumDTMTerrain: terrain CRS is not EPSG:31370")
        return false

    width = int(data.get("width", 0))
    height = int(data.get("height", 0))
    first_e = float(data.get("first_sample_e", 0.0))
    first_n = float(data.get("first_sample_n", 0.0))
    step_e = float(data.get("step_e", 0.0))
    step_n = float(data.get("step_n", 0.0))
    origin_e = float(data.get("game_origin_e", 0.0))
    origin_n = float(data.get("game_origin_n", 0.0))
    if width < 2 or height < 2 or is_zero_approx(step_e) or is_zero_approx(step_n):
        push_error("AtomiumDTMTerrain: invalid grid dimensions or spacing")
        return false

    var raw_heights: Variant = data.get("relative_heights_m", [])
    var raw_mask: Variant = data.get("valid_mask", [])
    if not raw_heights is Array or raw_heights.size() != width * height:
        push_error("AtomiumDTMTerrain: invalid height payload")
        return false
    if raw_mask is Array and raw_mask.size() != raw_heights.size():
        push_error("AtomiumDTMTerrain: invalid validity mask")
        return false

    heights.resize(raw_heights.size())
    valid_mask.resize(raw_heights.size())
    for i: int in range(raw_heights.size()):
        var value := float(raw_heights[i])
        var valid := value > LEGACY_NODATA_THRESHOLD
        if raw_mask is Array:
            valid = int(raw_mask[i]) != 0
        heights[i] = value if valid else 0.0
        valid_mask[i] = 1 if valid else 0
        if valid:
            valid_sample_count += 1
        else:
            invalid_sample_count += 1

    if valid_sample_count != int(data.get("valid_sample_count", -1)) or invalid_sample_count != int(data.get("invalid_sample_count", -1)):
        push_error("AtomiumDTMTerrain: sample counts drifted from locked evidence")
        return false

    var atomium: Variant = data.get("atomium_reference", {})
    if not atomium is Dictionary:
        return false
    var atomium_e := float(atomium.get("e", 0.0))
    var atomium_n := float(atomium.get("n", 0.0))
    atomium_absolute_elevation_m = float(atomium.get("absolute_elevation_m", 0.0))
    atomium_game_position = Vector3(atomium_e - origin_e, 0.0, -(atomium_n - origin_n))
    atomium_game_position.y = sample_height(atomium_game_position.x, atomium_game_position.z)
    return true


func _index(row: int, col: int) -> int:
    return row * width + col

func _valid(row: int, col: int) -> bool:
    if row < 0 or col < 0 or row >= height or col >= width:
        return false
    return valid_mask[_index(row, col)] != 0

func _height(row: int, col: int) -> float:
    return heights[_index(row, col)]

func _game_x(col: int) -> float:
    return first_e + float(col) * step_e - origin_e

func _game_z(row: int) -> float:
    return -(first_n + float(row) * step_n - origin_n)

func _neighbor_height(row: int, col: int, fallback: float) -> float:
    return _height(row, col) if _valid(row, col) else fallback

func _normal(row: int, col: int) -> Vector3:
    if not _valid(row, col):
        return Vector3.UP
    var centre := _height(row, col)
    var left := _neighbor_height(row, maxi(col - 1, 0), centre)
    var right := _neighbor_height(row, mini(col + 1, width - 1), centre)
    var up := _neighbor_height(maxi(row - 1, 0), col, centre)
    var down := _neighbor_height(mini(row + 1, height - 1), col, centre)
    var dhdx := (right - left) / (2.0 * maxf(absf(step_e), 0.001))
    var dhdz := (down - up) / (2.0 * maxf(absf(step_n), 0.001))
    return Vector3(-dhdx, 1.0, -dhdz).normalized()


func _build_mesh() -> void:
    var vertices := PackedVector3Array()
    var normals := PackedVector3Array()
    vertices.resize(width * height)
    normals.resize(width * height)
    for row: int in range(height):
        for col: int in range(width):
            var index := _index(row, col)
            vertices[index] = Vector3(_game_x(col), _height(row, col), _game_z(row))
            normals[index] = _normal(row, col)

    var indices := PackedInt32Array()
    for row: int in range(height - 1):
        for col: int in range(width - 1):
            var i0 := _index(row, col)
            var i1 := _index(row + 1, col)
            var i2 := _index(row, col + 1)
            var i3 := _index(row + 1, col + 1)
            if _valid(row, col) and _valid(row + 1, col) and _valid(row, col + 1):
                indices.append_array(PackedInt32Array([i0, i1, i2]))
            if _valid(row, col + 1) and _valid(row + 1, col) and _valid(row + 1, col + 1):
                indices.append_array(PackedInt32Array([i2, i1, i3]))
    triangle_count = indices.size() / 3
    if triangle_count <= 0:
        return

    var arrays: Array = []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = vertices
    arrays[Mesh.ARRAY_NORMAL] = normals
    arrays[Mesh.ARRAY_INDEX] = indices
    var mesh := ArrayMesh.new()
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    var material := StandardMaterial3D.new()
    material.albedo_color = Color(0.20, 0.31, 0.14, 1.0)
    material.roughness = 0.96
    mesh.surface_set_material(0, material)
    var instance := MeshInstance3D.new()
    instance.name = "OfficialAtomiumDTMMesh"
    instance.mesh = mesh
    add_child(instance)


func _build_collision() -> void:
    var collision_heights := PackedFloat32Array()
    collision_heights.resize(heights.size())
    for i: int in range(heights.size()):
        collision_heights[i] = heights[i] if valid_mask[i] != 0 else NAN
    var shape := HeightMapShape3D.new()
    shape.map_width = width
    shape.map_depth = height
    shape.map_data = collision_heights
    var collision := CollisionShape3D.new()
    collision.name = "OfficialAtomiumDTMHeightMapCollision"
    collision.shape = shape
    collision.scale = Vector3(absf(step_e), 1.0, absf(step_n))
    collision.position = Vector3((_game_x(0) + _game_x(width - 1)) * 0.5, 0.0, (_game_z(0) + _game_z(height - 1)) * 0.5)
    var body := StaticBody3D.new()
    body.name = "OfficialAtomiumDTMCollision"
    body.add_child(collision)
    add_child(body)


func contains_game_point(game_x: float, game_z: float) -> bool:
    var col_f := (game_x + origin_e - first_e) / step_e
    var row_f := (origin_n - game_z - first_n) / step_n
    if col_f < 0.0 or row_f < 0.0 or col_f > float(width - 1) or row_f > float(height - 1):
        return false
    return _valid(clampi(int(round(row_f)), 0, height - 1), clampi(int(round(col_f)), 0, width - 1))


func sample_height(game_x: float, game_z: float) -> float:
    if width < 2 or height < 2:
        return 0.0
    var col_f := (game_x + origin_e - first_e) / step_e
    var row_f := (origin_n - game_z - first_n) / step_n
    if col_f < 0.0 or row_f < 0.0 or col_f > float(width - 1) or row_f > float(height - 1):
        return 0.0
    var c0 := clampi(int(floor(col_f)), 0, width - 1)
    var r0 := clampi(int(floor(row_f)), 0, height - 1)
    var c1 := mini(c0 + 1, width - 1)
    var r1 := mini(r0 + 1, height - 1)
    var tx := col_f - float(c0)
    var tz := row_f - float(r0)
    var samples := [[r0, c0, (1.0 - tx) * (1.0 - tz)], [r0, c1, tx * (1.0 - tz)], [r1, c0, (1.0 - tx) * tz], [r1, c1, tx * tz]]
    var weighted := 0.0
    var total_weight := 0.0
    for sample: Array in samples:
        var row := int(sample[0])
        var col := int(sample[1])
        var weight := float(sample[2])
        if _valid(row, col) and weight > 0.0:
            weighted += _height(row, col) * weight
            total_weight += weight
    return weighted / total_weight if total_weight > 0.000001 else 0.0
