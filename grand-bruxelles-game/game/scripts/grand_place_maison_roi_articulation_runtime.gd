extends Node3D

const GEOMETRY_PATH := "res://data/urbis/grand_place_lod2/1654360.game.json"
const BUILDING_ID := "https://databrussels.be/id/building/1654360"
const PACKAGE_SHA := "cf8449d1a62b0e47aafe6d715ff6a2739f5c48f6d75995f7f418305a5d6cf3d2"
const FRONT_FACE_ID := "https://databrussels.be/id/buildingface/10843911"
const FACADE_BAYS := 9
const FACADE_LEVELS := 3
const FRONT_A := Vector2(333.6538, -584.4909)
const FRONT_B := Vector2(361.3908, -565.5639)

var geometry_loaded := false
var render_triangle_count := 0
var _surface: MeshInstance3D

func _ready() -> void:
    call_deferred("_build")

func _build() -> void:
    var data := _read_geometry()
    if data.is_empty():
        return
    var face := _find_front_face(data.get("faces", []))
    if face.is_empty():
        push_error("Maison du Roi exact front wall missing")
        return
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    st.set_material(_material())
    for raw_triangle: Variant in face.get("triangles", []):
        if typeof(raw_triangle) != TYPE_ARRAY or raw_triangle.size() != 3:
            continue
        var a := _point(raw_triangle[0])
        var b := _point(raw_triangle[1])
        var c := _point(raw_triangle[2])
        var normal := (b-a).cross(c-a).normalized()
        if normal.x - normal.z > 0.0:
            var swap := b
            b = c
            c = swap
            normal = -normal
        for vertex: Vector3 in [a,b,c]:
            st.set_normal(normal)
            st.add_vertex(vertex)
        render_triangle_count += 1
    var mesh := st.commit()
    if mesh == null or render_triangle_count < 8:
        push_error("Maison du Roi exact front wall did not materialize")
        return
    _surface = MeshInstance3D.new()
    _surface.name = "MaisonRoiExactUrbISFrontRhythm"
    _surface.mesh = mesh
    add_child(_surface)
    geometry_loaded = true
    set_meta("building_id", BUILDING_ID)
    set_meta("source_face_id", FRONT_FACE_ID)
    set_meta("facade_bays", FACADE_BAYS)
    set_meta("facade_levels", FACADE_LEVELS)
    set_meta("source_bounded_visualization_not_architectural_survey", true)
    set_meta("ornament_authored", false)
    set_meta("geometry_rescaled", false)
    set_meta("vertical_completeness", false)
    set_meta("opening_dimensions_source_explicit", false)
    set_meta("runtime_approved", false)
    print("GRAND_PLACE_MAISON_ROI_ARTICULATION_READY: exact_face=10843911 triangles=%d bays=9 levels=3 ornament_authored=false geometry_rescaled=false vertical_completeness=false" % render_triangle_count)

func _read_geometry() -> Dictionary:
    if not FileAccess.file_exists(GEOMETRY_PATH):
        return {}
    var parsed := JSON.parse_string(FileAccess.get_file_as_string(GEOMETRY_PATH))
    if typeof(parsed) != TYPE_DICTIONARY:
        return {}
    var data := parsed as Dictionary
    var source := data.get("source", {}) as Dictionary
    var evidence := data.get("evidence", {}) as Dictionary
    if str(source.get("building_2d_id", "")) != BUILDING_ID:
        return {}
    if str(source.get("package_sha256", "")) != PACKAGE_SHA:
        return {}
    if int(evidence.get("face_count", 0)) != 71 or int(evidence.get("triangle_count", 0)) != 230:
        return {}
    if absf(float(evidence.get("height_m", 0.0)) - 30.387) > 0.001:
        return {}
    return data

func _find_front_face(faces: Array) -> Dictionary:
    for raw_face: Variant in faces:
        if typeof(raw_face) == TYPE_DICTIONARY and str(raw_face.get("id", "")) == FRONT_FACE_ID:
            return raw_face as Dictionary
    return {}

func _point(raw: Variant) -> Vector3:
    if typeof(raw) != TYPE_ARRAY or raw.size() != 3:
        return Vector3.INF
    return Vector3(float(raw[0]), float(raw[1]), float(raw[2]))

func _material() -> ShaderMaterial:
    var tangent := (FRONT_B-FRONT_A).normalized()
    var shader := Shader.new()
    shader.code = "shader_type spatial; render_mode diffuse_burley,specular_schlick_ggx,cull_back; uniform vec2 origin; uniform vec2 tangent; uniform float span; varying vec3 p; void vertex(){p=VERTEX;} void fragment(){float u=dot(p.xz-origin,tangent)/span; float bp=abs(fract(u*9.0+0.5)-0.5); float vp=abs(fract(clamp(p.y/19.617,0.0,1.0)*3.0)-0.5); float bay=1.0-smoothstep(0.04,0.09,bp); float lev=1.0-smoothstep(0.025,0.07,vp); float rhythm=max(bay,lev); ALBEDO=mix(vec3(0.44,0.33,0.25),vec3(0.76,0.72,0.64),rhythm*0.82); ROUGHNESS=mix(0.92,0.76,rhythm); }"
    var material := ShaderMaterial.new()
    material.shader = shader
    material.set_shader_parameter("origin", FRONT_A)
    material.set_shader_parameter("tangent", tangent)
    material.set_shader_parameter("span", FRONT_A.distance_to(FRONT_B))
    material.set_meta("presentation_contract", "source_bounded_visualization_not_architectural_survey")
    material.set_meta("ornament_authored", false)
    material.set_meta("geometry_rescaled", false)
    return material

func set_candidate_visible(enabled: bool) -> void:
    if _surface != null:
        _surface.visible = enabled

func candidate_visible() -> bool:
    return _surface != null and _surface.visible
