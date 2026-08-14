extends Node3D

const GEOMETRY_PATH := "res://data/urbis/grand_place_lod2/1655673.game.json"
const MATERIAL_IDENTITY_PATH := "res://data/visual/grand_place_1655673_material_identity.json"
const BUILDING_ID := "https://databrussels.be/id/building/1655673"
const NEUTRAL_WALL_COLOR := Color(0.56, 0.54, 0.50, 1.0)
const WHITE_STONE_WALL_COLOR := Color(0.78, 0.76, 0.70, 1.0)
const NEUTRAL_WALL_ROUGHNESS := 0.88
const WHITE_STONE_WALL_ROUGHNESS := 0.82

var geometry_loaded := false
var render_triangle_count := 0
var masked_osm_count := 0
var source_height_m := 0.0
var source_bounds := Rect2()
var _masked_nodes: Array[Node3D] = []
var _masked_visibility: Array[bool] = []
var _official_collision_bodies: Array[CollisionObject3D] = []
var _official_visible := true
var _built := false
var _wall_material: StandardMaterial3D


func _ready() -> void:
    call_deferred("_build_when_scene_ready")


func _build_when_scene_ready() -> void:
    for _frame: int in range(8):
        await get_tree().process_frame
        var main := get_tree().current_scene
        if main != null and main.get_node_or_null("BrusselsOSM/GeneratedBuildings") != null:
            break
    if _built:
        return
    var data := _read_geometry()
    if data.is_empty():
        return
    var faces: Array = data.get("faces", [])
    var evidence: Dictionary = data.get("evidence", {})
    source_bounds = _horizontal_bounds(faces)
    source_height_m = float(evidence.get("height_m", 0.0))
    _mask_replaced_osm(source_bounds)
    _build_geometry(faces)
    _built = true
    geometry_loaded = true
    set_meta("building_id", BUILDING_ID)
    set_meta("runtime_approved", false)
    set_meta("realism_complete", false)
    set_meta("presentation_materials_only", true)
    set_meta("wall_material_identity", "official_heritage_white_stone")
    set_meta("wall_material_source", MATERIAL_IDENTITY_PATH)
    set_meta("official_collision_completed", not _official_collision_bodies.is_empty())
    print("GRAND_PLACE_LOD2_1655673_READY: triangles=%d masked_osm=%d height=%.3f white_stone=true collision_bodies=%d" % [render_triangle_count, masked_osm_count, source_height_m, _official_collision_bodies.size()])


func _read_geometry() -> Dictionary:
    if not FileAccess.file_exists(GEOMETRY_PATH):
        push_error("Grand-Place LoD2 geometry missing: %s" % GEOMETRY_PATH)
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(GEOMETRY_PATH))
    if typeof(parsed) != TYPE_DICTIONARY:
        push_error("Grand-Place LoD2 geometry JSON invalid")
        return {}
    var data: Dictionary = parsed
    if str(data.get("schema", "")) != "grand-bruxelles-urbis-context-mesh-v1":
        push_error("Grand-Place LoD2 schema mismatch")
        return {}
    var source: Dictionary = data.get("source", {})
    var evidence: Dictionary = data.get("evidence", {})
    if str(source.get("building_2d_id", "")) != BUILDING_ID:
        push_error("Grand-Place LoD2 building identity mismatch")
        return {}
    if str(source.get("crs", "")) != "EPSG:31370" or str(source.get("license", "")) != "CC0-1.0":
        push_error("Grand-Place LoD2 source provenance drifted")
        return {}
    if str(source.get("package_sha256", "")) != "cf8449d1a62b0e47aafe6d715ff6a2739f5c48f6d75995f7f418305a5d6cf3d2":
        push_error("Grand-Place LoD2 package digest drifted")
        return {}
    if int(evidence.get("face_count", 0)) != 82 or int(evidence.get("triangle_count", 0)) != 262:
        push_error("Grand-Place LoD2 geometry contract drifted")
        return {}
    if bool(data.get("runtime_approved", true)):
        push_error("Grand-Place LoD2 evidence must remain non-approved")
        return {}
    return data


func _point(raw: Variant) -> Vector3:
    if typeof(raw) != TYPE_ARRAY or raw.size() != 3:
        return Vector3.INF
    return Vector3(float(raw[0]), float(raw[1]), float(raw[2]))


func _horizontal_bounds(faces: Array) -> Rect2:
    var initialized := false
    var lo := Vector2.ZERO
    var hi := Vector2.ZERO
    for raw_face: Variant in faces:
        if typeof(raw_face) != TYPE_DICTIONARY:
            continue
        for raw_triangle: Variant in raw_face.get("triangles", []):
            if typeof(raw_triangle) != TYPE_ARRAY:
                continue
            for raw_point: Variant in raw_triangle:
                var p := _point(raw_point)
                if not p.is_finite():
                    continue
                var xz := Vector2(p.x, p.z)
                if not initialized:
                    lo = xz
                    hi = xz
                    initialized = true
                else:
                    lo.x = minf(lo.x, xz.x)
                    lo.y = minf(lo.y, xz.y)
                    hi.x = maxf(hi.x, xz.x)
                    hi.y = maxf(hi.y, xz.y)
    return Rect2(lo, hi - lo) if initialized else Rect2()


func _mask_replaced_osm(bounds: Rect2) -> void:
    var main := get_tree().current_scene
    var buildings := main.get_node_or_null("BrusselsOSM/GeneratedBuildings") if main != null else null
    if buildings == null or bounds.size.length_squared() <= 0.001:
        return
    var expanded := bounds.grow(3.0)
    for child: Node in buildings.get_children():
        if not child is Node3D:
            continue
        var node := child as Node3D
        if not expanded.has_point(Vector2(node.global_position.x, node.global_position.z)):
            continue
        _masked_nodes.append(node)
        _masked_visibility.append(node.visible)
        node.visible = false
        node.set_meta("replaced_by_urbis_building", "1655673")
        if node is CSGShape3D:
            (node as CSGShape3D).use_collision = false
        masked_osm_count += 1


func _materials() -> Dictionary:
    var wall := StandardMaterial3D.new()
    wall.albedo_color = WHITE_STONE_WALL_COLOR
    wall.roughness = WHITE_STONE_WALL_ROUGHNESS
    wall.cull_mode = BaseMaterial3D.CULL_BACK
    _wall_material = wall
    var roof := StandardMaterial3D.new()
    roof.albedo_color = Color(0.16, 0.17, 0.18, 1.0)
    roof.roughness = 0.9
    roof.cull_mode = BaseMaterial3D.CULL_BACK
    return {"WALLSURFACE": wall, "ROOFSURFACE": roof}


func _building_center(faces: Array) -> Vector3:
    var sum := Vector3.ZERO
    var count := 0
    for raw_face: Variant in faces:
        if typeof(raw_face) != TYPE_DICTIONARY:
            continue
        for raw_triangle: Variant in raw_face.get("triangles", []):
            if typeof(raw_triangle) != TYPE_ARRAY:
                continue
            for raw_point: Variant in raw_triangle:
                var p := _point(raw_point)
                if p.is_finite():
                    sum += p
                    count += 1
    return sum / float(count) if count > 0 else Vector3.ZERO


func _append_faces(tool: SurfaceTool, faces: Array, face_type: String, center: Vector3) -> int:
    var count := 0
    for raw_face: Variant in faces:
        if typeof(raw_face) != TYPE_DICTIONARY or str(raw_face.get("type", "")) != face_type:
            continue
        for raw_triangle: Variant in raw_face.get("triangles", []):
            if typeof(raw_triangle) != TYPE_ARRAY or raw_triangle.size() != 3:
                continue
            var a := _point(raw_triangle[0])
            var b := _point(raw_triangle[1])
            var c := _point(raw_triangle[2])
            if not a.is_finite() or not b.is_finite() or not c.is_finite():
                continue
            var normal := (b - a).cross(c - a).normalized()
            if not normal.is_finite() or normal.length_squared() < 0.5:
                continue
            var flip := false
            if face_type == "ROOFSURFACE":
                flip = normal.y < 0.0
            else:
                var tri_center := (a + b + c) / 3.0
                var outward := Vector3(tri_center.x - center.x, 0.0, tri_center.z - center.z)
                var horizontal_normal := Vector3(normal.x, 0.0, normal.z)
                if outward.length_squared() > 0.0001 and horizontal_normal.length_squared() > 0.0001:
                    flip = horizontal_normal.dot(outward) < 0.0
            if flip:
                var swap := b
                b = c
                c = swap
                normal = -normal
            for vertex: Vector3 in [a, b, c]:
                tool.set_normal(normal)
                tool.add_vertex(vertex)
            count += 1
    return count


func _build_surface(faces: Array, face_type: String, material: Material, center: Vector3) -> int:
    var tool := SurfaceTool.new()
    tool.begin(Mesh.PRIMITIVE_TRIANGLES)
    tool.set_material(material)
    var count := _append_faces(tool, faces, face_type, center)
    var mesh := tool.commit()
    if mesh != null and mesh.get_surface_count() > 0:
        var instance := MeshInstance3D.new()
        instance.name = "GrandPlace1655673_%s" % face_type
        instance.mesh = mesh
        add_child(instance)
        if face_type == "WALLSURFACE":
            _create_official_wall_collision(instance)
    return count


func _create_official_wall_collision(instance: MeshInstance3D) -> void:
    instance.create_trimesh_collision()
    for child: Node in instance.get_children():
        if child is CollisionObject3D:
            var collision := child as CollisionObject3D
            collision.collision_layer = 1
            collision.collision_mask = 1
            _official_collision_bodies.append(collision)


func _build_geometry(faces: Array) -> void:
    var mats := _materials()
    var center := _building_center(faces)
    render_triangle_count = _build_surface(faces, "WALLSURFACE", mats["WALLSURFACE"], center)
    render_triangle_count += _build_surface(faces, "ROOFSURFACE", mats["ROOFSURFACE"], center)


func set_sourced_wall_material(enabled: bool) -> void:
    if _wall_material == null:
        return
    _wall_material.albedo_color = WHITE_STONE_WALL_COLOR if enabled else NEUTRAL_WALL_COLOR
    _wall_material.roughness = WHITE_STONE_WALL_ROUGHNESS if enabled else NEUTRAL_WALL_ROUGHNESS


func sourced_wall_material_enabled() -> bool:
    return _wall_material != null and _wall_material.albedo_color.is_equal_approx(WHITE_STONE_WALL_COLOR)


func set_official_visible(enabled: bool) -> void:
    _official_visible = enabled
    visible = enabled
    for collision: CollisionObject3D in _official_collision_bodies:
        if is_instance_valid(collision):
            collision.collision_layer = 1 if enabled else 0
            collision.collision_mask = 1 if enabled else 0
    for i: int in range(_masked_nodes.size()):
        var node := _masked_nodes[i]
        if not is_instance_valid(node):
            continue
        node.visible = false if enabled else _masked_visibility[i]
        if node is CSGShape3D:
            (node as CSGShape3D).use_collision = not enabled


func official_visible() -> bool:
    return _official_visible
