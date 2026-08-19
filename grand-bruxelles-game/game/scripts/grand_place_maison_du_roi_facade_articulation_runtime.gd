extends Node3D

const GEOMETRY_PATH := "res://data/urbis/grand_place_lod2/1654360.game.json"
const CONTRACT_PATH := "res://data/qa/grand_place_maison_du_roi_facade_contract.json"
const OFFICIAL_AUTOLOAD := "GrandPlaceMaisonDuRoiOfficialLod2"
const CANONICAL_CAMERA := Vector3(319.01, 1.72, -535.20)
const LOWER_BAYS := 9
const UPPER_BAYS := 17
const RELIEF_DEPTH := 0.12

var built := false
var articulation_visible := true
var resolved_facade_width_m := 0.0
var resolved_facade_height_m := 0.0
var feature_count := 0
var front_normal := Vector3.ZERO
var front_tangent := Vector3.ZERO
var front_plane_point := Vector3.ZERO
var facade_min_u := 0.0
var facade_max_u := 0.0
var facade_min_y := 0.0
var facade_max_y := 0.0
var _feature_root: Node3D

func _ready() -> void:
    call_deferred("_build_when_ready")

func _build_when_ready() -> void:
    var official := get_tree().root.get_node_or_null(OFFICIAL_AUTOLOAD)
    for _frame: int in range(480):
        if official != null and bool(official.get("geometry_loaded")):
            break
        await get_tree().process_frame
        official = get_tree().root.get_node_or_null(OFFICIAL_AUTOLOAD)
    if official == null or not bool(official.get("geometry_loaded")):
        push_error("Maison du Roi articulation: official LoD2 runtime not ready")
        return
    var contract := _read_json(CONTRACT_PATH)
    var geometry := _read_json(GEOMETRY_PATH)
    if contract.is_empty() or geometry.is_empty():
        return
    if not _validate_contract(contract, geometry):
        return
    if not _resolve_main_facade(geometry):
        return
    _feature_root = Node3D.new()
    _feature_root.name = "MaisonDuRoiFacadeArticulation"
    add_child(_feature_root)
    _build_architectural_rhythm()
    if feature_count < 70:
        push_error("Maison du Roi articulation: feature contract too small: %d" % feature_count)
        _feature_root.queue_free()
        return
    built = true
    set_meta("building_id", "1654360")
    set_meta("source_record", "Urban Brussels 31143")
    set_meta("lower_bays", LOWER_BAYS)
    set_meta("upper_bays", UPPER_BAYS)
    set_meta("ground_lancets", 4)
    set_meta("upper_lancets", 2)
    set_meta("gallery_levels", 2)
    set_meta("axial_bay_wider", true)
    set_meta("source_geometry_changed", false)
    set_meta("source_collision_changed", false)
    set_meta("survey_dimensions_claimed", false)
    set_meta("exact_opening_coordinates_claimed", false)
    set_meta("runtime_approved", false)
    set_meta("realism_complete", false)
    print("MAISON_DU_ROI_FACADE_READY: width=%.3f height=%.3f features=%d source_geometry_changed=false" % [resolved_facade_width_m, resolved_facade_height_m, feature_count])

func _read_json(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        push_error("Maison du Roi articulation missing JSON: %s" % path)
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    if typeof(parsed) != TYPE_DICTIONARY:
        push_error("Maison du Roi articulation invalid JSON: %s" % path)
        return {}
    return parsed as Dictionary

func _validate_contract(contract: Dictionary, geometry: Dictionary) -> bool:
    if str(contract.get("schema", "")) != "grand-bruxelles-maison-du-roi-facade-v1":
        push_error("Maison du Roi articulation contract schema drifted")
        return false
    var official: Dictionary = contract.get("official_geometry", {})
    var source: Dictionary = geometry.get("source", {})
    var evidence: Dictionary = geometry.get("evidence", {})
    if str(source.get("building_2d_id", "")) != str(official.get("building_id", "")):
        push_error("Maison du Roi articulation building identity drifted")
        return false
    if str(source.get("package_sha256", "")) != str(official.get("package_sha256", "")):
        push_error("Maison du Roi articulation source package drifted")
        return false
    if int(evidence.get("face_count", 0)) != int(official.get("face_count", -1)):
        push_error("Maison du Roi articulation face count drifted")
        return false
    if int(evidence.get("triangle_count", 0)) != int(official.get("source_triangle_count", -1)):
        push_error("Maison du Roi articulation triangle count drifted")
        return false
    var facts: Dictionary = (contract.get("architectural_source", {}) as Dictionary).get("facts_used", {})
    if int(facts.get("lower_level_bays", 0)) != LOWER_BAYS or int(facts.get("upper_level_bays", 0)) != UPPER_BAYS:
        push_error("Maison du Roi articulation heritage rhythm drifted")
        return false
    return true

func _point(raw: Variant) -> Vector3:
    if typeof(raw) != TYPE_ARRAY or raw.size() != 3:
        return Vector3.INF
    return Vector3(float(raw[0]), float(raw[1]), float(raw[2]))

func _triangle(raw: Variant) -> Array[Vector3]:
    var out: Array[Vector3] = []
    if typeof(raw) != TYPE_ARRAY or raw.size() != 3:
        return out
    for value: Variant in raw:
        var p := _point(value)
        if not p.is_finite():
            return []
        out.append(p)
    return out

func _horizontal_normal(points: Array[Vector3], toward: Vector3) -> Vector3:
    if points.size() != 3:
        return Vector3.ZERO
    var n := (points[1] - points[0]).cross(points[2] - points[0])
    n.y = 0.0
    if n.length_squared() < 0.0001:
        return Vector3.ZERO
    n = n.normalized()
    var center := (points[0] + points[1] + points[2]) / 3.0
    var to_target := Vector3(toward.x - center.x, 0.0, toward.z - center.z)
    if to_target.length_squared() > 0.0001 and n.dot(to_target.normalized()) < 0.0:
        n = -n
    return n

func _triangle_area(points: Array[Vector3]) -> float:
    if points.size() != 3:
        return 0.0
    return 0.5 * (points[1] - points[0]).cross(points[2] - points[0]).length()

func _resolve_main_facade(geometry: Dictionary) -> bool:
    var best_score := 0.0
    var best_points: Array[Vector3] = []
    var best_normal := Vector3.ZERO
    var faces: Array = geometry.get("faces", [])
    for raw_face: Variant in faces:
        if typeof(raw_face) != TYPE_DICTIONARY or str(raw_face.get("type", "")) != "WALLSURFACE":
            continue
        for raw_tri: Variant in raw_face.get("triangles", []):
            var points := _triangle(raw_tri)
            if points.size() != 3:
                continue
            var n := _horizontal_normal(points, CANONICAL_CAMERA)
            if n.length_squared() < 0.5:
                continue
            var center := (points[0] + points[1] + points[2]) / 3.0
            var to_camera := Vector3(CANONICAL_CAMERA.x - center.x, 0.0, CANONICAL_CAMERA.z - center.z)
            if to_camera.length_squared() < 0.01:
                continue
            var facing := maxf(0.0, n.dot(to_camera.normalized()))
            var score := _triangle_area(points) * facing * facing
            if facing > 0.72 and score > best_score:
                best_score = score
                best_points = points
                best_normal = n
    if best_points.size() != 3:
        push_error("Maison du Roi articulation: no camera-facing official facade plane")
        return false
    front_normal = best_normal
    front_tangent = Vector3(-front_normal.z, 0.0, front_normal.x).normalized()
    front_plane_point = (best_points[0] + best_points[1] + best_points[2]) / 3.0
    var initialized := false
    for raw_face: Variant in faces:
        if typeof(raw_face) != TYPE_DICTIONARY or str(raw_face.get("type", "")) != "WALLSURFACE":
            continue
        for raw_tri: Variant in raw_face.get("triangles", []):
            var points := _triangle(raw_tri)
            if points.size() != 3:
                continue
            var n := _horizontal_normal(points, CANONICAL_CAMERA)
            if n.length_squared() < 0.5 or n.dot(front_normal) < 0.90:
                continue
            var center := (points[0] + points[1] + points[2]) / 3.0
            if absf((center - front_plane_point).dot(front_normal)) > 1.75:
                continue
            for p: Vector3 in points:
                var u := p.dot(front_tangent)
                if not initialized:
                    facade_min_u = u
                    facade_max_u = u
                    facade_min_y = p.y
                    facade_max_y = p.y
                    initialized = true
                else:
                    facade_min_u = minf(facade_min_u, u)
                    facade_max_u = maxf(facade_max_u, u)
                    facade_min_y = minf(facade_min_y, p.y)
                    facade_max_y = maxf(facade_max_y, p.y)
    if not initialized:
        push_error("Maison du Roi articulation: facade connected plane unresolved")
        return false
    resolved_facade_width_m = facade_max_u - facade_min_u
    resolved_facade_height_m = facade_max_y - facade_min_y
    if resolved_facade_width_m < 18.0 or resolved_facade_height_m < 15.0:
        push_error("Maison du Roi articulation: facade too small %.3fx%.3f" % [resolved_facade_width_m, resolved_facade_height_m])
        return false
    return true

func _material(color: Color, roughness: float) -> StandardMaterial3D:
    var mat := StandardMaterial3D.new()
    mat.albedo_color = color
    mat.roughness = roughness
    mat.cull_mode = BaseMaterial3D.CULL_DISABLED
    return mat

func _world(u: float, y: float, depth: float = RELIEF_DEPTH) -> Vector3:
    return front_plane_point + front_tangent * (u - front_plane_point.dot(front_tangent)) + Vector3.UP * (y - front_plane_point.y) + front_normal * depth

func _add_box(name_value: String, u: float, y: float, width: float, height: float, depth: float, mat: Material) -> void:
    var mesh := BoxMesh.new()
    mesh.size = Vector3(width, height, depth)
    var node := MeshInstance3D.new()
    node.name = name_value
    node.mesh = mesh
    node.material_override = mat
    node.position = _world(u, y, RELIEF_DEPTH + depth * 0.5)
    node.basis = Basis(front_tangent, Vector3.UP, front_normal)
    _feature_root.add_child(node)
    feature_count += 1

func _add_pointed_panel(name_value: String, center_u: float, bottom_y: float, width: float, height: float, mat: Material) -> void:
    var half := width * 0.5
    var shoulder_y := bottom_y + height * 0.76
    var apex_y := bottom_y + height
    var pts: Array[Vector3] = [
        _world(center_u - half, bottom_y),
        _world(center_u + half, bottom_y),
        _world(center_u + half, shoulder_y),
        _world(center_u, apex_y),
        _world(center_u - half, shoulder_y)
    ]
    var tool := SurfaceTool.new()
    tool.begin(Mesh.PRIMITIVE_TRIANGLES)
    tool.set_material(mat)
    for idx: int in [0, 1, 2, 0, 2, 3, 0, 3, 4]:
        tool.set_normal(front_normal)
        tool.add_vertex(pts[idx])
    var mesh := tool.commit()
    var node := MeshInstance3D.new()
    node.name = name_value
    node.mesh = mesh
    _feature_root.add_child(node)
    feature_count += 1

func _weighted_lower_bays(left: float, right: float) -> Array[Dictionary]:
    var weights: Array[float] = []
    for i: int in range(LOWER_BAYS):
        weights.append(1.35 if i == 4 else 1.0)
    var total := 0.0
    for weight: float in weights:
        total += weight
    var unit := (right - left) / total
    var cursor := left
    var out: Array[Dictionary] = []
    for i: int in range(LOWER_BAYS):
        var w := unit * weights[i]
        out.append({"center": cursor + w * 0.5, "width": w, "axial": i == 4})
        cursor += w
    return out

func _build_architectural_rhythm() -> void:
    var stone := _material(Color(0.80, 0.77, 0.69, 1.0), 0.90)
    var dark := _material(Color(0.10, 0.14, 0.16, 1.0), 0.78)
    var blue_stone := _material(Color(0.22, 0.25, 0.27, 1.0), 0.93)
    var left := facade_min_u + resolved_facade_width_m * 0.055
    var right := facade_max_u - resolved_facade_width_m * 0.055
    var base_y := facade_min_y + maxf(0.65, resolved_facade_height_m * 0.035)
    var usable_top := minf(facade_max_y - 0.8, base_y + resolved_facade_height_m * 0.78)
    var register_h := (usable_top - base_y) / 3.0
    if register_h < 3.2:
        push_error("Maison du Roi articulation: insufficient register height")
        return
    var lower_bays := _weighted_lower_bays(left, right)
    for register: int in range(2):
        var bottom := base_y + float(register) * register_h + register_h * 0.13
        var panel_h := register_h * 0.68
        for i: int in range(lower_bays.size()):
            var bay: Dictionary = lower_bays[i]
            var center := float(bay["center"])
            var bay_w := float(bay["width"])
            var lancets := 4 if register == 0 else 2
            var inner_w := bay_w * (0.72 if bool(bay["axial"]) else 0.66)
            var gap := inner_w * 0.055
            var lancet_w := (inner_w - gap * float(lancets - 1)) / float(lancets)
            var start := center - inner_w * 0.5 + lancet_w * 0.5
            for l: int in range(lancets):
                _add_pointed_panel("Lancet_%d_%d_%d" % [register, i, l], start + float(l) * (lancet_w + gap), bottom, lancet_w, panel_h, dark)
        var rail_y := base_y + float(register + 1) * register_h - register_h * 0.03
        _add_box("GalleryRail_%d" % register, (left + right) * 0.5, rail_y, right - left, 0.22, 0.16, stone)
        for bay: Dictionary in lower_bays:
            _add_box("GalleryPier_%d_%d" % [register, feature_count], float(bay["center"]), rail_y - register_h * 0.18, 0.20, register_h * 0.34, 0.16, stone)
    var upper_bottom := base_y + register_h * 2.0 + register_h * 0.11
    var upper_panel_h := register_h * 0.70
    var upper_unit := (right - left) / float(UPPER_BAYS)
    for i: int in range(UPPER_BAYS):
        var center := left + upper_unit * (float(i) + 0.5)
        var inner := upper_unit * (0.78 if i == 8 else 0.64)
        var gap := inner * 0.08
        var lancet_w := (inner - gap) * 0.5
        _add_pointed_panel("UpperLancet_%d_a" % i, center - (lancet_w + gap) * 0.5, upper_bottom, lancet_w, upper_panel_h, dark)
        _add_pointed_panel("UpperLancet_%d_b" % i, center + (lancet_w + gap) * 0.5, upper_bottom, lancet_w, upper_panel_h, dark)
    _add_box("BlueStonePlinth", (left + right) * 0.5, base_y - 0.16, right - left, 0.32, 0.18, blue_stone)
    var axial: Dictionary = lower_bays[4]
    _add_box("AxialEmphasisLeft", float(axial["center"]) - float(axial["width"]) * 0.42, base_y + register_h, 0.24, register_h * 1.85, 0.18, stone)
    _add_box("AxialEmphasisRight", float(axial["center"]) + float(axial["width"]) * 0.42, base_y + register_h, 0.24, register_h * 1.85, 0.18, stone)

func set_articulation_visible(enabled: bool) -> void:
    articulation_visible = enabled
    if _feature_root != null and is_instance_valid(_feature_root):
        _feature_root.visible = enabled

func is_articulation_visible() -> bool:
    return articulation_visible
