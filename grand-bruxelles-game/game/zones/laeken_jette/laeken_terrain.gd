extends Node3D

## Official UrbIS DTM terrain for Laeken phase 1.
## Prefer the full Bockstael/Parc de Laeken/Heysel mosaic when available and
## keep the validated Atomium 1 km tile only as a safe fallback.
## X/Z remain project-local Lambert72 metres. Y is official elevation relative
## to the sampled Atomium terrain level. UrbIS NoData cells remain holes.

const PRIMARY_DATA_PATH := "res://data/terrain/laeken_jette/phase1_dtm.game.json"
const FALLBACK_DATA_PATH := "res://data/terrain/laeken_jette/atomium_dtm.game.json"
const LEGACY_NODATA_THRESHOLD := -1.0e20

var terrain_loaded: bool = false
var data_path_used: String = ""
var width: int = 0
var height: int = 0
var first_e: float = 0.0
var first_n: float = 0.0
var step_e: float = 0.0
var step_n: float = 0.0
var origin_e: float = 0.0
var origin_n: float = 0.0
var heights: PackedFloat32Array = PackedFloat32Array()
var valid_mask: PackedByteArray = PackedByteArray()
var valid_sample_count: int = 0
var invalid_sample_count: int = 0
var min_height_m: float = 0.0
var max_height_m: float = 0.0
var atomium_absolute_elevation_m: float = 0.0


func _ready() -> void:
    if not _load_runtime():
        push_warning("LaekenTerrain: official DTM runtime is not available yet")
        return
    _build_mesh()
    _build_collision()
    call_deferred("_lower_reference_ground")
    terrain_loaded = true
    print("LAEKEN_TERRAIN_READY: source=%s %dx%d valid=%d holes=%d height_range=[%.2f, %.2f]m atomium_abs=%.2fm" % [data_path_used, width, height, valid_sample_count, invalid_sample_count, min_height_m, max_height_m, atomium_absolute_elevation_m])


func _select_runtime_path() -> String:
    if FileAccess.file_exists(PRIMARY_DATA_PATH):
        return PRIMARY_DATA_PATH
    if FileAccess.file_exists(FALLBACK_DATA_PATH):
        return FALLBACK_DATA_PATH
    return ""


func _load_runtime() -> bool:
    data_path_used = _select_runtime_path()
    if data_path_used.is_empty():
        return false
    var file := FileAccess.open(data_path_used, FileAccess.READ)
    if file == null:
        return false
    var parsed = JSON.parse_string(file.get_as_text())
    if typeof(parsed) != TYPE_DICTIONARY:
        return false
    var data := parsed as Dictionary
    if String(data.get("source_crs", "")) != "EPSG:31370":
        push_error("LaekenTerrain: terrain CRS is not EPSG:31370")
        return false

    width = int(data.get("width", 0))
    height = int(data.get("height", 0))
    first_e = float(data.get("first_sample_e", 0.0))
    first_n = float(data.get("first_sample_n", 0.0))
    step_e = float(data.get("step_e", 0.0))
    step_n = float(data.get("step_n", 0.0))
    origin_e = float(data.get("game_origin_e", 0.0))
    origin_n = float(data.get("game_origin_n", 0.0))
    min_height_m = float(data.get("relative_height_min_m", 0.0))
    max_height_m = float(data.get("relative_height_max_m", 0.0))
    var atomium = data.get("atomium_reference", {})
    if atomium is Dictionary:
        atomium_absolute_elevation_m = float(atomium.get("absolute_elevation_m", 0.0))

    var raw_heights = data.get("relative_heights_m", [])
    if not (raw_heights is Array) or width < 2 or height < 2 or raw_heights.size() != width * height:
        push_error("LaekenTerrain: invalid official DTM runtime dimensions")
        return false
    if is_zero_approx(step_e) or is_zero_approx(step_n):
        push_error("LaekenTerrain: invalid DTM sample spacing")
        return false

    var raw_mask = data.get("valid_mask", [])
    heights.resize(raw_heights.size())
    valid_mask.resize(raw_heights.size())
    valid_sample_count = 0
    invalid_sample_count = 0
    for i in range(raw_heights.size()):
        var value := float(raw_heights[i])
        var valid := value > LEGACY_NODATA_THRESHOLD
        if raw_mask is Array and raw_mask.size() == raw_heights.size():
            valid = int(raw_mask[i]) != 0
        valid_mask[i] = 1 if valid else 0
        heights[i] = value if valid else 0.0
        if valid:
            valid_sample_count += 1
        else:
            invalid_sample_count += 1

    if valid_sample_count == 0:
        push_error("LaekenTerrain: DTM runtime contains no valid samples")
        return false
    if min_height_m < LEGACY_NODATA_THRESHOLD:
        push_error("LaekenTerrain: unsafe legacy DTM runtime still contains NoData extrema")
        return false
    return true


func _index(row: int, col: int) -> int:
    return clampi(row, 0, height - 1) * width + clampi(col, 0, width - 1)


func _valid(row: int, col: int) -> bool:
    return valid_mask[_index(row, col)] != 0


func _game_x(col: int) -> float:
    return first_e + float(col) * step_e - origin_e


func _game_z(row: int) -> float:
    var north := first_n + float(row) * step_n
    return -(north - origin_n)


func _height(row: int, col: int) -> float:
    return heights[_index(row, col)]


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
    var dx := maxf(absf(step_e), 0.001)
    var dz := maxf(absf(step_n), 0.001)
    var dhdx := (right - left) / (2.0 * dx)
    var dhdz := (down - up) / (2.0 * dz)
    return Vector3(-dhdx, 1.0, -dhdz).normalized()


func _build_mesh() -> void:
    var vertices := PackedVector3Array()
    var normals := PackedVector3Array()
    var uvs := PackedVector2Array()
    vertices.resize(width * height)
    normals.resize(width * height)
    uvs.resize(width * height)

    for row in range(height):
        for col in range(width):
            var index := row * width + col
            vertices[index] = Vector3(_game_x(col), _height(row, col), _game_z(row))
            normals[index] = _normal(row, col)
            uvs[index] = Vector2(float(col) / float(width - 1), float(row) / float(height - 1)) * 32.0

    var indices := PackedInt32Array()
    for row in range(height - 1):
        for col in range(width - 1):
            var i0 := row * width + col
            var i1 := (row + 1) * width + col
            var i2 := row * width + col + 1
            var i3 := (row + 1) * width + col + 1
            if _valid(row, col) and _valid(row + 1, col) and _valid(row, col + 1):
                indices.append(i0)
                indices.append(i1)
                indices.append(i2)
            if _valid(row, col + 1) and _valid(row + 1, col) and _valid(row + 1, col + 1):
                indices.append(i2)
                indices.append(i1)
                indices.append(i3)

    if indices.is_empty():
        push_error("LaekenTerrain: no valid DTM triangles")
        return

    var arrays: Array = []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = vertices
    arrays[Mesh.ARRAY_NORMAL] = normals
    arrays[Mesh.ARRAY_TEX_UV] = uvs
    arrays[Mesh.ARRAY_INDEX] = indices

    var mesh := ArrayMesh.new()
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    mesh.surface_set_material(0, _terrain_material())
    var instance := MeshInstance3D.new()
    instance.name = "OfficialDTMTerrainMesh"
    instance.mesh = mesh
    add_child(instance)


func _terrain_material() -> ShaderMaterial:
    var shader := Shader.new()
    shader.code = """
shader_type spatial;
render_mode cull_disabled;
varying vec3 local_pos;
varying vec3 local_normal;
float hash21(vec2 p) {
    p = fract(p * vec2(127.1, 311.7));
    p += dot(p, p + 19.19);
    return fract(p.x * p.y);
}
void vertex() {
    local_pos = VERTEX;
    local_normal = NORMAL;
}
void fragment() {
    float slope = 1.0 - clamp(normalize(local_normal).y, 0.0, 1.0);
    float grain = hash21(floor(local_pos.xz * 0.42));
    float broad = hash21(floor(local_pos.xz / 8.0));
    vec3 grass_a = vec3(0.105, 0.205, 0.075);
    vec3 grass_b = vec3(0.145, 0.255, 0.095);
    vec3 soil = vec3(0.255, 0.205, 0.135);
    vec3 colour = mix(grass_a, grass_b, grain * 0.55 + broad * 0.20);
    colour = mix(colour, soil, smoothstep(0.18, 0.55, slope) * 0.58);
    ALBEDO = colour;
    ROUGHNESS = 0.98;
}
"""
    var material := ShaderMaterial.new()
    material.shader = shader
    return material


func _build_collision() -> void:
    var collision_heights := PackedFloat32Array()
    collision_heights.resize(heights.size())
    for i in range(heights.size()):
        collision_heights[i] = heights[i] if valid_mask[i] != 0 else NAN

    var shape := HeightMapShape3D.new()
    shape.map_width = width
    shape.map_depth = height
    shape.map_data = collision_heights

    var collision := CollisionShape3D.new()
    collision.name = "OfficialDTMHeightMapCollision"
    collision.shape = shape
    collision.scale = Vector3(absf(step_e), 1.0, absf(step_n))
    var first_x := _game_x(0)
    var last_x := _game_x(width - 1)
    var first_z := _game_z(0)
    var last_z := _game_z(height - 1)
    collision.position = Vector3((first_x + last_x) * 0.5, 0.0, (first_z + last_z) * 0.5)

    var body := StaticBody3D.new()
    body.name = "OfficialDTMTerrainCollision"
    body.add_child(collision)
    add_child(body)


func _lower_reference_ground() -> void:
    # The fallback plane only exists outside valid official terrain. Lower it
    # below the full DTM range so it cannot cut through the official surface.
    var fallback_y := min_height_m - 2.0
    var reference := get_parent().get_node_or_null("Phase1ReferenceGround") as MeshInstance3D
    if reference != null:
        reference.position.y = fallback_y
    var body := get_parent().get_node_or_null("Phase1ReferenceGroundCollision") as StaticBody3D
    if body != null:
        body.position.y = fallback_y - 0.1


func contains_game_point(game_x: float, game_z: float) -> bool:
    if not terrain_loaded:
        return false
    var e := game_x + origin_e
    var n := origin_n - game_z
    var col_f := (e - first_e) / step_e
    var row_f := (n - first_n) / step_n
    if col_f < 0.0 or col_f > float(width - 1) or row_f < 0.0 or row_f > float(height - 1):
        return false
    var col := clampi(int(round(col_f)), 0, width - 1)
    var row := clampi(int(round(row_f)), 0, height - 1)
    return _valid(row, col)


func sample_height(game_x: float, game_z: float) -> float:
    if not terrain_loaded:
        return 0.0
    var e := game_x + origin_e
    var n := origin_n - game_z
    var col_f := (e - first_e) / step_e
    var row_f := (n - first_n) / step_n
    if col_f < 0.0 or row_f < 0.0 or col_f > float(width - 1) or row_f > float(height - 1):
        return 0.0
    var c0 := clampi(int(floor(col_f)), 0, width - 1)
    var r0 := clampi(int(floor(row_f)), 0, height - 1)
    var c1 := mini(c0 + 1, width - 1)
    var r1 := mini(r0 + 1, height - 1)
    var tx := col_f - float(c0)
    var tz := row_f - float(r0)

    var samples := [
        [r0, c0, (1.0 - tx) * (1.0 - tz)],
        [r0, c1, tx * (1.0 - tz)],
        [r1, c0, (1.0 - tx) * tz],
        [r1, c1, tx * tz],
    ]
    var weighted := 0.0
    var total_weight := 0.0
    for sample in samples:
        var row := int(sample[0])
        var col := int(sample[1])
        var weight := float(sample[2])
        if _valid(row, col) and weight > 0.0:
            weighted += _height(row, col) * weight
            total_weight += weight
    return weighted / total_weight if total_weight > 0.000001 else 0.0
