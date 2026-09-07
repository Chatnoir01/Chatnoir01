extends Node3D

const SOURCE_DIR := "res://data/urbis/grand_place_lod2"
const PACKAGE_SHA256 := "cf8449d1a62b0e47aafe6d715ff6a2739f5c48f6d75995f7f418305a5d6cf3d2"
const DEDICATED_OWNER_IDS := {"1655673": true, "1786758": true}
const EXPECTED_OWNER_COUNT := 23
const EXPECTED_ALL_OWNER_COUNT := 25
const EXPECTED_ALL_FACE_COUNT := 715
const EXPECTED_ALL_TRIANGLE_COUNT := 2170
const EXPECTED_ZERO_SURFACE_COUNT := 9
const OSM_MASK_MARGIN_M := 3.0
const DEGENERATE_AREA2_EPSILON := 1.0e-12
const EXPECTED_ZERO_SURFACE_TRIANGLES := {
    "1601884|https://databrussels.be/id/buildingface/10910246|3": true,
    "1608847|https://databrussels.be/id/buildingface/10932426|5": true,
    "1608851|https://databrussels.be/id/buildingface/10787507|2": true,
    "1611166|https://databrussels.be/id/buildingface/10921163|4": true,
    "1611166|https://databrussels.be/id/buildingface/10921409|0": true,
    "1613517|https://databrussels.be/id/buildingface/10918081|2": true,
    "1613517|https://databrussels.be/id/buildingface/10918083|0": true,
    "1635455|https://databrussels.be/id/buildingface/10928302|0": true,
    "1645578|https://databrussels.be/id/buildingface/10797637|2": true,
}

var geometry_loaded := false
var loaded_owner_count := 0
var render_triangle_count := 0
var wall_collision_owner_count := 0
var masked_osm_count := 0
var _owner_bounds: Dictionary = {}
var _masked_nodes: Dictionary = {}
var _observed_zero_surface: Dictionary = {}
var _built := false
var _tree_watcher_connected := false
var _neutral_wall_material: StandardMaterial3D
var _neutral_roof_material: StandardMaterial3D

func _ready() -> void:
    _connect_late_osm_watcher()
    call_deferred("_build_when_scene_ready")

func _exit_tree() -> void:
    _restore_masked_osm_nodes()
    if _tree_watcher_connected and get_tree() != null and get_tree().node_added.is_connected(_on_tree_node_added):
        get_tree().node_added.disconnect(_on_tree_node_added)
    _tree_watcher_connected = false

func _connect_late_osm_watcher() -> void:
    if get_tree() == null or _tree_watcher_connected:
        return
    if not get_tree().node_added.is_connected(_on_tree_node_added):
        get_tree().node_added.connect(_on_tree_node_added)
    _tree_watcher_connected = true

func _restore_masked_osm_nodes() -> void:
    for snapshot_variant: Variant in _masked_nodes.values():
        if typeof(snapshot_variant) != TYPE_DICTIONARY:
            continue
        var snapshot: Dictionary = snapshot_variant
        var weak_node: WeakRef = snapshot.get("node") as WeakRef
        if weak_node == null:
            continue
        var restored_variant: Variant = weak_node.get_ref()
        if restored_variant == null or not is_instance_valid(restored_variant):
            continue
        var node := restored_variant as Node3D
        if node == null:
            continue
        var owner_id := str(snapshot.get("owner_id", ""))
        if str(node.get_meta("replaced_by_urbis_building", "")) != owner_id:
            continue
        node.visible = bool(snapshot.get("visible", true))
        if node is CSGShape3D and snapshot.has("use_collision"):
            (node as CSGShape3D).use_collision = bool(snapshot["use_collision"])
        if node is CollisionObject3D:
            var collision := node as CollisionObject3D
            collision.collision_layer = int(snapshot.get("collision_layer", collision.collision_layer))
            collision.collision_mask = int(snapshot.get("collision_mask", collision.collision_mask))
        if bool(snapshot.get("had_replacement_meta", false)):
            node.set_meta("replaced_by_urbis_building", snapshot.get("replacement_meta"))
        else:
            node.remove_meta("replaced_by_urbis_building")
    _masked_nodes.clear()
    masked_osm_count = 0

func _reset_partial_build_state() -> void:
    _restore_masked_osm_nodes()
    for child: Node in get_children():
        if child is Node3D and child.name.begins_with("GrandPlaceOfficial_"):
            remove_child(child)
            child.queue_free()
    geometry_loaded = false
    loaded_owner_count = 0
    render_triangle_count = 0
    wall_collision_owner_count = 0
    _owner_bounds.clear()
    _observed_zero_surface.clear()
    _built = false

func _build_when_scene_ready() -> void:
    if _built:
        return
    for _frame: int in range(8):
        await get_tree().process_frame
        var main := get_tree().current_scene
        if main != null and main.get_node_or_null("BrusselsOSM/GeneratedBuildings") != null:
            break
    _reset_partial_build_state()
    _ensure_materials()
    var files := _official_source_files()
    if files.size() != EXPECTED_ALL_OWNER_COUNT:
        push_error("Grand-Place official contour source-owner count drifted: %d" % files.size())
        _reset_partial_build_state()
        return
    var all_faces := 0
    var all_triangles := 0
    for file_name: String in files:
        var data := _read_owner(file_name)
        if data.is_empty():
            _reset_partial_build_state()
            return
        var evidence: Dictionary = data.get("evidence", {})
        all_faces += int(evidence.get("face_count", 0))
        all_triangles += int(evidence.get("triangle_count", 0))
        var owner_id := file_name.trim_suffix(".game.json")
        if DEDICATED_OWNER_IDS.has(owner_id):
            continue
        if not _build_owner(owner_id, data):
            push_error("Grand-Place official contour owner failed: %s" % owner_id)
            _reset_partial_build_state()
            return
    if all_faces != EXPECTED_ALL_FACE_COUNT or all_triangles != EXPECTED_ALL_TRIANGLE_COUNT:
        push_error("Grand-Place official contour aggregate source drifted: faces=%d triangles=%d" % [all_faces, all_triangles])
        _reset_partial_build_state()
        return
    if _observed_zero_surface.size() != EXPECTED_ZERO_SURFACE_COUNT:
        push_error("Grand-Place official contour zero-surface exclusion count drifted: %d" % _observed_zero_surface.size())
        _reset_partial_build_state()
        return
    for exclusion_key: String in EXPECTED_ZERO_SURFACE_TRIANGLES.keys():
        if not _observed_zero_surface.has(exclusion_key):
            push_error("Grand-Place official contour registered zero-surface triangle drifted: %s" % exclusion_key)
            _reset_partial_build_state()
            return
    if loaded_owner_count != EXPECTED_OWNER_COUNT or wall_collision_owner_count != EXPECTED_OWNER_COUNT:
        push_error("Grand-Place official contour incomplete: owners=%d collision_owners=%d" % [loaded_owner_count, wall_collision_owner_count])
        _reset_partial_build_state()
        return
    _built = true
    geometry_loaded = true
    set_meta("official_owner_count", loaded_owner_count)
    set_meta("official_source_owner_count", EXPECTED_ALL_OWNER_COUNT)
    set_meta("source_face_count", EXPECTED_ALL_FACE_COUNT)
    set_meta("source_triangle_count", EXPECTED_ALL_TRIANGLE_COUNT)
    set_meta("source_zero_surface_triangle_count", EXPECTED_ZERO_SURFACE_COUNT)
    set_meta("source_ground_surface_policy", "validated_source_not_mounted")
    set_meta("source_crs", "EPSG:31370")
    set_meta("source_license", "CC0-1.0")
    set_meta("source_package_sha256", PACKAGE_SHA256)
    set_meta("source_mutated", false)
    set_meta("runtime_approved", false)
    set_meta("visual_acceptance", false)
    set_meta("jouable_authorized", false)
    _rescan_generated_buildings()
    print("GRAND_PLACE_OFFICIAL_CONTOUR_READY: owners=%d collisions=%d source_triangles=%d excluded_zero_surface=%d render_triangles=%d ground_surface_policy=validated_source_not_mounted masked_osm=%d visual_acceptance=false jouable_authorized=false" % [loaded_owner_count, wall_collision_owner_count, EXPECTED_ALL_TRIANGLE_COUNT, EXPECTED_ZERO_SURFACE_COUNT, render_triangle_count, masked_osm_count])

func _official_source_files() -> PackedStringArray:
    var files := DirAccess.get_files_at(SOURCE_DIR)
    var filtered := PackedStringArray()
    for file_name: String in files:
        if file_name.ends_with(".game.json"):
            filtered.append(file_name)
    filtered.sort()
    return filtered

func _zero_surface_key(owner_id: String, face_id: String, triangle_index: int) -> String:
    return "%s|%s|%d" % [owner_id, face_id, triangle_index]

func _read_owner(file_name: String) -> Dictionary:
    var owner_id := file_name.trim_suffix(".game.json")
    var path := "%s/%s" % [SOURCE_DIR, file_name]
    if not FileAccess.file_exists(path):
        push_error("Grand-Place official contour source missing: %s" % path)
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    if typeof(parsed) != TYPE_DICTIONARY:
        push_error("Grand-Place official contour JSON invalid: %s" % owner_id)
        return {}
    var data: Dictionary = parsed
    var source: Dictionary = data.get("source", {})
    var evidence: Dictionary = data.get("evidence", {})
    if str(data.get("schema", "")) != "grand-bruxelles-urbis-context-mesh-v1":
        push_error("Grand-Place official contour schema mismatch: %s" % owner_id)
        return {}
    if str(source.get("building_2d_id", "")) != "https://databrussels.be/id/building/%s" % owner_id:
        push_error("Grand-Place official contour building identity mismatch: %s" % owner_id)
        return {}
    if str(source.get("crs", "")) != "EPSG:31370" or str(source.get("license", "")) != "CC0-1.0":
        push_error("Grand-Place official contour provenance drifted: %s" % owner_id)
        return {}
    if str(source.get("package_sha256", "")) != PACKAGE_SHA256:
        push_error("Grand-Place official contour package digest drifted: %s" % owner_id)
        return {}
    if bool(data.get("runtime_approved", true)):
        push_error("Grand-Place official contour source must remain non-approved: %s" % owner_id)
        return {}
    var faces: Array = data.get("faces", [])
    if int(evidence.get("face_count", -1)) != faces.size():
        push_error("Grand-Place official contour face count drifted: %s" % owner_id)
        return {}
    var actual_triangle_count := _validate_face_triangles(owner_id, faces)
    if actual_triangle_count < 0:
        return {}
    if int(evidence.get("triangle_count", -1)) != actual_triangle_count:
        push_error("Grand-Place official contour triangle count drifted: %s evidence=%d actual=%d" % [owner_id, int(evidence.get("triangle_count", -1)), actual_triangle_count])
        return {}
    return data

func _validate_face_triangles(owner_id: String, faces: Array) -> int:
    var count := 0
    for face_index: int in range(faces.size()):
        var raw_face: Variant = faces[face_index]
        if typeof(raw_face) != TYPE_DICTIONARY:
            push_error("Grand-Place official contour malformed face: %s face=%d" % [owner_id, face_index])
            return -1
        var face_id := str(raw_face.get("id", ""))
        var face_type := str(raw_face.get("type", ""))
        if face_type != "WALLSURFACE" and face_type != "ROOFSURFACE" and face_type != "GROUNDSURFACE":
            push_error("Grand-Place official contour unsupported face type: %s face=%d type=%s" % [owner_id, face_index, face_type])
            return -1
        var triangles: Variant = raw_face.get("triangles", [])
        if typeof(triangles) != TYPE_ARRAY:
            push_error("Grand-Place official contour malformed triangle list: %s face=%d" % [owner_id, face_index])
            return -1
        for triangle_index: int in range(triangles.size()):
            var triangle: Variant = triangles[triangle_index]
            if typeof(triangle) != TYPE_ARRAY or triangle.size() != 3:
                push_error("Grand-Place official contour malformed triangle: %s face=%d triangle=%d" % [owner_id, face_index, triangle_index])
                return -1
            for point_index: int in range(3):
                var point: Variant = triangle[point_index]
                if typeof(point) != TYPE_ARRAY or point.size() != 3:
                    push_error("Grand-Place official contour malformed point: %s face=%d triangle=%d point=%d" % [owner_id, face_index, triangle_index, point_index])
                    return -1
                for coordinate: Variant in point:
                    if typeof(coordinate) != TYPE_INT and typeof(coordinate) != TYPE_FLOAT:
                        push_error("Grand-Place official contour non-numeric point: %s face=%d triangle=%d point=%d" % [owner_id, face_index, triangle_index, point_index])
                        return -1
            var a := _point(triangle[0])
            var b := _point(triangle[1])
            var c := _point(triangle[2])
            if not a.is_finite() or not b.is_finite() or not c.is_finite():
                push_error("Grand-Place official contour non-finite triangle: %s face=%d triangle=%d" % [owner_id, face_index, triangle_index])
                return -1
            var exclusion_key := _zero_surface_key(owner_id, face_id, triangle_index)
            var is_zero_surface := (b - a).cross(c - a).length_squared() <= DEGENERATE_AREA2_EPSILON
            if is_zero_surface:
                if face_type != "WALLSURFACE" or not EXPECTED_ZERO_SURFACE_TRIANGLES.has(exclusion_key):
                    push_error("Grand-Place official contour unregistered zero-surface triangle: %s" % exclusion_key)
                    return -1
                if _observed_zero_surface.has(exclusion_key):
                    push_error("Grand-Place official contour duplicate zero-surface triangle identity: %s" % exclusion_key)
                    return -1
                _observed_zero_surface[exclusion_key] = true
            elif EXPECTED_ZERO_SURFACE_TRIANGLES.has(exclusion_key):
                push_error("Grand-Place official contour registered zero-surface triangle drifted: %s" % exclusion_key)
                return -1
            count += 1
    return count

func _ensure_materials() -> void:
    if _neutral_wall_material == null:
        _neutral_wall_material = StandardMaterial3D.new()
        _neutral_wall_material.albedo_color = Color(0.56, 0.54, 0.50, 1.0)
        _neutral_wall_material.roughness = 0.88
        _neutral_wall_material.cull_mode = BaseMaterial3D.CULL_BACK
    if _neutral_roof_material == null:
        _neutral_roof_material = StandardMaterial3D.new()
        _neutral_roof_material.albedo_color = Color(0.16, 0.17, 0.18, 1.0)
        _neutral_roof_material.roughness = 0.90
        _neutral_roof_material.cull_mode = BaseMaterial3D.CULL_BACK

func _build_owner(owner_id: String, data: Dictionary) -> bool:
    var faces: Array = data.get("faces", [])
    var center := _building_center(faces)
    var owner_root := Node3D.new()
    owner_root.name = "GrandPlaceOfficial_%s" % owner_id
    owner_root.set_meta("building_id", "https://databrussels.be/id/building/%s" % owner_id)
    owner_root.set_meta("runtime_approved", false)
    owner_root.set_meta("neutral_presentation_only", true)
    add_child(owner_root)
    var wall_triangles := _build_surface(owner_root, owner_id, faces, "WALLSURFACE", _neutral_wall_material, center, true)
    var roof_triangles := _build_surface(owner_root, owner_id, faces, "ROOFSURFACE", _neutral_roof_material, center, false)
    if wall_triangles <= 0:
        owner_root.queue_free()
        return false
    _owner_bounds[owner_id] = _horizontal_bounds(faces)
    loaded_owner_count += 1
    render_triangle_count += wall_triangles + roof_triangles
    wall_collision_owner_count += 1
    return true

func _point(raw: Variant) -> Vector3:
    if typeof(raw) != TYPE_ARRAY or raw.size() != 3:
        return Vector3.INF
    return Vector3(float(raw[0]), float(raw[1]), float(raw[2]))

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

func _append_faces(tool: SurfaceTool, owner_id: String, faces: Array, face_type: String, center: Vector3) -> int:
    var count := 0
    for raw_face: Variant in faces:
        if typeof(raw_face) != TYPE_DICTIONARY or str(raw_face.get("type", "")) != face_type:
            continue
        var face_id := str(raw_face.get("id", ""))
        var triangles: Array = raw_face.get("triangles", [])
        for triangle_index: int in range(triangles.size()):
            var raw_triangle: Variant = triangles[triangle_index]
            if typeof(raw_triangle) != TYPE_ARRAY or raw_triangle.size() != 3:
                return -1
            var a := _point(raw_triangle[0])
            var b := _point(raw_triangle[1])
            var c := _point(raw_triangle[2])
            if not a.is_finite() or not b.is_finite() or not c.is_finite():
                return -1
            var cross := (b - a).cross(c - a)
            if cross.length_squared() <= DEGENERATE_AREA2_EPSILON:
                var exclusion_key := _zero_surface_key(owner_id, face_id, triangle_index)
                if not EXPECTED_ZERO_SURFACE_TRIANGLES.has(exclusion_key):
                    push_error("Grand-Place official contour build encountered unregistered zero-surface triangle: %s" % exclusion_key)
                    return -1
                continue
            var normal := cross.normalized()
            if not normal.is_finite() or normal.length_squared() < 0.5:
                return -1
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

func _build_surface(owner_root: Node3D, owner_id: String, faces: Array, face_type: String, material: Material, center: Vector3, with_collision: bool) -> int:
    var tool := SurfaceTool.new()
    tool.begin(Mesh.PRIMITIVE_TRIANGLES)
    tool.set_material(material)
    var count := _append_faces(tool, owner_id, faces, face_type, center)
    if count <= 0:
        return count
    var mesh := tool.commit()
    if mesh == null or mesh.get_surface_count() == 0:
        return 0
    var instance := MeshInstance3D.new()
    instance.name = "%s_%s" % [owner_id, face_type]
    instance.mesh = mesh
    owner_root.add_child(instance)
    if with_collision:
        instance.create_trimesh_collision()
        for child: Node in instance.get_children():
            if child is CollisionObject3D:
                var collision := child as CollisionObject3D
                collision.collision_layer = 1
                collision.collision_mask = 1
                collision.set_meta("official_source_owner", owner_id)
    return count

func _on_tree_node_added(node: Node) -> void:
    if not is_instance_valid(node):
        return
    call_deferred("_consider_late_osm_node", node)

func _consider_late_osm_node(node: Node) -> void:
    if not is_instance_valid(node):
        return
    if node.name == "GeneratedBuildings":
        _rescan_generated_buildings()
        return
    if node is Node3D and _is_under_generated_buildings(node):
        _mask_osm_node_if_replaced(node as Node3D)

func _is_under_generated_buildings(node: Node) -> bool:
    var cursor: Node = node
    while cursor != null:
        if cursor.name == "GeneratedBuildings":
            return true
        cursor = cursor.get_parent()
    return false

func _rescan_generated_buildings() -> void:
    var main := get_tree().current_scene if get_tree() != null else null
    var buildings := main.get_node_or_null("BrusselsOSM/GeneratedBuildings") if main != null else null
    if buildings == null:
        return
    _scan_osm_descendants(buildings)

func _scan_osm_descendants(root: Node) -> void:
    for child: Node in root.get_children():
        if child is Node3D:
            _mask_osm_node_if_replaced(child as Node3D)
        _scan_osm_descendants(child)

func _mask_existing_osm_for_owner(_owner_id: String) -> void:
    var main := get_tree().current_scene if get_tree() != null else null
    var buildings := main.get_node_or_null("BrusselsOSM/GeneratedBuildings") if main != null else null
    if buildings == null:
        return
    _scan_osm_descendants(buildings)

func _mask_osm_node_if_replaced(node: Node3D) -> void:
    var instance_id := node.get_instance_id()
    if _masked_nodes.has(instance_id):
        return
    var xz := Vector2(node.global_position.x, node.global_position.z)
    for owner_id: String in _owner_bounds.keys():
        var bounds: Rect2 = _owner_bounds[owner_id]
        if bounds.size.length_squared() <= 0.001 or not bounds.grow(OSM_MASK_MARGIN_M).has_point(xz):
            continue
        var snapshot := {
            "node": weakref(node),
            "owner_id": owner_id,
            "visible": node.visible,
            "had_replacement_meta": node.has_meta("replaced_by_urbis_building"),
            "replacement_meta": node.get_meta("replaced_by_urbis_building") if node.has_meta("replaced_by_urbis_building") else null,
        }
        if node is CSGShape3D:
            snapshot["use_collision"] = (node as CSGShape3D).use_collision
        if node is CollisionObject3D:
            var collision := node as CollisionObject3D
            snapshot["collision_layer"] = collision.collision_layer
            snapshot["collision_mask"] = collision.collision_mask
        _masked_nodes[instance_id] = snapshot
        node.visible = false
        node.set_meta("replaced_by_urbis_building", owner_id)
        if node is CSGShape3D:
            (node as CSGShape3D).use_collision = false
        if node is CollisionObject3D:
            var collision := node as CollisionObject3D
            collision.collision_layer = 0
            collision.collision_mask = 0
        masked_osm_count += 1
        return
