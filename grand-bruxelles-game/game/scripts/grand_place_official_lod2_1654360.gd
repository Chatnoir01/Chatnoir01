extends Node3D

const GEOMETRY_PATH := "res://data/urbis/grand_place_lod2/1654360.game.json"
const BUILDING_ID := "https://databrussels.be/id/building/1654360"
const PACKAGE_SHA256 := "cf8449d1a62b0e47aafe6d715ff6a2739f5c48f6d75995f7f418305a5d6cf3d2"
const CITY_TOTAL_HEIGHT_M := 38.0
const LOD2_HEIGHT_M := 30.387
const HEIGHT_UNDERREPRESENTATION_M := 7.613
const EXPECTED_FACE_COUNT := 71
const EXPECTED_TRIANGLE_COUNT := 230
const EXPECTED_RENDER_TRIANGLE_COUNT := 213

var geometry_loaded := false
var render_triangle_count := 0
var masked_osm_count := 0
var source_height_m := 0.0
var source_bounds := Rect2()
var _built := false
var _official_visible := true
var _masked_nodes: Array[Node3D] = []
var _masked_visibility: Array[bool] = []
var _official_collision_bodies: Array[CollisionObject3D] = []

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
    source_bounds = _horizontal_bounds(faces)
    source_height_m = float((data.get("evidence", {}) as Dictionary).get("height_m", 0.0))
    _mask_replaced_osm(source_bounds)
    _build_geometry(faces)
    if render_triangle_count != EXPECTED_RENDER_TRIANGLE_COUNT:
        push_error("Maison du Roi render triangle contract drifted: %d" % render_triangle_count)
        return
    _built = true
    geometry_loaded = true
    set_meta("building_id", BUILDING_ID)
    set_meta("package_sha256", PACKAGE_SHA256)
    set_meta("city_total_height_m", CITY_TOTAL_HEIGHT_M)
    set_meta("lod2_height_m", LOD2_HEIGHT_M)
    set_meta("height_underrepresentation_m", HEIGHT_UNDERREPRESENTATION_M)
    set_meta("vertical_completeness", false)
    set_meta("geometry_rescaled", false)
    set_meta("openings_authored", false)
    set_meta("material_identity_complete", false)
    set_meta("runtime_approved", false)
    set_meta("realism_complete", false)
    set_meta("official_collision_completed", not _official_collision_bodies.is_empty())
    set_meta("wall_material_semantics", "mixed brick/blue stone/Gobertange stone; exact LoD2 distribution unresolved")
    set_meta("roof_material_semantics", "slate")
    print("GRAND_PLACE_MAISON_DU_ROI_READY: triangles=%d masked_osm=%d lod2_height=%.3f city_height=%.3f vertically_complete=false" % [render_triangle_count, masked_osm_count, source_height_m, CITY_TOTAL_HEIGHT_M])

func _read_geometry() -> Dictionary:
    if not FileAccess.file_exists(GEOMETRY_PATH):
        push_error("Maison du Roi official LoD2 geometry missing")
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(GEOMETRY_PATH))
    if typeof(parsed) != TYPE_DICTIONARY:
        push_error("Maison du Roi official LoD2 JSON invalid")
        return {}
    var data: Dictionary = parsed
    var source: Dictionary = data.get("source", {})
    var evidence: Dictionary = data.get("evidence", {})
    if str(data.get("schema", "")) != "grand-bruxelles-urbis-context-mesh-v1":
        push_error("Maison du Roi schema mismatch")
        return {}
    if str(source.get("building_2d_id", "")) != BUILDING_ID:
        push_error("Maison du Roi building identity mismatch")
        return {}
    if str(source.get("crs", "")) != "EPSG:31370" or str(source.get("license", "")) != "CC0-1.0":
        push_error("Maison du Roi provenance drifted")
        return {}
    if str(source.get("package_sha256", "")) != PACKAGE_SHA256:
        push_error("Maison du Roi package digest drifted")
        return {}
    if int(evidence.get("face_count", 0)) != EXPECTED_FACE_COUNT or int(evidence.get("triangle_count", 0)) != EXPECTED_TRIANGLE_COUNT:
        push_error("Maison du Roi geometry counts drifted")
        return {}
    var types: Dictionary = evidence.get("face_type_counts", {})
    if int(types.get("WALLSURFACE", 0)) != 48 or int(types.get("ROOFSURFACE", 0)) != 22 or int(types.get("GROUNDSURFACE", 0)) != 1:
        push_error("Maison du Roi face types drifted")
        return {}
    if absf(float(evidence.get("height_m", 0.0)) - LOD2_HEIGHT_M) > 0.001:
        push_error("Maison du Roi LoD2 height drifted")
        return {}
    if bool(data.get("runtime_approved", true)):
        push_error("Maison du Roi evidence must remain non-approved")
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
        node.set_meta("replaced_by_urbis_building", "1654360")
        if node is CSGShape3D:
            (node as CSGShape3D).use_collision = false
        masked_osm_count += 1

func _materials() -> Dictionary:
    var wall := StandardMaterial3D.new()
    wall.albedo_color = Color(0.68, 0.64, 0.56, 1.0)
    wall.roughness = 0.88
    wall.cull_mode = BaseMaterial3D.CULL_BACK
    wall.set_meta("material_semantics", "mixed_masonry_unresolved")
    wall.set_meta("exact_rgb_is_photometric_measurement", false)
    var roof := StandardMaterial3D.new()
    roof.albedo_color = Color(0.14, 0.15, 0.16, 1.0)
    roof.roughness = 0.92
    roof.cull_mode = BaseMaterial3D.CULL_BACK
    roof.set_meta("material_semantics", "slate")
    roof.set_meta("exact_rgb_is_photometric_measurement", false)
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
        instance.name = "GrandPlace1654360_%s" % face_type
        instance.mesh = mesh
        add_child(instance)
        if face_type == "WALLSURFACE":
            instance.create_trimesh_collision()
            for child: Node in instance.get_children():
                if child is CollisionObject3D:
                    var collision := child as CollisionObject3D
                    collision.collision_layer = 1
                    collision.collision_mask = 1
                    _official_collision_bodies.append(collision)
    return count

func _build_geometry(faces: Array) -> void:
    var mats := _materials()
    var center := _building_center(faces)
    render_triangle_count = _build_surface(faces, "WALLSURFACE", mats["WALLSURFACE"], center)
    render_triangle_count += _build_surface(faces, "ROOFSURFACE", mats["ROOFSURFACE"], center)

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
