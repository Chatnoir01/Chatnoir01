extends Node3D

const GEOMETRY_PATH := "res://data/urbis/grand_place_lod2/1654360.game.json"
const BUILDING_ID := "https://databrussels.be/id/building/1654360"
const SOURCE_ID := "https://databrussels.be/id/building/1654360"
const SOURCE_PACKAGE := "grand_place_lod2_v1"
const SOURCE_PACKAGE_SHA := "cf8449d1a62b0e47aafe6d715ff6a2739f5c48f6d75995f7f418305a5d6cf3d2"
const SOURCE_FACE_COUNT := 71
const SOURCE_TRIANGLE_COUNT := 230
const SOURCE_HEIGHT_M := 30.387
const FACADE_BAYS := 9
const FACADE_LEVELS := 3
const SOURCE_EXPLICIT_BAY_COUNT := 9
const SOURCE_EXPLICIT_LEVEL_COUNT := 3
const DECORATIVE_ORNAMENT_AUTHORED := false
const OPENING_DIMENSIONS_SOURCE_EXPLICIT := false
const GOTHIC_VERTICAL_READ_FROM_SOURCE := true
const RUNTIME_GEOMETRY_RESCALED := false
const HEIGHT_PROVENANCE := "official_urbis_lod2"
const FRONT_TO_SQUARE := Vector3(-1.0, 0.0, 1.0).normalized()
const PRESENTATION_DEPTH := 0.16

var geometry_loaded := false
var render_triangle_count := 0
var articulation_piece_count := 0
var masked_osm_count := 0
var _official_root: Node3D
var _articulation_root: Node3D

func _ready() -> void:
    call_deferred("_build_when_ready")

func _build_when_ready() -> void:
    for _frame: int in range(8):
        await get_tree().process_frame
    var data := _read_geometry()
    if data.is_empty():
        return
    var faces: Array = data.get("faces", [])
    _official_root = Node3D.new()
    _official_root.name = "OfficialUrbIS1654360"
    add_child(_official_root)
    _build_official_geometry(faces)
    _mask_replaced_osm(_horizontal_bounds(faces))
    _articulation_root = Node3D.new()
    _articulation_root.name = "SourceBoundedFacadeArticulation"
    add_child(_articulation_root)
    _build_source_bounded_frontage(faces)
    geometry_loaded = true
    set_meta("building_id", BUILDING_ID)
    set_meta("source_package", SOURCE_PACKAGE)
    set_meta("source_bounded_visualization_not_architectural_survey", true)
    set_meta("ornament_authored", false)
    set_meta("geometry_rescaled", false)
    set_meta("vertical_completeness", false)
    set_meta("opening_dimensions_source_explicit", false)
    set_meta("facade_bays_source_explicit", SOURCE_EXPLICIT_BAY_COUNT)
    set_meta("facade_levels_source_explicit", SOURCE_EXPLICIT_LEVEL_COUNT)
    set_meta("height_provenance", HEIGHT_PROVENANCE)
    set_meta("runtime_approved", false)
    set_meta("realism_complete", false)
    print("GRAND_PLACE_MAISON_ROI_ARTICULATION_READY: triangles=%d pieces=%d masked_osm=%d bays=%d levels=%d" % [render_triangle_count, articulation_piece_count, masked_osm_count, FACADE_BAYS, FACADE_LEVELS])

func _read_geometry() -> Dictionary:
    if not FileAccess.file_exists(GEOMETRY_PATH):
        push_error("Maison du Roi official geometry missing")
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(GEOMETRY_PATH))
    if typeof(parsed) != TYPE_DICTIONARY:
        push_error("Maison du Roi official geometry invalid")
        return {}
    var data := parsed as Dictionary
    var source := data.get("source", {}) as Dictionary
    var evidence := data.get("evidence", {}) as Dictionary
    var contract := data.get("source_contract", {}) as Dictionary
    if str(data.get("schema", "")) != "grand-bruxelles-urbis-context-mesh-v1":
        return {}
    if str(source.get("building_2d_id", "")) != BUILDING_ID:
        return {}
    if str(source.get("package_sha256", "")) != SOURCE_PACKAGE_SHA:
        return {}
    if str(source.get("crs", "")) != "EPSG:31370" or str(source.get("license", "")) != "CC0-1.0":
        return {}
    if int(evidence.get("face_count", 0)) != SOURCE_FACE_COUNT or int(evidence.get("triangle_count", 0)) != SOURCE_TRIANGLE_COUNT:
        return {}
    if absf(float(evidence.get("height_m", 0.0)) - SOURCE_HEIGHT_M) > 0.001:
        return {}
    if bool(contract.get("geometry_rescaled", true)):
        return {}
    if str(contract.get("vertical_completion", "")) != "incomplete":
        return {}
    if str(contract.get("height_provenance", "")) != HEIGHT_PROVENANCE:
        return {}
    return data

func _point(raw: Variant) -> Vector3:
    if typeof(raw) != TYPE_ARRAY or raw.size() != 3:
        return Vector3.INF
    return Vector3(float(raw[0]), float(raw[1]), float(raw[2]))

func _materials() -> Dictionary:
    var brick := StandardMaterial3D.new()
    brick.albedo_color = Color(0.43, 0.26, 0.18, 1.0)
    brick.roughness = 0.92
    var slate := StandardMaterial3D.new()
    slate.albedo_color = Color(0.10, 0.12, 0.14, 1.0)
    slate.roughness = 0.88
    var ground := StandardMaterial3D.new()
    ground.albedo_color = Color(0.20, 0.20, 0.19, 1.0)
    ground.roughness = 0.95
    return {"WALLSURFACE": brick, "ROOFSURFACE": slate, "GROUNDSURFACE": ground}

func _build_official_geometry(faces: Array) -> void:
    var mats := _materials()
    var center := _building_center(faces)
    for face_type: String in ["WALLSURFACE", "ROOFSURFACE", "GROUNDSURFACE"]:
        var tool := SurfaceTool.new()
        tool.begin(Mesh.PRIMITIVE_TRIANGLES)
        tool.set_material(mats[face_type])
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
                if not normal.is_finite():
                    continue
                var tri_center := (a + b + c) / 3.0
                var flip := false
                if face_type == "ROOFSURFACE":
                    flip = normal.y < 0.0
                elif face_type == "WALLSURFACE":
                    var outward := Vector3(tri_center.x - center.x, 0.0, tri_center.z - center.z)
                    var hn := Vector3(normal.x, 0.0, normal.z)
                    if outward.length_squared() > 0.001 and hn.length_squared() > 0.001:
                        flip = hn.dot(outward) < 0.0
                if flip:
                    var swap := b
                    b = c
                    c = swap
                    normal = -normal
                for p: Vector3 in [a, b, c]:
                    tool.set_normal(normal)
                    tool.add_vertex(p)
                count += 1
        var mesh := tool.commit()
        if mesh != null and mesh.get_surface_count() > 0:
            var instance := MeshInstance3D.new()
            instance.name = "MaisonDuRoi_%s" % face_type
            instance.mesh = mesh
            _official_root.add_child(instance)
            render_triangle_count += count

func _building_center(faces: Array) -> Vector3:
    var total := Vector3.ZERO
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
                    total += p
                    count += 1
    return total / float(count) if count > 0 else Vector3.ZERO

func _horizontal_bounds(faces: Array) -> Rect2:
    var first := true
    var lo := Vector2.ZERO
    var hi := Vector2.ZERO
    for raw_face: Variant in faces:
        if typeof(raw_face) != TYPE_DICTIONARY:
            continue
        for raw_triangle: Variant in raw_face.get("triangles", []):
            for raw_point: Variant in raw_triangle:
                var p := _point(raw_point)
                if not p.is_finite():
                    continue
                var xz := Vector2(p.x, p.z)
                if first:
                    lo = xz; hi = xz; first = false
                else:
                    lo.x = minf(lo.x, xz.x); lo.y = minf(lo.y, xz.y)
                    hi.x = maxf(hi.x, xz.x); hi.y = maxf(hi.y, xz.y)
    return Rect2(lo, hi - lo) if not first else Rect2()

func _frontage_points(faces: Array) -> Array[Vector3]:
    var points: Array[Vector3] = []
    for raw_face: Variant in faces:
        if typeof(raw_face) != TYPE_DICTIONARY or str(raw_face.get("type", "")) != "WALLSURFACE":
            continue
        for raw_triangle: Variant in raw_face.get("triangles", []):
            if typeof(raw_triangle) != TYPE_ARRAY or raw_triangle.size() != 3:
                continue
            var a := _point(raw_triangle[0]); var b := _point(raw_triangle[1]); var c := _point(raw_triangle[2])
            if not a.is_finite() or not b.is_finite() or not c.is_finite():
                continue
            var n := (b-a).cross(c-a).normalized()
            var hn := Vector3(n.x, 0.0, n.z)
            if hn.length_squared() < 0.1:
                continue
            hn = hn.normalized()
            if absf(hn.dot(FRONT_TO_SQUARE)) >= 0.62:
                points.append(a); points.append(b); points.append(c)
    return points

func _build_source_bounded_frontage(faces: Array) -> void:
    var points := _frontage_points(faces)
    if points.size() < 9:
        push_error("Maison du Roi frontage selection insufficient")
        return
    var tangent := Vector3(FRONT_TO_SQUARE.z, 0.0, -FRONT_TO_SQUARE.x).normalized()
    var min_u := INF; var max_u := -INF; var min_y := INF; var max_y := -INF
    var plane_d := 0.0
    for p: Vector3 in points:
        var u := p.dot(tangent)
        min_u = minf(min_u, u); max_u = maxf(max_u, u)
        min_y = minf(min_y, p.y); max_y = maxf(max_y, p.y)
        plane_d += p.dot(FRONT_TO_SQUARE)
    plane_d /= float(points.size())
    var facade_height := minf(max_y - min_y, 21.0)
    var facade_width := max_u - min_u
    if facade_width < 12.0 or facade_height < 9.0:
        push_error("Maison du Roi frontage bounds implausible")
        return
    var stone := StandardMaterial3D.new()
    stone.albedo_color = Color(0.68, 0.67, 0.60, 1.0)
    stone.roughness = 0.84
    var glass := StandardMaterial3D.new()
    glass.albedo_color = Color(0.055, 0.075, 0.085, 1.0)
    glass.roughness = 0.32
    var bay_w := facade_width / float(FACADE_BAYS)
    var level_h := facade_height / float(FACADE_LEVELS)
    for i: int in range(FACADE_BAYS + 1):
        var u := min_u + bay_w * float(i)
        _add_front_box("VerticalRhythm_%02d" % i, u, min_y + facade_height * 0.5, 0.18, facade_height, plane_d + 0.05, tangent, stone)
    for level: int in range(1, FACADE_LEVELS):
        _add_front_box("LevelBand_%02d" % level, (min_u + max_u) * 0.5, min_y + level_h * float(level), facade_width, 0.16, plane_d + 0.06, tangent, stone)
    for bay: int in range(FACADE_BAYS):
        for level: int in range(FACADE_LEVELS):
            var u := min_u + bay_w * (float(bay) + 0.5)
            var y := min_y + level_h * (float(level) + 0.53)
            _add_front_box("Bay_%02d_Level_%02d" % [bay, level], u, y, bay_w * 0.58, level_h * 0.52, plane_d + 0.035, tangent, glass)

func _add_front_box(node_name: String, u: float, y: float, width: float, height: float, plane_d: float, tangent: Vector3, material: Material) -> void:
    var mesh := BoxMesh.new()
    mesh.size = Vector3(width, height, PRESENTATION_DEPTH)
    mesh.material = material
    var instance := MeshInstance3D.new()
    instance.name = node_name
    instance.mesh = mesh
    var center := tangent * u + FRONT_TO_SQUARE * plane_d + Vector3.UP * y
    instance.position = center
    instance.rotation.y = atan2(FRONT_TO_SQUARE.x, FRONT_TO_SQUARE.z)
    _articulation_root.add_child(instance)
    articulation_piece_count += 1

func _mask_replaced_osm(bounds: Rect2) -> void:
    var main := get_tree().current_scene
    var buildings := main.get_node_or_null("BrusselsOSM/GeneratedBuildings") if main != null else null
    if buildings == null:
        return
    var expanded := bounds.grow(3.0)
    for child: Node in buildings.get_children():
        if child is Node3D:
            var node := child as Node3D
            if expanded.has_point(Vector2(node.global_position.x, node.global_position.z)):
                node.visible = false
                node.set_meta("replaced_by_urbis_building", "1654360")
                masked_osm_count += 1

func set_candidate_visible(enabled: bool) -> void:
    if _official_root != null:
        _official_root.visible = enabled
    if _articulation_root != null:
        _articulation_root.visible = enabled

func candidate_visible() -> bool:
    return _official_root != null and _official_root.visible
