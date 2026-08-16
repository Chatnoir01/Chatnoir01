extends Node3D

const DATA_PATH := "res://data/urbis/midi_fonsny_roof_continuation/1633645_roofs_outside_core.game.json"
const BUILDING_ID := "https://databrussels.be/id/building/1633645"
const PACKAGE_SHA256 := "a760fdff222ae9431113f82fe1c8f942a9fe2bda40e32064c627ae8d3a21110f"
const EXPECTED_FACE_COUNT := 18
const EXPECTED_TRIANGLE_COUNT := 105

var geometry_loaded := false
var render_triangle_count := 0
var source_face_count := 0
var _built := false

func _ready() -> void:
    call_deferred("_build")

func _read_data() -> Dictionary:
    if not FileAccess.file_exists(DATA_PATH):
        push_error("Midi Fonsny roof continuation data missing")
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
    if typeof(parsed) != TYPE_DICTIONARY:
        push_error("Midi Fonsny roof continuation JSON invalid")
        return {}
    var data: Dictionary = parsed
    var source: Dictionary = data.get("source", {})
    var selection: Dictionary = data.get("selection", {})
    if str(data.get("schema", "")) != "grand-bruxelles-midi-fonsny-roof-continuation-v1":
        push_error("Midi Fonsny roof continuation schema drifted")
        return {}
    if str(source.get("building_2d_id", "")) != BUILDING_ID:
        push_error("Midi Fonsny roof continuation building identity drifted")
        return {}
    if str(source.get("package_sha256", "")) != PACKAGE_SHA256 or str(source.get("crs", "")) != "EPSG:31370" or str(source.get("license", "")) != "CC0-1.0":
        push_error("Midi Fonsny roof continuation provenance drifted")
        return {}
    if int(selection.get("selected_face_count", 0)) != EXPECTED_FACE_COUNT or int(selection.get("selected_triangle_count", 0)) != EXPECTED_TRIANGLE_COUNT:
        push_error("Midi Fonsny roof continuation selection count drifted")
        return {}
    if not bool(selection.get("complete_face_only", false)) or bool(selection.get("vertex_clipping", true)) or bool(selection.get("vertex_movement", true)) or bool(selection.get("triangle_replacement", true)):
        push_error("Midi Fonsny roof continuation exact-source invariants drifted")
        return {}
    if bool(data.get("runtime_approved", true)) or bool(data.get("realism_complete", true)):
        push_error("Midi Fonsny roof continuation source must remain non-approved evidence")
        return {}
    return data

func _point(raw: Variant) -> Vector3:
    if typeof(raw) != TYPE_ARRAY or raw.size() != 3:
        return Vector3.INF
    return Vector3(float(raw[0]), float(raw[1]), float(raw[2]))

func _material() -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = Color(0.285, 0.295, 0.30, 1.0)
    material.roughness = 0.92
    material.metallic = 0.02
    material.cull_mode = BaseMaterial3D.CULL_DISABLED
    material.set_meta("neutral_presentation_only", true)
    material.set_meta("material_identity_claimed", false)
    return material

func _build() -> void:
    if _built:
        return
    var data := _read_data()
    if data.is_empty():
        return
    var faces: Array = data.get("faces", [])
    source_face_count = faces.size()
    var tool := SurfaceTool.new()
    tool.begin(Mesh.PRIMITIVE_TRIANGLES)
    tool.set_material(_material())
    var triangle_count := 0
    for raw_face: Variant in faces:
        if typeof(raw_face) != TYPE_DICTIONARY or str(raw_face.get("type", "")) != "ROOFSURFACE":
            push_error("Midi Fonsny roof continuation contains a non-roof face")
            return
        for raw_triangle: Variant in raw_face.get("triangles", []):
            if typeof(raw_triangle) != TYPE_ARRAY or raw_triangle.size() != 3:
                push_error("Midi Fonsny roof continuation malformed triangle")
                return
            var a := _point(raw_triangle[0])
            var b := _point(raw_triangle[1])
            var c := _point(raw_triangle[2])
            if not a.is_finite() or not b.is_finite() or not c.is_finite():
                push_error("Midi Fonsny roof continuation invalid source vertex")
                return
            var normal := (b - a).cross(c - a).normalized()
            if not normal.is_finite() or normal.length_squared() < 0.5:
                push_error("Midi Fonsny roof continuation degenerate source triangle")
                return
            for vertex: Vector3 in [a, b, c]:
                tool.set_normal(normal)
                tool.add_vertex(vertex)
            triangle_count += 1
    if source_face_count != EXPECTED_FACE_COUNT or triangle_count != EXPECTED_TRIANGLE_COUNT:
        push_error("Midi Fonsny roof continuation runtime count mismatch")
        return
    var mesh := tool.commit()
    if mesh == null or mesh.get_surface_count() == 0:
        push_error("Midi Fonsny roof continuation mesh empty")
        return
    var instance := MeshInstance3D.new()
    instance.name = "OfficialFonsnyRoofContinuation"
    instance.mesh = mesh
    add_child(instance)
    render_triangle_count = triangle_count
    _built = true
    geometry_loaded = true
    set_meta("source_vertices_moved", false)
    set_meta("source_triangles_replaced", false)
    set_meta("source_faces_clipped", false)
    set_meta("hero_zone_replaced", false)
    set_meta("material_identity_claimed", false)
    set_meta("runtime_approved", false)
    set_meta("realism_complete", false)
    print("MIDI_FONSNY_ROOF_CONTINUATION_READY: faces=%d triangles=%d" % [source_face_count, render_triangle_count])

func set_continuation_visible(enabled: bool) -> void:
    visible = enabled

func continuation_visible() -> bool:
    return visible
