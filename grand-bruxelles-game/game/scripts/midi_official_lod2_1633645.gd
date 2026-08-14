extends Node3D

const GEOMETRY_PATH := "res://data/urbis/midi_lod2/1633645.game.json"
const BUILDING_ID := "https://databrussels.be/id/building/1633645"
const PACKAGE_SHA256 := "a760fdff222ae9431113f82fe1c8f942a9fe2bda40e32064c627ae8d3a21110f"
const EXPECTED_FACE_COUNT := 889
const EXPECTED_TRIANGLE_COUNT := 3428
const EXPECTED_RENDER_TRIANGLES := 3051
const EXPECTED_HEIGHT_M := 13.6076

var geometry_loaded := false
var render_triangle_count := 0
var source_height_m := 0.0
var source_bounds := Rect2()
var _built := false
var _official_visible := true
var _hero_zone: Node3D
var _hero_baseline_visible := true

func _ready() -> void:
    call_deferred("_build_when_scene_ready")

func _build_when_scene_ready() -> void:
    for _frame: int in range(12):
        await get_tree().process_frame
        var main := get_tree().current_scene
        if main != null and main.get_node_or_null("MidiHeroZone") != null:
            break
    if _built:
        return
    var data := _read_geometry()
    if data.is_empty():
        return
    var faces: Array = data.get("faces", [])
    source_height_m = float((data.get("evidence", {}) as Dictionary).get("height_m", 0.0))
    source_bounds = _horizontal_bounds(faces)
    _build_geometry(faces)
    if render_triangle_count != EXPECTED_RENDER_TRIANGLES:
        push_error("Midi LoD2 1633645 render triangle contract drifted: %d" % render_triangle_count)
        return
    var main := get_tree().current_scene
    if main != null:
        _hero_zone = main.get_node_or_null("MidiHeroZone") as Node3D
        if _hero_zone != null:
            _hero_baseline_visible = _hero_zone.visible
    _built = true
    geometry_loaded = true
    set_meta("building_id", BUILDING_ID)
    set_meta("source_geometry_exact", true)
    set_meta("source_vertices_moved", false)
    set_meta("source_triangles_replaced", false)
    set_meta("invented_openings", false)
    set_meta("invented_roof_details", false)
    set_meta("neutral_presentation", true)
    set_meta("runtime_approved", false)
    set_meta("realism_complete", false)
    set_official_visible(true)
    print("MIDI_LOD2_1633645_READY: triangles=%d height=%.4f bounds=(%.1f,%.1f)" % [render_triangle_count, source_height_m, source_bounds.size.x, source_bounds.size.y])

func _read_geometry() -> Dictionary:
    if not FileAccess.file_exists(GEOMETRY_PATH):
        push_error("Midi LoD2 1633645 geometry missing")
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(GEOMETRY_PATH))
    if typeof(parsed) != TYPE_DICTIONARY:
        push_error("Midi LoD2 1633645 JSON invalid")
        return {}
    var data: Dictionary = parsed
    var source: Dictionary = data.get("source", {})
    var evidence: Dictionary = data.get("evidence", {})
    if str(data.get("schema", "")) != "grand-bruxelles-urbis-hero-mesh-v1":
        push_error("Midi LoD2 1633645 schema mismatch")
        return {}
    if str(source.get("building_2d_id", "")) != BUILDING_ID:
        push_error("Midi LoD2 1633645 building identity mismatch")
        return {}
    if str(source.get("package_sha256", "")) != PACKAGE_SHA256 or str(source.get("crs", "")) != "EPSG:31370" or str(source.get("license", "")) != "CC0-1.0":
        push_error("Midi LoD2 1633645 provenance drifted")
        return {}
    if int(evidence.get("face_count", 0)) != EXPECTED_FACE_COUNT or int(evidence.get("triangle_count", 0)) != EXPECTED_TRIANGLE_COUNT:
        push_error("Midi LoD2 1633645 source count contract drifted")
        return {}
    var types: Dictionary = evidence.get("face_type_counts", {})
    if int(types.get("WALLSURFACE", 0)) != 852 or int(types.get("ROOFSURFACE", 0)) != 34:
        push_error("Midi LoD2 1633645 face-type contract drifted")
        return {}
    if absf(float(evidence.get("height_m", 0.0)) - EXPECTED_HEIGHT_M) > 0.0001:
        push_error("Midi LoD2 1633645 source height drifted")
        return {}
    if bool(data.get("runtime_approved", true)):
        push_error("Midi LoD2 1633645 source evidence must remain non-approved")
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
                    lo = xz; hi = xz; initialized = true
                else:
                    lo.x = minf(lo.x, xz.x); lo.y = minf(lo.y, xz.y)
                    hi.x = maxf(hi.x, xz.x); hi.y = maxf(hi.y, xz.y)
    return Rect2(lo, hi - lo) if initialized else Rect2()

func _neutral_material(face_type: String) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    if face_type == "ROOFSURFACE":
        material.albedo_color = Color(0.31, 0.32, 0.32, 1.0)
        material.roughness = 0.92
    else:
        material.albedo_color = Color(0.56, 0.55, 0.51, 1.0)
        material.roughness = 0.90
    material.cull_mode = BaseMaterial3D.CULL_DISABLED
    material.set_meta("neutral_presentation_only", true)
    return material

func _build_surface(faces: Array, face_type: String) -> int:
    var tool := SurfaceTool.new()
    tool.begin(Mesh.PRIMITIVE_TRIANGLES)
    tool.set_material(_neutral_material(face_type))
    var count := 0
    for raw_face: Variant in faces:
        if typeof(raw_face) != TYPE_DICTIONARY or str(raw_face.get("type", "")) != face_type:
            continue
        for raw_triangle: Variant in raw_face.get("triangles", []):
            if typeof(raw_triangle) != TYPE_ARRAY or raw_triangle.size() != 3:
                continue
            var a := _point(raw_triangle[0]); var b := _point(raw_triangle[1]); var c := _point(raw_triangle[2])
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
        var instance := MeshInstance3D.new()
        instance.name = "Midi1633645_%s" % face_type
        instance.mesh = mesh
        add_child(instance)
    return count

func _build_geometry(faces: Array) -> void:
    render_triangle_count = _build_surface(faces, "WALLSURFACE")
    render_triangle_count += _build_surface(faces, "ROOFSURFACE")

func set_official_visible(enabled: bool) -> void:
    _official_visible = enabled
    visible = enabled
    if _hero_zone != null and is_instance_valid(_hero_zone):
        _hero_zone.visible = false if enabled else _hero_baseline_visible

func official_visible() -> bool:
    return _official_visible
