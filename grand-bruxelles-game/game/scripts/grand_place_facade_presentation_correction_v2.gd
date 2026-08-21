extends Node3D

const SOURCE_DIR := "res://data/urbis/grand_place_lod2"
const FACADE_NAME := "GrandPlaceFacadePresentationRuntime"
const CONTOUR_NAME := "GrandPlaceCompleteContourRuntime"
const PACKAGE_SHA256 := "cf8449d1a62b0e47aafe6d715ff6a2739f5c48f6d75995f7f418305a5d6cf3d2"
const CANONICAL_CAMERA := Vector3(319.01, 1.72, -535.20)
const MAISON_OWNER := "1654360"
const CORNET_OWNER := "1608847"
const RENARD_OWNER := "1608851"
const DETAIL_OFFSET := 0.055

var built := false
var failed := false
var correction_feature_count := 0
var _facade: Node = null
var _contour: Node = null
var _root: Node3D = null
var _maison_legacy_root: Node3D = null
var _cornet_roof: MeshInstance3D = null
var _cornet_roof_original: Material = null
var _cornet_roof_material: Material = null
var _last_visible := true

func _ready() -> void:
    set_process(false)
    call_deferred("_build_when_ready")

func _fail(message: String) -> void:
    failed = true
    push_error("Grand-Place facade correction V2: %s" % message)

func _build_when_ready() -> void:
    for _frame: int in range(900):
        _facade = get_tree().root.get_node_or_null(FACADE_NAME)
        _contour = get_tree().root.get_node_or_null(CONTOUR_NAME)
        if _facade != null and _contour != null and bool(_facade.get("built")) and bool(_contour.get("geometry_loaded")):
            break
        await get_tree().process_frame
    if _facade == null or _contour == null or not bool(_facade.get("built")) or not bool(_contour.get("geometry_loaded")):
        _fail("base facade/contour runtime not ready")
        return

    _maison_legacy_root = _facade.get_node_or_null("GrandPlaceFacadePresentationDetails/Facade_1654360_Maison_du_Roi") as Node3D
    if _maison_legacy_root == null:
        _fail("legacy Maison du Roi owner root missing")
        return
    _maison_legacy_root.visible = false

    var maison_frame := _resolve_facade(_read_owner(MAISON_OWNER))
    var cornet_frame := _resolve_facade(_read_owner(CORNET_OWNER))
    var renard_frame := _resolve_facade(_read_owner(RENARD_OWNER))
    if maison_frame.is_empty() or cornet_frame.is_empty() or renard_frame.is_empty():
        _fail("source-derived facade frame missing")
        return

    _root = Node3D.new()
    _root.name = "GrandPlaceFacadeCorrectionV2Details"
    add_child(_root)
    _build_maison_du_roi_grouped(_root, maison_frame)
    _build_cornet_crown(_root, cornet_frame)
    _build_renard_crown(_root, renard_frame)
    _apply_cornet_roof()

    if correction_feature_count < 100:
        _fail("correction feature accounting too small: %d" % correction_feature_count)
        return

    built = true
    set_meta("correction_revision", 2)
    set_meta("source_geometry_changed", false)
    set_meta("source_collision_changed", false)
    set_meta("camera_changed", false)
    set_meta("threshold_changed", false)
    set_meta("legacy_maison_grid_hidden", true)
    set_meta("maison_grouped_lancets", true)
    set_meta("cornet_roof_identity", "slate_and_tile_documented")
    set_meta("statuary_authored", false)
    set_meta("finished_perfect", false)
    _sync_visibility(true)
    set_process(true)
    print("GRAND_PLACE_FACADE_CORRECTION_V2_READY: features=%d geometry_changed=false collision_changed=false camera_changed=false threshold_changed=false" % correction_feature_count)

func _process(_delta: float) -> void:
    if not built or _facade == null:
        return
    var enabled := bool(_facade.get("presentation_visible"))
    if enabled != _last_visible:
        _sync_visibility(enabled)

func _sync_visibility(enabled: bool) -> void:
    _last_visible = enabled
    if _root != null and is_instance_valid(_root):
        _root.visible = enabled
    if _maison_legacy_root != null and is_instance_valid(_maison_legacy_root):
        _maison_legacy_root.visible = false
    if _cornet_roof != null and is_instance_valid(_cornet_roof):
        _cornet_roof.material_override = _cornet_roof_material if enabled else _cornet_roof_original
        _cornet_roof.set_meta("presentation_identity", "Le Cornet" if enabled else "neutral_unregistered")

func _read_json(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        _fail("missing JSON: %s" % path)
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    if typeof(parsed) != TYPE_DICTIONARY:
        _fail("invalid JSON: %s" % path)
        return {}
    return parsed as Dictionary

func _read_owner(owner_id: String) -> Dictionary:
    var data := _read_json(SOURCE_DIR.path_join("%s.game.json" % owner_id))
    if data.is_empty():
        return {}
    var source: Dictionary = data.get("source", {})
    if str(source.get("building_2d_id", "")) != "https://databrussels.be/id/building/%s" % owner_id:
        _fail("owner identity drifted: %s" % owner_id)
        return {}
    if str(source.get("package_sha256", "")) != PACKAGE_SHA256:
        _fail("source package drifted: %s" % owner_id)
        return {}
    return data

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

func _horizontal_normal(points: Array[Vector3]) -> Vector3:
    if points.size() != 3:
        return Vector3.ZERO
    var normal := (points[1] - points[0]).cross(points[2] - points[0])
    normal.y = 0.0
    if normal.length_squared() < 0.0001:
        return Vector3.ZERO
    normal = normal.normalized()
    var center := (points[0] + points[1] + points[2]) / 3.0
    var toward := Vector3(CANONICAL_CAMERA.x - center.x, 0.0, CANONICAL_CAMERA.z - center.z)
    if toward.length_squared() > 0.0001 and normal.dot(toward.normalized()) < 0.0:
        normal = -normal
    return normal

func _triangle_area(points: Array[Vector3]) -> float:
    if points.size() != 3:
        return 0.0
    return 0.5 * (points[1] - points[0]).cross(points[2] - points[0]).length()

func _resolve_facade(data: Dictionary) -> Dictionary:
    if data.is_empty():
        return {}
    var faces: Array = data.get("faces", [])
    var best_score := 0.0
    var best_points: Array[Vector3] = []
    var best_normal := Vector3.ZERO
    for raw_face: Variant in faces:
        if typeof(raw_face) != TYPE_DICTIONARY or str(raw_face.get("type", "")) != "WALLSURFACE":
            continue
        for raw_tri: Variant in raw_face.get("triangles", []):
            var points := _triangle(raw_tri)
            if points.size() != 3:
                continue
            var normal := _horizontal_normal(points)
            if normal.length_squared() < 0.5:
                continue
            var center := (points[0] + points[1] + points[2]) / 3.0
            var toward := Vector3(CANONICAL_CAMERA.x - center.x, 0.0, CANONICAL_CAMERA.z - center.z)
            if toward.length_squared() < 0.01:
                continue
            var facing := maxf(0.0, normal.dot(toward.normalized()))
            var score := _triangle_area(points) * facing * facing
            if facing > 0.55 and score > best_score:
                best_score = score
                best_points = points
                best_normal = normal
    if best_points.size() != 3:
        return {}
    var tangent := Vector3(-best_normal.z, 0.0, best_normal.x).normalized()
    var plane_point := (best_points[0] + best_points[1] + best_points[2]) / 3.0
    var initialized := false
    var min_u := 0.0
    var max_u := 0.0
    var min_y := 0.0
    var max_y := 0.0
    for raw_face: Variant in faces:
        if typeof(raw_face) != TYPE_DICTIONARY or str(raw_face.get("type", "")) != "WALLSURFACE":
            continue
        for raw_tri: Variant in raw_face.get("triangles", []):
            var points := _triangle(raw_tri)
            if points.size() != 3:
                continue
            var normal := _horizontal_normal(points)
            if normal.length_squared() < 0.5 or normal.dot(best_normal) < 0.88:
                continue
            var center := (points[0] + points[1] + points[2]) / 3.0
            if absf((center - plane_point).dot(best_normal)) > 2.0:
                continue
            for p: Vector3 in points:
                var u := p.dot(tangent)
                if not initialized:
                    min_u = u
                    max_u = u
                    min_y = p.y
                    max_y = p.y
                    initialized = true
                else:
                    min_u = minf(min_u, u)
                    max_u = maxf(max_u, u)
                    min_y = minf(min_y, p.y)
                    max_y = maxf(max_y, p.y)
    if not initialized or max_u - min_u < 3.0 or max_y - min_y < 8.0:
        return {}
    return {
        "normal": best_normal,
        "tangent": tangent,
        "plane_point": plane_point,
        "min_u": min_u,
        "max_u": max_u,
        "min_y": min_y,
        "max_y": max_y,
        "width": max_u - min_u,
        "height": max_y - min_y
    }

func _material(color: Color, roughness: float, source_label: String) -> StandardMaterial3D:
    var mat := StandardMaterial3D.new()
    mat.albedo_color = color
    mat.roughness = roughness
    mat.cull_mode = BaseMaterial3D.CULL_BACK
    mat.set_meta("source_label", source_label)
    mat.set_meta("authored_presentation_only", true)
    mat.set_meta("exact_rgb_is_photometric_measurement", false)
    return mat

func _world(frame: Dictionary, u: float, y: float, depth: float = DETAIL_OFFSET) -> Vector3:
    var tangent: Vector3 = frame["tangent"]
    var normal: Vector3 = frame["normal"]
    var point: Vector3 = frame["plane_point"]
    return point + tangent * (u - point.dot(tangent)) + Vector3.UP * (y - point.y) + normal * depth

func _add_box(parent: Node3D, frame: Dictionary, name_value: String, u: float, y: float, width: float, height: float, depth: float, mat: Material) -> MeshInstance3D:
    var mesh := BoxMesh.new()
    mesh.size = Vector3(maxf(width, 0.02), maxf(height, 0.02), maxf(depth, 0.02))
    var node := MeshInstance3D.new()
    node.name = name_value
    node.mesh = mesh
    node.material_override = mat
    node.position = _world(frame, u, y, DETAIL_OFFSET + depth * 0.5)
    node.basis = Basis(frame["tangent"], Vector3.UP, frame["normal"])
    node.set_meta("source_geometry", false)
    node.set_meta("presentation_dimension_surveyed", false)
    parent.add_child(node)
    correction_feature_count += 1
    return node

func _add_pointed_panel(parent: Node3D, frame: Dictionary, name_value: String, center_u: float, bottom_y: float, width: float, height: float, mat: Material) -> void:
    var half := width * 0.5
    var shoulder_y := bottom_y + height * 0.78
    var points: Array[Vector3] = [
        _world(frame, center_u - half, bottom_y, DETAIL_OFFSET + 0.010),
        _world(frame, center_u + half, bottom_y, DETAIL_OFFSET + 0.010),
        _world(frame, center_u + half, shoulder_y, DETAIL_OFFSET + 0.010),
        _world(frame, center_u, bottom_y + height, DETAIL_OFFSET + 0.010),
        _world(frame, center_u - half, shoulder_y, DETAIL_OFFSET + 0.010)
    ]
    var tool := SurfaceTool.new()
    tool.begin(Mesh.PRIMITIVE_TRIANGLES)
    tool.set_material(mat)
    for index: int in [0, 1, 2, 0, 2, 3, 0, 3, 4]:
        tool.set_normal(frame["normal"])
        tool.add_vertex(points[index])
    var node := MeshInstance3D.new()
    node.name = name_value
    node.mesh = tool.commit()
    node.set_meta("source_geometry", false)
    node.set_meta("presentation_dimension_surveyed", false)
    parent.add_child(node)
    correction_feature_count += 1

func _weighted_bays(left: float, right: float) -> Array[Dictionary]:
    var weights: Array[float] = []
    for index: int in range(9):
        weights.append(1.35 if index == 4 else 1.0)
    var total := 0.0
    for weight: float in weights:
        total += weight
    var unit := (right - left) / total
    var cursor := left
    var out: Array[Dictionary] = []
    for index: int in range(9):
        var width := unit * weights[index]
        out.append({"center": cursor + width * 0.5, "width": width, "axial": index == 4})
        cursor += width
    return out

func _build_maison_du_roi_grouped(parent: Node3D, frame: Dictionary) -> void:
    var maison_root := Node3D.new()
    maison_root.name = "MaisonDuRoiGroupedLancetsV2"
    maison_root.set_meta("source_record", "Urban Brussels 31143")
    maison_root.set_meta("bay_rhythm", "9_9_17")
    maison_root.set_meta("ground_lancets_per_bay", 4)
    maison_root.set_meta("upper_lancets_per_bay", 2)
    maison_root.set_meta("grouped_opening_method", true)
    maison_root.set_meta("exact_opening_dimensions_claimed", false)
    parent.add_child(maison_root)

    var dark := _material(Color(0.055, 0.065, 0.075, 1.0), 0.66, "authored glazing presentation; no photometric claim")
    var stone := _material(Color(0.66, 0.63, 0.56, 1.0), 0.86, "Urban 31143: Gobertange stone component; exact RGB authored")
    var blue := _material(Color(0.20, 0.23, 0.25, 1.0), 0.92, "Urban 31143: blue-stone component; exact RGB authored")

    var left := float(frame["min_u"]) + float(frame["width"]) * 0.055
    var right := float(frame["max_u"]) - float(frame["width"]) * 0.055
    var base_y := float(frame["min_y"]) + maxf(0.65, float(frame["height"]) * 0.035)
    var usable_top := minf(float(frame["max_y"]) - 0.8, base_y + float(frame["height"]) * 0.78)
    var register_h := (usable_top - base_y) / 3.0
    var lower := _weighted_bays(left, right)

    for register: int in range(2):
        var bottom := base_y + float(register) * register_h + register_h * 0.16
        var panel_h := register_h * 0.58
        for index: int in range(lower.size()):
            var bay: Dictionary = lower[index]
            var center := float(bay["center"])
            var bay_width := float(bay["width"])
            var panel_width := bay_width * (0.72 if bool(bay["axial"]) else 0.64)
            _add_pointed_panel(maison_root, frame, "GroupedBay_%d_%02d" % [register, index], center, bottom, panel_width, panel_h, dark)
            var mullions := 3 if register == 0 else 1
            for mullion: int in range(mullions):
                var fraction := float(mullion + 1) / float(mullions + 1)
                var u := center - panel_width * 0.5 + panel_width * fraction
                _add_box(maison_root, frame, "GroupedBay_%d_%02d_Mullion_%d" % [register, index, mullion], u, bottom + panel_h * 0.40, 0.085, panel_h * 0.72, 0.045, stone)
        var rail_y := base_y + float(register + 1) * register_h - register_h * 0.045
        _add_box(maison_root, frame, "GalleryRail_%d" % register, (left + right) * 0.5, rail_y, right - left, 0.10, 0.075, stone)
        for boundary: int in range(10):
            var boundary_u := left + (right - left) * float(boundary) / 9.0
            _add_box(maison_root, frame, "GalleryPier_%d_%02d" % [register, boundary], boundary_u, rail_y - register_h * 0.16, 0.105, register_h * 0.28, 0.075, stone)

    var upper_bottom := base_y + register_h * 2.0 + register_h * 0.18
    var upper_panel_h := register_h * 0.54
    var upper_unit := (right - left) / 17.0
    for index: int in range(17):
        var center := left + upper_unit * (float(index) + 0.5)
        var panel_width := upper_unit * (0.72 if index == 8 else 0.58)
        _add_pointed_panel(maison_root, frame, "UpperGroupedBay_%02d" % index, center, upper_bottom, panel_width, upper_panel_h, dark)
        _add_box(maison_root, frame, "UpperGroupedBay_%02d_Mullion" % index, center, upper_bottom + upper_panel_h * 0.40, 0.065, upper_panel_h * 0.70, 0.040, stone)

    var axial: Dictionary = lower[4]
    _add_box(maison_root, frame, "AxialLeft", float(axial["center"]) - float(axial["width"]) * 0.44, base_y + register_h, 0.14, register_h * 1.72, 0.085, stone)
    _add_box(maison_root, frame, "AxialRight", float(axial["center"]) + float(axial["width"]) * 0.44, base_y + register_h, 0.14, register_h * 1.72, 0.085, stone)
    _add_box(maison_root, frame, "BlueStonePlinth", (left + right) * 0.5, base_y - 0.12, right - left, 0.24, 0.10, blue)

func _build_cornet_crown(parent: Node3D, frame: Dictionary) -> void:
    var root := Node3D.new()
    root.name = "CornetCrownV2"
    root.set_meta("source_record", "Urban Brussels 31123")
    root.set_meta("roof_balustrade_documented", true)
    root.set_meta("ship_stern_crown_documented", true)
    root.set_meta("exact_dimensions_claimed", false)
    parent.add_child(root)
    var stone := _material(Color(0.73, 0.70, 0.64, 1.0), 0.86, "Urban 31123: Gobertange/Euville restoration; exact RGB authored")
    var width := float(frame["width"])
    var center := (float(frame["min_u"]) + float(frame["max_u"])) * 0.5
    var rail_y := float(frame["min_y"]) + float(frame["height"]) * 0.82
    _add_box(root, frame, "RoofBalustradeRail", center, rail_y, width * 0.94, 0.12, 0.075, stone)
    for index: int in range(9):
        var u := float(frame["min_u"]) + width * (0.07 + 0.86 * float(index) / 8.0)
        _add_box(root, frame, "RoofBaluster_%02d" % index, u, rail_y + float(frame["height"]) * 0.028, 0.075, maxf(0.34, float(frame["height"]) * 0.055), 0.060, stone)

func _build_renard_crown(parent: Node3D, frame: Dictionary) -> void:
    var root := Node3D.new()
    root.name = "RenardCrownV2"
    root.set_meta("source_record", "Urban Brussels 31124")
    root.set_meta("profiled_cornice_documented", true)
    root.set_meta("curved_pediment_documented", true)
    root.set_meta("exact_dimensions_claimed", false)
    parent.add_child(root)
    var stone := _material(Color(0.70, 0.68, 0.63, 1.0), 0.86, "Urban 31124: white-stone facade; exact RGB authored")
    var dark := _material(Color(0.055, 0.065, 0.075, 1.0), 0.66, "authored gable-window presentation; no photometric claim")
    var width := float(frame["width"])
    var center := (float(frame["min_u"]) + float(frame["max_u"])) * 0.5
    var crown_y := float(frame["min_y"]) + float(frame["height"]) * 0.76
    _add_box(root, frame, "ProfiledCorniceCue", center, crown_y, width * 0.94, 0.14, 0.075, stone)
    _add_box(root, frame, "AxialGableWindowCue", center, float(frame["min_y"]) + float(frame["height"]) * 0.835, width * 0.24, maxf(0.52, float(frame["height"]) * 0.065), 0.055, dark)
    _add_box(root, frame, "PedimentShoulderLeft", center - width * 0.33, crown_y + float(frame["height"]) * 0.045, width * 0.18, 0.11, 0.075, stone)
    _add_box(root, frame, "PedimentShoulderRight", center + width * 0.33, crown_y + float(frame["height"]) * 0.045, width * 0.18, 0.11, 0.075, stone)

func _apply_cornet_roof() -> void:
    _cornet_roof = _contour.get_node_or_null("GrandPlaceContour_1608847_ROOFSURFACE") as MeshInstance3D
    if _cornet_roof == null:
        _fail("Cornet official roof mesh missing")
        return
    _cornet_roof_original = _cornet_roof.material_override
    _cornet_roof_material = _material(Color(0.18, 0.20, 0.22, 1.0), 0.92, "Urban 31123: mansard plus adjoining gable roofs covered with slate and tile; one broad presentation family, exact RGB authored")
    _cornet_roof_material.set_meta("slate_tile_mix_not_spatially_resolved", true)
    _cornet_roof.material_override = _cornet_roof_material
    _cornet_roof.set_meta("presentation_identity", "Le Cornet")
    _cornet_roof.set_meta("source_geometry_unchanged", true)

func collision_object_count() -> int:
    if _root == null:
        return 0
    var count := 0
    var stack: Array[Node] = [_root]
    while not stack.is_empty():
        var node: Node = stack.pop_back()
        if node is CollisionObject3D:
            count += 1
        for child: Node in node.get_children():
            stack.append(child)
    return count
