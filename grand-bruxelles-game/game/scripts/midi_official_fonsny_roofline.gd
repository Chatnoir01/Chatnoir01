extends Node3D

# Source-bounded replacement for the authored long Fonsny roofline placeholder.
# Selection uses the existing hand-built StationRoofLine footprint only as a
# replacement mask. It is not promoted to source truth. Every rendered face is
# a complete UrbIS ROOFSURFACE face with original source triangles/vertices.
const GEOMETRY_PATH := "res://data/urbis/midi_lod2/1633645.game.json"
const BUILDING_ID := "https://databrussels.be/id/building/1633645"
const PACKAGE_SHA256 := "a760fdff222ae9431113f82fe1c8f942a9fe2bda40e32064c627ae8d3a21110f"
const EXPECTED_FACE_COUNT := 889
const EXPECTED_TRIANGLE_COUNT := 3428
const EXPECTED_HEIGHT_M := 13.6076

const MIDI := Vector3(-668.5, 0.0, 627.84)
const FONSNY_AXIS := Vector3(-0.627, 0.0, 0.779)
const STATION_SIDE := Vector3(-0.779, 0.0, -0.627)
# Exact current authored StationRoofLine footprint from midi_hero_zone.gd.
const PLACEHOLDER_CENTER_X := 0.0
const PLACEHOLDER_SIZE_X := 48.0
const PLACEHOLDER_CENTER_Z := 0.0
const PLACEHOLDER_SIZE_Z := 176.0

var geometry_loaded := false
var selected_face_count := 0
var render_triangle_count := 0
var selected_face_ids: Array[String] = []
var selected_bounds := Rect2()
var _mesh_instance: MeshInstance3D
var _placeholder: Node3D
var _official_visible := true

func _ready() -> void:
    call_deferred("_build_when_scene_ready")

func _build_when_scene_ready() -> void:
    for _frame: int in range(16):
        await get_tree().process_frame
        if _find_station() != null:
            break
    var station := _find_station()
    if station == null:
        push_error("Midi official Fonsny roofline: authored station missing")
        return
    _placeholder = station.get_node_or_null("StationRoofLine") as Node3D
    if _placeholder == null:
        push_error("Midi official Fonsny roofline: StationRoofLine placeholder missing")
        return

    var data := _read_geometry()
    if data.is_empty():
        return
    var faces: Array = data.get("faces", [])
    var selected := _select_complete_roof_faces(faces)
    selected_face_count = selected.size()
    if selected_face_count == 0:
        push_error("Midi official Fonsny roofline: no complete UrbIS roof face falls inside placeholder footprint")
        return
    selected_bounds = _horizontal_bounds(selected)
    render_triangle_count = _build_surface(selected)
    if render_triangle_count <= 0:
        push_error("Midi official Fonsny roofline: selected source faces produced no triangles")
        return

    geometry_loaded = true
    set_meta("building_id", BUILDING_ID)
    set_meta("package_sha256", PACKAGE_SHA256)
    set_meta("source_geometry_exact", true)
    set_meta("source_vertices_moved", false)
    set_meta("source_faces_clipped", false)
    set_meta("source_triangles_replaced", false)
    set_meta("selection_boundary_is_authored_placeholder_only", true)
    set_meta("selection_claims_authoritative_roofline_dimensions", false)
    set_meta("neutral_presentation", true)
    set_meta("runtime_approved", false)
    set_meta("realism_complete", false)
    set_official_visible(true)
    print("MIDI_OFFICIAL_FONSNY_ROOFLINE_READY: faces=%d triangles=%d ids=%s bounds=(%.2f,%.2f)" % [selected_face_count, render_triangle_count, str(selected_face_ids), selected_bounds.size.x, selected_bounds.size.y])

func _find_station() -> Node3D:
    var main := get_tree().current_scene
    if main == null:
        return null
    return main.get_node_or_null("MidiHeroZone/BruxellesMidiStation") as Node3D

func _read_geometry() -> Dictionary:
    if not FileAccess.file_exists(GEOMETRY_PATH):
        push_error("Midi official Fonsny roofline: geometry missing")
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(GEOMETRY_PATH))
    if typeof(parsed) != TYPE_DICTIONARY:
        push_error("Midi official Fonsny roofline: invalid geometry JSON")
        return {}
    var data: Dictionary = parsed
    var source: Dictionary = data.get("source", {})
    var evidence: Dictionary = data.get("evidence", {})
    if str(data.get("schema", "")) != "grand-bruxelles-urbis-hero-mesh-v1":
        push_error("Midi official Fonsny roofline: schema drift")
        return {}
    if str(source.get("building_2d_id", "")) != BUILDING_ID:
        push_error("Midi official Fonsny roofline: building identity drift")
        return {}
    if str(source.get("package_sha256", "")) != PACKAGE_SHA256 or str(source.get("crs", "")) != "EPSG:31370" or str(source.get("license", "")) != "CC0-1.0":
        push_error("Midi official Fonsny roofline: provenance drift")
        return {}
    if int(evidence.get("face_count", 0)) != EXPECTED_FACE_COUNT or int(evidence.get("triangle_count", 0)) != EXPECTED_TRIANGLE_COUNT:
        push_error("Midi official Fonsny roofline: source count drift")
        return {}
    if int((evidence.get("face_type_counts", {}) as Dictionary).get("ROOFSURFACE", 0)) != 34:
        push_error("Midi official Fonsny roofline: roof face count drift")
        return {}
    if absf(float(evidence.get("height_m", 0.0)) - EXPECTED_HEIGHT_M) > 0.0001:
        push_error("Midi official Fonsny roofline: source height drift")
        return {}
    return data

func _point(raw: Variant) -> Vector3:
    if typeof(raw) != TYPE_ARRAY or raw.size() != 3:
        return Vector3.INF
    return Vector3(float(raw[0]), float(raw[1]), float(raw[2]))

func _station_origin() -> Vector3:
    return MIDI + STATION_SIDE * 34.0 + FONSNY_AXIS * 2.0

func _to_station_local_xz(point: Vector3) -> Vector2:
    var delta := point - _station_origin()
    var angle := atan2(FONSNY_AXIS.x, FONSNY_AXIS.z)
    var c := cos(angle)
    var s := sin(angle)
    return Vector2(c * delta.x - s * delta.z, s * delta.x + c * delta.z)

func _face_centroid(face: Dictionary) -> Vector3:
    var total := Vector3.ZERO
    var count := 0
    for raw_triangle: Variant in face.get("triangles", []):
        if typeof(raw_triangle) != TYPE_ARRAY:
            continue
        for raw_point: Variant in raw_triangle:
            var p := _point(raw_point)
            if p.is_finite():
                total += p
                count += 1
    return total / float(count) if count > 0 else Vector3.INF

func _inside_placeholder_footprint(local_xz: Vector2) -> bool:
    var half_x := PLACEHOLDER_SIZE_X * 0.5
    var half_z := PLACEHOLDER_SIZE_Z * 0.5
    return (
        local_xz.x >= PLACEHOLDER_CENTER_X - half_x
        and local_xz.x <= PLACEHOLDER_CENTER_X + half_x
        and local_xz.y >= PLACEHOLDER_CENTER_Z - half_z
        and local_xz.y <= PLACEHOLDER_CENTER_Z + half_z
    )

func _select_complete_roof_faces(faces: Array) -> Array[Dictionary]:
    var selected: Array[Dictionary] = []
    for raw_face: Variant in faces:
        if typeof(raw_face) != TYPE_DICTIONARY:
            continue
        var face: Dictionary = raw_face
        if str(face.get("type", "")) != "ROOFSURFACE":
            continue
        var centroid := _face_centroid(face)
        if not centroid.is_finite() or not _inside_placeholder_footprint(_to_station_local_xz(centroid)):
            continue
        selected.append(face)
        selected_face_ids.append(str(face.get("id", "")))
    return selected

func _horizontal_bounds(faces: Array[Dictionary]) -> Rect2:
    var initialized := false
    var lo := Vector2.ZERO
    var hi := Vector2.ZERO
    for face: Dictionary in faces:
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

func _neutral_roof_material() -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = Color(0.31, 0.32, 0.32, 1.0)
    material.roughness = 0.92
    material.cull_mode = BaseMaterial3D.CULL_DISABLED
    material.set_meta("neutral_presentation_only", true)
    return material

func _build_surface(faces: Array[Dictionary]) -> int:
    var tool := SurfaceTool.new()
    tool.begin(Mesh.PRIMITIVE_TRIANGLES)
    tool.set_material(_neutral_roof_material())
    var count := 0
    for face: Dictionary in faces:
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
            for vertex: Vector3 in [a, b, c]:
                tool.set_normal(normal)
                tool.add_vertex(vertex)
            count += 1
    var mesh := tool.commit()
    if mesh != null and mesh.get_surface_count() > 0:
        _mesh_instance = MeshInstance3D.new()
        _mesh_instance.name = "MidiOfficialFonsnyRoofFaces"
        _mesh_instance.mesh = mesh
        add_child(_mesh_instance)
    return count

func set_official_visible(enabled: bool) -> void:
    _official_visible = enabled
    if _mesh_instance != null:
        _mesh_instance.visible = enabled
    if _placeholder != null and is_instance_valid(_placeholder):
        _placeholder.visible = not enabled

func official_visible() -> bool:
    return _official_visible
