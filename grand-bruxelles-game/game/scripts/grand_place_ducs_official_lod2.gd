extends Node3D

const GEOMETRY_PATH := "res://data/urbis/grand_place_lod2/1640085.indexed.json"
const SOURCE_PATH := "res://data/qa/grand_place_ducs_1640085_source.json"
const BUILDING_ID := "https://databrussels.be/id/building/1640085"
const PACKAGE_SHA256 := "cf8449d1a62b0e47aafe6d715ff6a2739f5c48f6d75995f7f418305a5d6cf3d2"

var geometry_loaded := false
var render_triangle_count := 0
var masked_osm_count := 0
var source_height_m := 0.0
var _masked_nodes: Array[Node3D] = []
var _masked_visibility: Array[bool] = []
var _official_collision_bodies: Array[CollisionObject3D] = []
var _official_visible := true
var _wall_instance: MeshInstance3D

func _ready() -> void:
    call_deferred("_build_when_scene_ready")

func _build_when_scene_ready() -> void:
    for _frame: int in range(16):
        await get_tree().process_frame
        var current := get_tree().current_scene
        if current != null and current.get_node_or_null("BrusselsOSM/GeneratedBuildings") != null:
            break
    var mesh_data := _read_json(GEOMETRY_PATH)
    var source := _read_json(SOURCE_PATH)
    if mesh_data.is_empty() or source.is_empty():
        return
    if not _validate(mesh_data, source):
        return
    var vertices := _vertices(mesh_data.get("vertices", []))
    if vertices.is_empty():
        push_error("Ducs LoD2 vertices missing")
        return
    var bounds := _bounds(vertices)
    _mask_replaced_osm(bounds)
    var wall_material := _white_stone_material()
    var roof_material := _slate_material()
    render_triangle_count = _build_surface("Ducs_WALLSURFACE", vertices, mesh_data.get("wall_triangles", []), wall_material, true)
    render_triangle_count += _build_surface("Ducs_ROOFSURFACE", vertices, mesh_data.get("roof_triangles", []), roof_material, false)
    source_height_m = float(mesh_data.get("height_m", 0.0))
    geometry_loaded = render_triangle_count == 441
    set_meta("building_id", BUILDING_ID)
    set_meta("package_sha256", PACKAGE_SHA256)
    set_meta("source_solid_count", 2)
    set_meta("source_face_count", 146)
    set_meta("source_triangle_count", 476)
    set_meta("source_wall_face_count", 93)
    set_meta("source_roof_face_count", 51)
    set_meta("source_ground_face_count", 2)
    set_meta("city_house_count", 7)
    set_meta("heritage_bay_count", 19)
    set_meta("placement_semantics", "official_lod2_with_heritage_identity_no_surveyed_openings")
    set_meta("openings_authored", false)
    set_meta("geometry_changed", false)
    set_meta("vertical_rescaled_to_city_height", false)
    set_meta("official_collision_completed", not _official_collision_bodies.is_empty())
    set_meta("runtime_approved", false)
    set_meta("realism_complete", false)
    print("GRAND_PLACE_DUCS_LOD2_READY: building=1640085 render_triangles=%d masked_osm=%d height=%.3f collision=%d" % [render_triangle_count, masked_osm_count, source_height_m, _official_collision_bodies.size()])

func _read_json(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        push_error("Ducs LoD2 missing file: %s" % path)
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    if typeof(parsed) != TYPE_DICTIONARY:
        push_error("Ducs LoD2 invalid JSON: %s" % path)
        return {}
    return parsed as Dictionary

func _validate(mesh_data: Dictionary, source: Dictionary) -> bool:
    if str(mesh_data.get("schema", "")) != "grand-bruxelles-urbis-indexed-mesh-v1":
        push_error("Ducs indexed mesh schema mismatch"); return false
    if str(mesh_data.get("building_id", "")) != BUILDING_ID or str(source.get("official_building_id", "")) != BUILDING_ID:
        push_error("Ducs building identity mismatch"); return false
    if str(mesh_data.get("package_sha256", "")) != PACKAGE_SHA256:
        push_error("Ducs package digest mismatch"); return false
    if int(mesh_data.get("solid_count", 0)) != 2 or int(mesh_data.get("source_face_count", 0)) != 146 or int(mesh_data.get("source_triangle_count", 0)) != 476:
        push_error("Ducs source topology mismatch"); return false
    var counts := mesh_data.get("face_counts", {}) as Dictionary
    if int(counts.get("WALLSURFACE", 0)) != 93 or int(counts.get("ROOFSURFACE", 0)) != 51 or int(counts.get("GROUNDSURFACE", 0)) != 2:
        push_error("Ducs face types mismatch"); return false
    if int(source.get("city_house_count", 0)) != 7:
        push_error("Ducs City record count mismatch"); return false
    var heritage := source.get("heritage_facts", {}) as Dictionary
    if int(heritage.get("bay_count", 0)) != 19 or not bool(heritage.get("common_facade", false)):
        push_error("Ducs heritage facade identity mismatch"); return false
    if bool(source.get("runtime_approved", true)) or bool(source.get("realism_complete", true)):
        push_error("Ducs source contract overclaims approval"); return false
    return true

func _vertices(raw: Variant) -> Array[Vector3]:
    var out: Array[Vector3] = []
    if typeof(raw) != TYPE_ARRAY:
        return out
    for p: Variant in raw:
        if typeof(p) != TYPE_ARRAY or p.size() != 3:
            out.clear(); return out
        out.append(Vector3(float(p[0]), float(p[1]), float(p[2])))
    return out

func _bounds(vertices: Array[Vector3]) -> Rect2:
    var lo := Vector2(INF, INF)
    var hi := Vector2(-INF, -INF)
    for p: Vector3 in vertices:
        lo.x = minf(lo.x, p.x); lo.y = minf(lo.y, p.z)
        hi.x = maxf(hi.x, p.x); hi.y = maxf(hi.y, p.z)
    return Rect2(lo, hi - lo)

func _mask_replaced_osm(bounds: Rect2) -> void:
    var current := get_tree().current_scene
    var buildings := current.get_node_or_null("BrusselsOSM/GeneratedBuildings") if current != null else null
    if buildings == null:
        return
    var expanded := bounds.grow(2.0)
    for child: Node in buildings.get_children():
        if child is not Node3D:
            continue
        var node := child as Node3D
        if not expanded.has_point(Vector2(node.global_position.x, node.global_position.z)):
            continue
        _masked_nodes.append(node)
        _masked_visibility.append(node.visible)
        node.visible = false
        node.set_meta("replaced_by_urbis_building", "1640085")
        if node is CSGShape3D:
            (node as CSGShape3D).use_collision = false
        masked_osm_count += 1

func _white_stone_material() -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = Color(0.82, 0.80, 0.74, 1.0)
    material.roughness = 0.80
    material.cull_mode = BaseMaterial3D.CULL_DISABLED
    material.set_meta("material_identity", "heritage_white_stone")
    material.set_meta("exact_rgb_is_photometric_measurement", false)
    return material

func _slate_material() -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = Color(0.15, 0.16, 0.17, 1.0)
    material.roughness = 0.90
    material.cull_mode = BaseMaterial3D.CULL_DISABLED
    material.set_meta("exact_rgb_is_photometric_measurement", false)
    return material

func _build_surface(name_value: String, vertices: Array[Vector3], raw_triangles: Variant, material: Material, collision: bool) -> int:
    if typeof(raw_triangles) != TYPE_ARRAY:
        return 0
    var tool := SurfaceTool.new()
    tool.begin(Mesh.PRIMITIVE_TRIANGLES)
    tool.set_material(material)
    var count := 0
    for raw: Variant in raw_triangles:
        if typeof(raw) != TYPE_ARRAY or raw.size() != 3:
            continue
        var ia := int(raw[0]); var ib := int(raw[1]); var ic := int(raw[2])
        if ia < 0 or ib < 0 or ic < 0 or ia >= vertices.size() or ib >= vertices.size() or ic >= vertices.size():
            continue
        var a := vertices[ia]; var b := vertices[ib]; var c := vertices[ic]
        var normal := (b - a).cross(c - a).normalized()
        if normal.length_squared() < 0.5:
            continue
        for p: Vector3 in [a, b, c]:
            tool.set_normal(normal); tool.add_vertex(p)
        count += 1
    var mesh := tool.commit()
    if mesh == null:
        return 0
    var instance := MeshInstance3D.new()
    instance.name = name_value
    instance.mesh = mesh
    add_child(instance)
    if collision:
        _wall_instance = instance
        instance.create_trimesh_collision()
        for child: Node in instance.get_children():
            if child is CollisionObject3D:
                var body := child as CollisionObject3D
                body.collision_layer = 1
                body.collision_mask = 1
                _official_collision_bodies.append(body)
    return count

func set_official_visible(enabled: bool) -> void:
    _official_visible = enabled
    visible = enabled
    for body: CollisionObject3D in _official_collision_bodies:
        if is_instance_valid(body):
            body.collision_layer = 1 if enabled else 0
            body.collision_mask = 1 if enabled else 0
    for i: int in range(_masked_nodes.size()):
        var node := _masked_nodes[i]
        if not is_instance_valid(node):
            continue
        node.visible = false if enabled else _masked_visibility[i]
        if node is CSGShape3D:
            (node as CSGShape3D).use_collision = not enabled

func official_visible() -> bool:
    return _official_visible
