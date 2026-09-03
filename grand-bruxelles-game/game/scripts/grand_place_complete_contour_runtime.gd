extends Node3D

const SOURCE_DIR := "res://data/urbis/grand_place_lod2"
const SOURCE_SCHEMA := "grand-bruxelles-urbis-context-mesh-v1"
const PACKAGE_SHA256 := "cf8449d1a62b0e47aafe6d715ff6a2739f5c48f6d75995f7f418305a5d6cf3d2"
const EXPECTED_SOURCE_FACE_COUNT := 551
const EXPECTED_SOURCE_TRIANGLE_COUNT := 1712
const TRIANGLE_CROSS_EPSILON_SQ := 1.0e-12
const EXPECTED_OWNER_IDS := [
    "1601883", "1601884", "1608847", "1608851", "1611166", "1613517",
    "1635455", "1635485", "1637695", "1637729", "1639974", "1639985",
    "1643344", "1645578", "1645580", "1646728", "1647834", "1647943",
    "1649069", "1653185", "1654360", "1661439", "1781508"
]
const DEDICATED_RUNTIME_OWNER_IDS := ["1655673", "1786758"]
const OSM_MASK_GROW_M := 0.0

var geometry_loaded := false
var source_face_count := 0
var source_triangle_count := 0
var wall_roof_source_triangle_count := 0
var render_triangle_count := 0
var degenerate_render_triangle_count := 0
var collision_body_count := 0
var masked_osm_count := 0
var loaded_owner_ids: Array[String] = []

var _done := false
var _failed := false
var _built := false
var _build_started := false
var _visible := true
var _bound_scene: Node = null
var _mesh_nodes: Array[MeshInstance3D] = []
var _collision_bodies: Array[CollisionObject3D] = []
var _masked_nodes: Array[Node3D] = []
var _masked_original_visible: Dictionary = {}
var _masked_original_csg_collision: Dictionary = {}
var _masked_instance_ids: Dictionary = {}
var _wall_material: StandardMaterial3D
var _roof_material: StandardMaterial3D

func _ready() -> void:
    call_deferred("_build_when_scene_ready")

func bind_scene(scene: Node) -> void:
    if scene == null or _built or _build_started:
        return
    _bound_scene = scene
    call_deferred("_build_bound_scene")

func _build_bound_scene() -> void:
    if _built or _build_started or _bound_scene == null:
        return
    _build_for_scene(_bound_scene)

func _build_when_scene_ready() -> void:
    for _frame: int in range(20):
        if _built or _build_started:
            return
        var scene := _bound_scene if _bound_scene != null else _discover_scene_root()
        if scene != null:
            _build_for_scene(scene)
            return
        await get_tree().process_frame
    _stop("production scene with BrusselsOSM/GeneratedBuildings not found")

func _discover_scene_root() -> Node:
    var current := get_tree().current_scene
    if current != null and current.get_node_or_null("BrusselsOSM/GeneratedBuildings") != null:
        return current
    for child: Node in get_tree().root.get_children():
        if child == self:
            continue
        if child.get_node_or_null("BrusselsOSM/GeneratedBuildings") != null:
            return child
        if child is Viewport:
            for nested: Node in child.get_children():
                if nested.get_node_or_null("BrusselsOSM/GeneratedBuildings") != null:
                    return nested
    return null

func _stop(message: String) -> void:
    _failed = true
    _done = true
    push_error("Grand-Place complete contour: %s" % message)

func _build_for_scene(scene: Node) -> void:
    if _built or _build_started:
        return
    _build_started = true
    var source_by_owner: Dictionary = {}
    var aggregate_faces := 0
    var aggregate_triangles := 0
    for owner_id: String in EXPECTED_OWNER_IDS:
        var data := _read_owner(owner_id)
        if data.is_empty():
            _stop("owner %s failed source validation" % owner_id)
            return
        source_by_owner[owner_id] = data
        var evidence: Dictionary = data.get("evidence", {})
        aggregate_faces += int(evidence.get("face_count", 0))
        aggregate_triangles += int(evidence.get("triangle_count", 0))
    if aggregate_faces != EXPECTED_SOURCE_FACE_COUNT:
        _stop("23-owner source face total drifted: %d" % aggregate_faces)
        return
    if aggregate_triangles != EXPECTED_SOURCE_TRIANGLE_COUNT:
        _stop("23-owner source triangle total drifted: %d" % aggregate_triangles)
        return

    _create_neutral_materials()
    for owner_id: String in EXPECTED_OWNER_IDS:
        var data: Dictionary = source_by_owner[owner_id]
        var faces: Array = data.get("faces", [])
        var evidence: Dictionary = data.get("evidence", {})
        source_face_count += int(evidence.get("face_count", 0))
        source_triangle_count += int(evidence.get("triangle_count", 0))
        _mask_replaced_osm(owner_id, _horizontal_bounds(faces), scene)
        _build_owner(owner_id, faces)
        loaded_owner_ids.append(owner_id)

    loaded_owner_ids.sort()
    collision_body_count = _collision_bodies.size()
    if loaded_owner_ids.size() != EXPECTED_OWNER_IDS.size():
        _stop("loaded owner count drifted")
        return
    if render_triangle_count + degenerate_render_triangle_count != wall_roof_source_triangle_count:
        _stop("WALL+ROOF triangle accounting is not closed")
        return

    _built = true
    geometry_loaded = true
    _done = true
    set_meta("source_geometry", "official_urbis_lod2_unchanged")
    set_meta("source_revision", "2026-08-08")
    set_meta("source_package_sha256", PACKAGE_SHA256)
    set_meta("owner_count", loaded_owner_ids.size())
    set_meta("dedicated_runtime_owner_ids", DEDICATED_RUNTIME_OWNER_IDS)
    set_meta("semantic_guessing", false)
    set_meta("presentation_identity", "neutral_unregistered")
    set_meta("groundsurface_rendered", false)
    set_meta("official_wall_collision", true)
    set_meta("degenerate_source_geometry_repaired", false)
    set_meta("realism_complete", false)
    print("GRAND_PLACE_COMPLETE_CONTOUR_READY: owners=%d source_faces=%d source_triangles=%d wall_roof_source=%d render_triangles=%d degenerate_wall_roof=%d collisions=%d masked_osm=%d neutral=true" % [loaded_owner_ids.size(), source_face_count, source_triangle_count, wall_roof_source_triangle_count, render_triangle_count, degenerate_render_triangle_count, collision_body_count, masked_osm_count])

func _source_point_is_valid(raw: Variant) -> bool:
    if typeof(raw) != TYPE_ARRAY or raw.size() != 3:
        return false
    for raw_component: Variant in raw:
        var component_type := typeof(raw_component)
        if component_type != TYPE_INT and component_type != TYPE_FLOAT:
            return false
    var point := Vector3(float(raw[0]), float(raw[1]), float(raw[2]))
    return point.is_finite()

func _read_owner(owner_id: String) -> Dictionary:
    var path := SOURCE_DIR.path_join("%s.game.json" % owner_id)
    if not FileAccess.file_exists(path):
        push_error("Grand-Place contour source missing: %s" % path)
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    if typeof(parsed) != TYPE_DICTIONARY:
        push_error("Grand-Place contour source JSON invalid: %s" % owner_id)
        return {}
    var data: Dictionary = parsed
    if str(data.get("schema", "")) != SOURCE_SCHEMA or bool(data.get("runtime_approved", true)):
        push_error("Grand-Place contour schema/approval mismatch: %s" % owner_id)
        return {}
    var source: Dictionary = data.get("source", {})
    if str(source.get("building_2d_id", "")) != "https://databrussels.be/id/building/%s" % owner_id:
        push_error("Grand-Place contour building identity mismatch: %s" % owner_id)
        return {}
    if str(source.get("crs", "")) != "EPSG:31370" or str(source.get("license", "")) != "CC0-1.0" or str(source.get("package_sha256", "")) != PACKAGE_SHA256:
        push_error("Grand-Place contour provenance mismatch: %s" % owner_id)
        return {}
    var evidence: Dictionary = data.get("evidence", {})
    var faces: Array = data.get("faces", [])
    if faces.size() != int(evidence.get("face_count", 0)) or faces.is_empty():
        push_error("Grand-Place contour face count mismatch: %s" % owner_id)
        return {}
    var counted_triangles := 0
    for raw_face: Variant in faces:
        if typeof(raw_face) != TYPE_DICTIONARY:
            return {}
        var face_type := str(raw_face.get("type", ""))
        if face_type not in ["WALLSURFACE", "ROOFSURFACE", "GROUNDSURFACE"]:
            push_error("Grand-Place contour unsupported face type %s: %s" % [face_type, owner_id])
            return {}
        for raw_triangle: Variant in raw_face.get("triangles", []):
            if typeof(raw_triangle) != TYPE_ARRAY or raw_triangle.size() != 3:
                push_error("Grand-Place contour malformed triangle: %s" % owner_id)
                return {}
            for raw_point: Variant in raw_triangle:
                if not _source_point_is_valid(raw_point):
                    push_error("Grand-Place contour non-canonical source point: %s" % owner_id)
                    return {}
            counted_triangles += 1
    if counted_triangles != int(evidence.get("triangle_count", 0)):
        push_error("Grand-Place contour triangle count mismatch: %s" % owner_id)
        return {}
    return data

func _create_neutral_materials() -> void:
    _wall_material = StandardMaterial3D.new()
    _wall_material.albedo_color = Color(0.58, 0.56, 0.52, 1.0)
    _wall_material.roughness = 0.88
    _wall_material.cull_mode = BaseMaterial3D.CULL_BACK
    _roof_material = StandardMaterial3D.new()
    _roof_material.albedo_color = Color(0.20, 0.21, 0.22, 1.0)
    _roof_material.roughness = 0.90
    _roof_material.cull_mode = BaseMaterial3D.CULL_BACK

func _point(raw: Variant) -> Vector3:
    if not _source_point_is_valid(raw):
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

func _mask_replaced_osm(owner_id: String, bounds: Rect2, scene: Node) -> void:
    var generated := scene.get_node_or_null("BrusselsOSM/GeneratedBuildings")
    if generated == null or bounds.size.length_squared() <= 0.001:
        return
    var expanded := bounds.grow(OSM_MASK_GROW_M)
    for child: Node in generated.get_children():
        if not child is Node3D:
            continue
        var node := child as Node3D
        if not expanded.has_point(Vector2(node.global_position.x, node.global_position.z)) or node.has_meta("replaced_by_urbis_building"):
            continue
        var instance_id := node.get_instance_id()
        if _masked_instance_ids.has(instance_id):
            continue
        _masked_instance_ids[instance_id] = true
        _masked_nodes.append(node)
        _masked_original_visible[instance_id] = node.visible
        node.visible = false
        node.set_meta("replaced_by_urbis_building", owner_id)
        if node is CSGShape3D:
            var csg := node as CSGShape3D
            _masked_original_csg_collision[instance_id] = csg.use_collision
            csg.use_collision = false
        masked_osm_count += 1

func _append_faces(tool: SurfaceTool, faces: Array, face_type: String, center: Vector3) -> int:
    var count := 0
    for raw_face: Variant in faces:
        if typeof(raw_face) != TYPE_DICTIONARY or str(raw_face.get("type", "")) != face_type:
            continue
        for raw_triangle: Variant in raw_face.get("triangles", []):
            if typeof(raw_triangle) != TYPE_ARRAY or raw_triangle.size() != 3:
                continue
            wall_roof_source_triangle_count += 1
            var a := _point(raw_triangle[0])
            var b := _point(raw_triangle[1])
            var c := _point(raw_triangle[2])
            if not a.is_finite() or not b.is_finite() or not c.is_finite():
                _stop("non-finite source triangle reached render path")
                return count
            var cross := (b - a).cross(c - a)
            if not cross.is_finite() or cross.length_squared() <= TRIANGLE_CROSS_EPSILON_SQ:
                degenerate_render_triangle_count += 1
                continue
            var normal := cross.normalized()
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

func _build_surface(owner_id: String, faces: Array, face_type: String, material: Material, center: Vector3) -> int:
    var tool := SurfaceTool.new()
    tool.begin(Mesh.PRIMITIVE_TRIANGLES)
    tool.set_material(material)
    var count := _append_faces(tool, faces, face_type, center)
    if count <= 0:
        return 0
    var mesh := tool.commit()
    if mesh == null or mesh.get_surface_count() <= 0:
        _stop("non-empty render surface failed to commit: %s %s" % [owner_id, face_type])
        return 0
    var instance := MeshInstance3D.new()
    instance.name = "GrandPlaceContour_%s_%s" % [owner_id, face_type]
    instance.mesh = mesh
    instance.set_meta("urbis_owner_id", owner_id)
    instance.set_meta("source_geometry_unchanged", true)
    instance.set_meta("presentation_identity", "neutral_unregistered")
    add_child(instance)
    _mesh_nodes.append(instance)
    if face_type == "WALLSURFACE":
        _create_official_wall_collision(instance, owner_id)
    return count

func _create_official_wall_collision(instance: MeshInstance3D, owner_id: String) -> void:
    instance.create_trimesh_collision()
    for child: Node in instance.get_children():
        if child is CollisionObject3D:
            var collision := child as CollisionObject3D
            collision.collision_layer = 1
            collision.collision_mask = 1
            collision.set_meta("urbis_owner_id", owner_id)
            collision.set_meta("official_wall_collision", true)
            _collision_bodies.append(collision)

func _build_owner(owner_id: String, faces: Array) -> void:
    var center := _building_center(faces)
    render_triangle_count += _build_surface(owner_id, faces, "WALLSURFACE", _wall_material, center)
    render_triangle_count += _build_surface(owner_id, faces, "ROOFSURFACE", _roof_material, center)

func _apply_osm_mask(enabled: bool) -> void:
    for node: Node3D in _masked_nodes:
        if not is_instance_valid(node):
            continue
        var instance_id := node.get_instance_id()
        if enabled:
            node.visible = false
            if node is CSGShape3D:
                (node as CSGShape3D).use_collision = false
        else:
            node.visible = bool(_masked_original_visible.get(instance_id, true))
            if node is CSGShape3D:
                (node as CSGShape3D).use_collision = bool(_masked_original_csg_collision.get(instance_id, false))

func set_official_visible(enabled: bool) -> void:
    _visible = enabled
    for mesh: MeshInstance3D in _mesh_nodes:
        if is_instance_valid(mesh):
            mesh.visible = enabled
    for body: CollisionObject3D in _collision_bodies:
        if is_instance_valid(body):
            body.collision_layer = 1 if enabled else 0
            body.collision_mask = 1 if enabled else 0
    _apply_osm_mask(enabled)

func ready_complete() -> bool:
    return _done

func failed() -> bool:
    return _failed

func owner_count() -> int:
    return loaded_owner_ids.size()

func get_loaded_owner_ids() -> Array[String]:
    return loaded_owner_ids.duplicate()

func visible_surface_count() -> int:
    var count := 0
    for mesh: MeshInstance3D in _mesh_nodes:
        if is_instance_valid(mesh) and mesh.visible:
            count += 1
    return count

func active_collision_count() -> int:
    var count := 0
    for body: CollisionObject3D in _collision_bodies:
        if is_instance_valid(body) and body.collision_layer != 0:
            count += 1
    return count

func world_matches(world: World3D) -> bool:
    return world != null and get_world_3d() == world