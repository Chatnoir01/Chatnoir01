extends Node3D

const DATA_DIR := "res://data/urbis/grand_place_contiguous_lod2_front"
const TARGET_IDS := [
    "1601883", "1601884", "1635485", "1637729", "1639985", "1643344",
    "1645580", "1646728", "1647834", "1649069", "1661439", "1781508",
]
const PACKAGE_SHA256 := "cf8449d1a62b0e47aafe6d715ff6a2739f5c48f6d75995f7f418305a5d6cf3d2"
const EXPECTED_RENDER_TRIANGLES := 573

var geometry_loaded := false
var building_count := 0
var render_triangle_count := 0
var masked_osm_count := 0
var _built := false
var _front_visible := true
var _official_root: Node3D
var _official_collisions: Array[CollisionObject3D] = []
var _masked_nodes: Array[Node3D] = []
var _masked_visibility: Array[bool] = []
var _masked_collision: Array[bool] = []

func _ready() -> void:
    call_deferred("_build_when_scene_ready")

func _build_when_scene_ready() -> void:
    for _frame: int in range(12):
        await get_tree().process_frame
        var main := get_tree().current_scene
        if main != null and main.get_node_or_null("BrusselsOSM/GeneratedBuildings") != null:
            break
    if _built:
        return
    var buildings := _read_all_buildings()
    if buildings.size() != TARGET_IDS.size():
        push_error("Grand-Place contiguous LoD2 front source set incomplete")
        return
    _official_root = Node3D.new()
    _official_root.name = "GrandPlaceContiguousOfficialLod2Front"
    add_child(_official_root)
    var bounds: Array[Rect2] = []
    for data_variant: Variant in buildings:
        var data: Dictionary = data_variant
        var faces: Array = data.get("faces", [])
        var bid := _compact_building_id(str((data.get("source", {}) as Dictionary).get("building_2d_id", "")))
        var building_node := Node3D.new()
        building_node.name = "Official_%s" % bid
        building_node.set_meta("building_id", bid)
        building_node.set_meta("source_geometry", "UrbIS 3D Constructions LoD2")
        building_node.set_meta("semantic_name_authorized", false)
        _official_root.add_child(building_node)
        bounds.append(_horizontal_bounds(faces))
        render_triangle_count += _build_building(building_node, faces, bid)
        building_count += 1
    if render_triangle_count != EXPECTED_RENDER_TRIANGLES:
        push_error("Grand-Place contiguous LoD2 render triangle contract drifted: %d" % render_triangle_count)
        return
    _mask_replaced_osm(bounds)
    _built = true
    geometry_loaded = true
    set_meta("runtime_approved", false)
    set_meta("source_geometry_unchanged", true)
    set_meta("semantic_names_authorized", false)
    set_meta("presentation_palette_is_measurement", false)
    set_meta("building_count", building_count)
    set_meta("render_triangle_count", render_triangle_count)
    set_front_visible(true)
    print("GRAND_PLACE_CONTIGUOUS_LOD2_FRONT_READY: buildings=%d triangles=%d masked_osm=%d" % [building_count, render_triangle_count, masked_osm_count])

func _read_all_buildings() -> Array:
    var result: Array = []
    for bid_variant: Variant in TARGET_IDS:
        var bid := str(bid_variant)
        var path := "%s/%s.game.json" % [DATA_DIR, bid]
        if not FileAccess.file_exists(path):
            push_error("Grand-Place contiguous LoD2 source missing: %s" % bid)
            return []
        var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
        if typeof(parsed) != TYPE_DICTIONARY:
            push_error("Grand-Place contiguous LoD2 JSON invalid: %s" % bid)
            return []
        var data: Dictionary = parsed
        if not _validate_building(data, bid):
            return []
        result.append(data)
    return result

func _validate_building(data: Dictionary, bid: String) -> bool:
    if str(data.get("schema", "")) != "grand-bruxelles-urbis-context-mesh-v1":
        push_error("Grand-Place contiguous LoD2 schema mismatch: %s" % bid)
        return false
    var source: Dictionary = data.get("source", {})
    if _compact_building_id(str(source.get("building_2d_id", ""))) != bid:
        push_error("Grand-Place contiguous LoD2 building identity mismatch: %s" % bid)
        return false
    if str(source.get("package_sha256", "")) != PACKAGE_SHA256:
        push_error("Grand-Place contiguous LoD2 package digest drifted: %s" % bid)
        return false
    if str(source.get("crs", "")) != "EPSG:31370" or str(source.get("license", "")) != "CC0-1.0":
        push_error("Grand-Place contiguous LoD2 provenance drifted: %s" % bid)
        return false
    if bool(data.get("runtime_approved", true)):
        push_error("Grand-Place contiguous LoD2 source must remain evidence-only: %s" % bid)
        return false
    var evidence: Dictionary = data.get("evidence", {})
    if int(evidence.get("face_count", 0)) <= 0 or int(evidence.get("triangle_count", 0)) <= 0:
        push_error("Grand-Place contiguous LoD2 empty geometry: %s" % bid)
        return false
    return true

func _compact_building_id(value: String) -> String:
    return value.get_file()

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
        var face: Dictionary = raw_face
        for raw_triangle: Variant in face.get("triangles", []):
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
        var face: Dictionary = raw_face
        for raw_triangle: Variant in face.get("triangles", []):
            if typeof(raw_triangle) != TYPE_ARRAY:
                continue
            for raw_point: Variant in raw_triangle:
                var p := _point(raw_point)
                if p.is_finite():
                    sum += p
                    count += 1
    return sum / float(count) if count > 0 else Vector3.ZERO

func _materials() -> Dictionary:
    # These are deliberately neutral presentation values, not claims about the
    # exact stone/slate of any unnamed owner. Geometry/provenance are source truth.
    var wall := StandardMaterial3D.new()
    wall.albedo_color = Color(0.79, 0.76, 0.68, 1.0)
    wall.roughness = 0.78
    wall.cull_mode = BaseMaterial3D.CULL_BACK
    wall.set_meta("presentation_only", true)
    wall.set_meta("photometric_measurement", false)
    var roof := StandardMaterial3D.new()
    roof.albedo_color = Color(0.15, 0.16, 0.17, 1.0)
    roof.roughness = 0.9
    roof.cull_mode = BaseMaterial3D.CULL_BACK
    roof.set_meta("presentation_only", true)
    roof.set_meta("photometric_measurement", false)
    return {"WALLSURFACE": wall, "ROOFSURFACE": roof}

func _append_type(tool: SurfaceTool, faces: Array, face_type: String, center: Vector3) -> int:
    var count := 0
    for raw_face: Variant in faces:
        if typeof(raw_face) != TYPE_DICTIONARY:
            continue
        var face: Dictionary = raw_face
        if str(face.get("type", "")) != face_type:
            continue
        for raw_triangle: Variant in face.get("triangles", []):
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

func _build_surface(parent: Node3D, faces: Array, face_type: String, material: Material, center: Vector3, bid: String) -> int:
    var tool := SurfaceTool.new()
    tool.begin(Mesh.PRIMITIVE_TRIANGLES)
    tool.set_material(material)
    var count := _append_type(tool, faces, face_type, center)
    var mesh := tool.commit()
    if mesh == null or mesh.get_surface_count() == 0:
        return 0
    var instance := MeshInstance3D.new()
    instance.name = "%s_%s" % [bid, face_type]
    instance.mesh = mesh
    instance.set_meta("source_geometry_unchanged", true)
    parent.add_child(instance)
    if face_type == "WALLSURFACE":
        instance.create_trimesh_collision()
        for child: Node in instance.get_children():
            if child is CollisionObject3D:
                var collision := child as CollisionObject3D
                collision.collision_layer = 1
                collision.collision_mask = 1
                _official_collisions.append(collision)
    return count

func _build_building(parent: Node3D, faces: Array, bid: String) -> int:
    var mats := _materials()
    var center := _building_center(faces)
    var count := _build_surface(parent, faces, "WALLSURFACE", mats["WALLSURFACE"], center, bid)
    count += _build_surface(parent, faces, "ROOFSURFACE", mats["ROOFSURFACE"], center, bid)
    return count

func _mask_replaced_osm(bounds: Array[Rect2]) -> void:
    var main := get_tree().current_scene
    var generated := main.get_node_or_null("BrusselsOSM/GeneratedBuildings") if main != null else null
    if generated == null:
        return
    var seen := {}
    for child: Node in generated.get_children():
        if not child is Node3D:
            continue
        var node := child as Node3D
        var p := Vector2(node.global_position.x, node.global_position.z)
        var owned := false
        for rect: Rect2 in bounds:
            if rect.size.length_squared() > 0.001 and rect.grow(1.5).has_point(p):
                owned = true
                break
        if not owned or seen.has(node.get_instance_id()):
            continue
        seen[node.get_instance_id()] = true
        _masked_nodes.append(node)
        _masked_visibility.append(node.visible)
        _masked_collision.append((node as CSGShape3D).use_collision if node is CSGShape3D else false)
        node.visible = false
        node.set_meta("replaced_by_urbis_contiguous_front", true)
        if node is CSGShape3D:
            (node as CSGShape3D).use_collision = false
        masked_osm_count += 1

func set_front_visible(enabled: bool) -> void:
    _front_visible = enabled
    if _official_root != null:
        _official_root.visible = enabled
    for collision: CollisionObject3D in _official_collisions:
        if is_instance_valid(collision):
            collision.collision_layer = 1 if enabled else 0
            collision.collision_mask = 1 if enabled else 0
    for i: int in range(_masked_nodes.size()):
        var node := _masked_nodes[i]
        if not is_instance_valid(node):
            continue
        node.visible = false if enabled else _masked_visibility[i]
        if node is CSGShape3D:
            (node as CSGShape3D).use_collision = false if enabled else _masked_collision[i]

func front_visible() -> bool:
    return _front_visible
