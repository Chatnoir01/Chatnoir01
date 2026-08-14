extends Node

## Direct-spawn-only presentation of official Brussels Mobility / Paradigm
## sidewalk geometry. The source polygons are EPSG:31370; the mesh is draped
## onto the already accepted Atomium DTM. No curb, markings, paving subtype,
## collision or measured material property is inferred.

const DATA_PATH := "res://data/environment/laeken_jette/atomium_sidewalk_context.game.json"
const GREEN_PATH := "res://data/environment/laeken_jette/atomium_landcover_context.game.json"
const SURFACE_OFFSET_M := 0.030

var context_built := false
var source_crs := ""
var source_license := ""
var source_layer := ""
var source_geometry_sha256 := ""
var source_feature_count := 0
var triangle_count := 0
var excluded_green_triangle_count := 0
var material_photometry_resolved := false
var curb_geometry_resolved := false
var markings_resolved := false
var paving_subtype_resolved := false
var _sidewalk_polygons: Array = []
var _green_polygons: Array = []
var _instance: MeshInstance3D

func _ready() -> void:
    if not _wants_atomium(OS.get_cmdline_user_args()):
        return
    call_deferred("_mount_when_ready")

func _wants_atomium(args: PackedStringArray) -> bool:
    for arg: String in args:
        if arg.strip_edges().to_lower() == "spawn=atomium":
            return true
    return false

func _mount_when_ready() -> void:
    for _frame: int in range(60):
        var world := get_tree().current_scene
        if world != null:
            var terrain := world.get_node_or_null("AtomiumDirectTerrain")
            if terrain != null and bool(terrain.get("terrain_loaded")):
                build_for_world(world, terrain)
                return
        await get_tree().process_frame
    push_warning("Atomium sidewalk context: direct terrain unavailable")

func build_for_world(world: Node, terrain: Node) -> bool:
    if context_built:
        return true
    if world == null or terrain == null or not bool(terrain.get("terrain_loaded")):
        return false
    if not _load_contracts():
        return false
    var width: int = int(terrain.get("width"))
    var height: int = int(terrain.get("height"))
    var first_e: float = float(terrain.get("first_e"))
    var first_n: float = float(terrain.get("first_n"))
    var step_e: float = float(terrain.get("step_e"))
    var step_n: float = float(terrain.get("step_n"))
    var origin_e: float = float(terrain.get("origin_e"))
    var origin_n: float = float(terrain.get("origin_n"))
    var heights: PackedFloat32Array = terrain.get("heights")
    var valid_mask: PackedByteArray = terrain.get("valid_mask")
    if width < 2 or height < 2 or heights.size() != width * height or valid_mask.size() != heights.size():
        return false

    var vertices := PackedVector3Array()
    for row: int in range(height - 1):
        for col: int in range(width - 1):
            var i0 := row * width + col
            var i1 := (row + 1) * width + col
            var i2 := row * width + col + 1
            var i3 := (row + 1) * width + col + 1
            if valid_mask[i0] != 0 and valid_mask[i1] != 0 and valid_mask[i2] != 0:
                _append_triangle(vertices, [i0, i1, i2], width, first_e, first_n, step_e, step_n, origin_e, origin_n, heights)
            if valid_mask[i2] != 0 and valid_mask[i1] != 0 and valid_mask[i3] != 0:
                _append_triangle(vertices, [i2, i1, i3], width, first_e, first_n, step_e, step_n, origin_e, origin_n, heights)
    triangle_count = vertices.size() / 3
    if triangle_count <= 0:
        return false

    var arrays: Array = []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = vertices
    var mesh := ArrayMesh.new()
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    var material := StandardMaterial3D.new()
    # Reuses the already shipped Bourse sidewalk presentation values. These
    # are authored readability values, not a paving/asphalt or photometry claim.
    material.albedo_color = Color(0.48, 0.455, 0.415, 1.0)
    material.roughness = 0.95
    material.cull_mode = BaseMaterial3D.CULL_DISABLED
    mesh.surface_set_material(0, material)
    _instance = MeshInstance3D.new()
    _instance.name = "OfficialAtomiumSidewalkContext"
    _instance.mesh = mesh
    _instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    world.add_child(_instance)
    context_built = true
    print("ATOMIUM_SIDEWALK_CONTEXT_READY: features=%d triangles=%d excluded_green=%d sha256=%s" % [source_feature_count, triangle_count, excluded_green_triangle_count, source_geometry_sha256])
    return true

func set_context_visible(value: bool) -> void:
    if _instance != null:
        _instance.visible = value

func _append_triangle(vertices: PackedVector3Array, ids: Array, width: int, first_e: float, first_n: float, step_e: float, step_n: float, origin_e: float, origin_n: float, heights: PackedFloat32Array) -> void:
    var source_points: Array[Vector2] = []
    for raw_id: Variant in ids:
        var idx := int(raw_id)
        var row := idx / width
        var col := idx % width
        source_points.append(Vector2(first_e + float(col) * step_e, first_n + float(row) * step_n))
    var centroid := (source_points[0] + source_points[1] + source_points[2]) / 3.0
    if not _point_in_polygons(centroid, _sidewalk_polygons):
        return
    if _point_in_polygons(centroid, _green_polygons):
        excluded_green_triangle_count += 1
        return
    for k: int in range(3):
        var idx := int(ids[k])
        var source := source_points[k]
        vertices.append(Vector3(source.x - origin_e, heights[idx] + SURFACE_OFFSET_M, -(source.y - origin_n)))

func _load_contracts() -> bool:
    if not FileAccess.file_exists(DATA_PATH) or not FileAccess.file_exists(GREEN_PATH):
        return false
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
    var green_parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(GREEN_PATH))
    if typeof(parsed) != TYPE_DICTIONARY or typeof(green_parsed) != TYPE_DICTIONARY:
        return false
    var data := parsed as Dictionary
    if int(data.get("schema", 0)) != 2 or str(data.get("format", "")) != "grand-bruxelles-atomium-sidewalk-source-v2":
        return false
    var source := data.get("source", {}) as Dictionary
    source_crs = str(source.get("crs", ""))
    source_license = str(source.get("license", ""))
    source_layer = str(source.get("layer", ""))
    source_geometry_sha256 = str(source.get("canonical_geometry_sha256", ""))
    source_feature_count = int(data.get("feature_count", 0))
    if source_crs != "EPSG:31370" or source_license != "CC0" or source_layer != "bm_urbis:urbadm_ssw" or source_geometry_sha256.length() != 64 or source_feature_count <= 0:
        return false
    _sidewalk_polygons.clear()
    for feature_raw: Variant in data.get("features", []):
        if feature_raw is Dictionary:
            _append_geometry_polygons((feature_raw as Dictionary).get("geometry", {}), _sidewalk_polygons)
    var green := green_parsed as Dictionary
    _green_polygons.clear()
    _append_geometry_polygons(green.get("geometry", {}), _green_polygons)
    material_photometry_resolved = false
    curb_geometry_resolved = false
    markings_resolved = false
    paving_subtype_resolved = false
    return not _sidewalk_polygons.is_empty() and not _green_polygons.is_empty()

func _append_geometry_polygons(raw_geometry: Variant, target: Array) -> void:
    if not raw_geometry is Dictionary:
        return
    var geometry := raw_geometry as Dictionary
    var kind := str(geometry.get("type", ""))
    var coordinates: Variant = geometry.get("coordinates", [])
    if not coordinates is Array:
        return
    if kind == "Polygon":
        target.append(coordinates)
    elif kind == "MultiPolygon":
        for polygon: Variant in coordinates:
            if polygon is Array:
                target.append(polygon)

func _point_in_polygons(point: Vector2, polygons: Array) -> bool:
    for polygon_raw: Variant in polygons:
        if not polygon_raw is Array:
            continue
        var polygon := polygon_raw as Array
        if polygon.is_empty() or not polygon[0] is Array or not _point_in_ring(point, polygon[0] as Array):
            continue
        var in_hole := false
        for hole_index: int in range(1, polygon.size()):
            if polygon[hole_index] is Array and _point_in_ring(point, polygon[hole_index] as Array):
                in_hole = true
                break
        if not in_hole:
            return true
    return false

func _point_in_ring(point: Vector2, ring: Array) -> bool:
    if ring.size() < 3:
        return false
    var inside := false
    var j := ring.size() - 1
    for i: int in range(ring.size()):
        var a_raw: Variant = ring[i]
        var b_raw: Variant = ring[j]
        if a_raw is Array and b_raw is Array and a_raw.size() >= 2 and b_raw.size() >= 2:
            var a := Vector2(float(a_raw[0]), float(a_raw[1]))
            var b := Vector2(float(b_raw[0]), float(b_raw[1]))
            if (a.y > point.y) != (b.y > point.y):
                var cross_x := (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x
                if point.x < cross_x:
                    inside = not inside
        j = i
    return inside
