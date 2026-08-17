extends Node3D

const GEOMETRY_PATH := "res://data/urbis/grand_place_lod2/1654360.game.json"
const BUILDING_ID := "https://databrussels.be/id/building/1654360"
const PACKAGE_SHA := "cf8449d1a62b0e47aafe6d715ff6a2739f5c48f6d75995f7f418305a5d6cf3d2"
const FRONT_FACE_ID := "https://databrussels.be/id/buildingface/10843911"
const FACADE_BAYS := 9
const FACADE_LEVELS := 3
const EXPECTED_SOURCE_FACES := 71
const EXPECTED_SOURCE_TRIANGLES := 230
const EXPECTED_RENDER_TRIANGLES := 213
const LOD2_HEIGHT_M := 30.387
const FRONT_A := Vector2(333.6538, -584.4909)
const FRONT_B := Vector2(361.3908, -565.5639)
const FRONT_EAVES_M := 19.617

var geometry_loaded := false
var render_triangle_count := 0
var masked_osm_count := 0
var source_bounds := Rect2()
var _candidate_root: Node3D
var _masked_nodes: Array[Node3D] = []
var _masked_visibility: Array[bool] = []

func _ready() -> void:
    call_deferred("_build_when_ready")

func _build_when_ready() -> void:
    for _frame: int in range(12):
        await get_tree().process_frame
        var main := get_tree().current_scene
        if main != null and main.get_node_or_null("BrusselsOSM/GeneratedBuildings") != null:
            break
    var data := _read_geometry()
    if data.is_empty():
        return
    var faces: Array = data.get("faces", [])
    source_bounds = _horizontal_bounds(faces)
    _candidate_root = Node3D.new()
    _candidate_root.name = "MaisonDuRoiOfficialUrbIS1654360"
    add_child(_candidate_root)
    _mask_replaced_osm(source_bounds)
    var center := _building_center(faces)
    render_triangle_count = _build_surface(faces, "WALLSURFACE", _wall_material(), center, false)
    render_triangle_count += _build_surface(faces, "ROOFSURFACE", _roof_material(), center, false)
    if render_triangle_count != EXPECTED_RENDER_TRIANGLES:
        push_error("Maison du Roi render triangle contract drifted: %d" % render_triangle_count)
        return
    _build_front_surface(faces, center)
    geometry_loaded = true
    set_meta("building_id", BUILDING_ID)
    set_meta("source_face_id", FRONT_FACE_ID)
    set_meta("facade_bays", FACADE_BAYS)
    set_meta("facade_levels", FACADE_LEVELS)
    set_meta("source_bounded_visualization_not_architectural_survey", true)
    set_meta("ornament_authored", false)
    set_meta("openings_authored", false)
    set_meta("geometry_rescaled", false)
    set_meta("vertical_completeness", false)
    set_meta("opening_dimensions_source_explicit", false)
    set_meta("runtime_approved", false)
    set_meta("realism_complete", false)
    print("GRAND_PLACE_MAISON_ROI_ARTICULATION_READY: building=1654360 triangles=%d front_face=10843911 bays=9 levels=3 masked_osm=%d ornament_authored=false geometry_rescaled=false vertical_completeness=false" % [render_triangle_count, masked_osm_count])

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
    if str(data.get("schema", "")) != "grand-bruxelles-urbis-context-mesh-v1":
        return {}
    if str(source.get("building_2d_id", "")) != BUILDING_ID:
        return {}
    if str(source.get("package_sha256", "")) != PACKAGE_SHA:
        return {}
    if str(source.get("crs", "")) != "EPSG:31370" or str(source.get("license", "")) != "CC0-1.0":
        return {}
    if int(evidence.get("face_count", 0)) != EXPECTED_SOURCE_FACES or int(evidence.get("triangle_count", 0)) != EXPECTED_SOURCE_TRIANGLES:
        return {}
    if absf(float(evidence.get("height_m", 0.0)) - LOD2_HEIGHT_M) > 0.001:
        return {}
    if bool(data.get("runtime_approved", true)):
        return {}
    return data

func _point(raw: Variant) -> Vector3:
    if typeof(raw) != TYPE_ARRAY or raw.size() != 3:
        return Vector3.INF
    return Vector3(float(raw[0]), float(raw[1]), float(raw[2]))

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
            if typeof(raw_triangle) != TYPE_ARRAY:
                continue
            for raw_point: Variant in raw_triangle:
                var p := _point(raw_point)
                if not p.is_finite():
                    continue
                var xz := Vector2(p.x, p.z)
                if first:
                    lo = xz
                    hi = xz
                    first = false
                else:
                    lo.x = minf(lo.x, xz.x)
                    lo.y = minf(lo.y, xz.y)
                    hi.x = maxf(hi.x, xz.x)
                    hi.y = maxf(hi.y, xz.y)
    return Rect2(lo, hi - lo) if not first else Rect2()

func _append_triangle(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, face_type: String, center: Vector3) -> void:
    var aa := a
    var bb := b
    var cc := c
    var normal := (bb-aa).cross(cc-aa).normalized()
    var flip := false
    if face_type == "ROOFSURFACE":
        flip = normal.y < 0.0
    elif face_type == "WALLSURFACE":
        var tri_center := (aa+bb+cc)/3.0
        var outward := Vector3(tri_center.x-center.x, 0.0, tri_center.z-center.z)
        var horizontal := Vector3(normal.x, 0.0, normal.z)
        if outward.length_squared() > 0.0001 and horizontal.length_squared() > 0.0001:
            flip = horizontal.dot(outward) < 0.0
    if flip:
        var swap := bb
        bb = cc
        cc = swap
        normal = -normal
    for vertex: Vector3 in [aa,bb,cc]:
        tool.set_normal(normal)
        tool.add_vertex(vertex)

func _build_surface(faces: Array, face_type: String, material: Material, center: Vector3, skip_front: bool) -> int:
    var tool := SurfaceTool.new()
    tool.begin(Mesh.PRIMITIVE_TRIANGLES)
    tool.set_material(material)
    var count := 0
    for raw_face: Variant in faces:
        if typeof(raw_face) != TYPE_DICTIONARY or str(raw_face.get("type", "")) != face_type:
            continue
        if skip_front and str(raw_face.get("id", "")) == FRONT_FACE_ID:
            continue
        for raw_triangle: Variant in raw_face.get("triangles", []):
            if typeof(raw_triangle) != TYPE_ARRAY or raw_triangle.size() != 3:
                continue
            _append_triangle(tool, _point(raw_triangle[0]), _point(raw_triangle[1]), _point(raw_triangle[2]), face_type, center)
            count += 1
    var mesh := tool.commit()
    if mesh != null and mesh.get_surface_count() > 0:
        var instance := MeshInstance3D.new()
        instance.name = "MaisonDuRoi_%s" % face_type
        instance.mesh = mesh
        _candidate_root.add_child(instance)
        if face_type == "WALLSURFACE":
            instance.create_trimesh_collision()
    return count

func _build_front_surface(faces: Array, center: Vector3) -> void:
    var tool := SurfaceTool.new()
    tool.begin(Mesh.PRIMITIVE_TRIANGLES)
    tool.set_material(_front_material())
    var found := false
    for raw_face: Variant in faces:
        if typeof(raw_face) != TYPE_DICTIONARY or str(raw_face.get("id", "")) != FRONT_FACE_ID:
            continue
        found = true
        for raw_triangle: Variant in raw_face.get("triangles", []):
            if typeof(raw_triangle) != TYPE_ARRAY or raw_triangle.size() != 3:
                continue
            _append_triangle(tool, _point(raw_triangle[0]), _point(raw_triangle[1]), _point(raw_triangle[2]), "WALLSURFACE", center)
    if not found:
        push_error("Maison du Roi exact front wall missing")
        return
    var mesh := tool.commit()
    if mesh != null and mesh.get_surface_count() > 0:
        var instance := MeshInstance3D.new()
        instance.name = "MaisonDuRoi_ExactFrontRhythm"
        instance.mesh = mesh
        _candidate_root.add_child(instance)

func _wall_material() -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = Color(0.48, 0.42, 0.34, 1.0)
    material.roughness = 0.90
    material.cull_mode = BaseMaterial3D.CULL_BACK
    material.set_meta("material_semantics", "mixed_masonry_unresolved")
    return material

func _roof_material() -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = Color(0.12, 0.135, 0.15, 1.0)
    material.roughness = 0.92
    material.cull_mode = BaseMaterial3D.CULL_BACK
    material.set_meta("material_semantics", "slate")
    return material

func _front_material() -> ShaderMaterial:
    var tangent := (FRONT_B-FRONT_A).normalized()
    var shader := Shader.new()
    shader.code = "shader_type spatial; render_mode diffuse_burley,specular_schlick_ggx,cull_back; uniform vec2 origin; uniform vec2 tangent; uniform float span; varying vec3 p; void vertex(){p=VERTEX;} void fragment(){float u=dot(p.xz-origin,tangent)/span; float bay_phase=abs(fract(u*9.0+0.5)-0.5); float level_phase=abs(fract(clamp(p.y/19.617,0.0,1.0)*3.0)-0.5); float bay=1.0-smoothstep(0.04,0.09,bay_phase); float level=1.0-smoothstep(0.025,0.07,level_phase); float rhythm=max(bay,level); ALBEDO=mix(vec3(0.44,0.33,0.25),vec3(0.76,0.72,0.64),rhythm*0.82); ROUGHNESS=mix(0.92,0.76,rhythm); }"
    var material := ShaderMaterial.new()
    material.shader = shader
    material.set_shader_parameter("origin", FRONT_A)
    material.set_shader_parameter("tangent", tangent)
    material.set_shader_parameter("span", FRONT_A.distance_to(FRONT_B))
    material.set_meta("presentation_contract", "source_bounded_visualization_not_architectural_survey")
    material.set_meta("ornament_authored", false)
    material.set_meta("openings_authored", false)
    material.set_meta("geometry_rescaled", false)
    return material

func _mask_replaced_osm(bounds: Rect2) -> void:
    var main := get_tree().current_scene
    var buildings := main.get_node_or_null("BrusselsOSM/GeneratedBuildings") if main != null else null
    if buildings == null or bounds.size.length_squared() <= 0.001:
        return
    var expanded := bounds.grow(3.0)
    for child: Node in buildings.get_children():
        if not child is Node3D:
            continue
        var node := child as Node3D
        if not expanded.has_point(Vector2(node.global_position.x, node.global_position.z)):
            continue
        _masked_nodes.append(node)
        _masked_visibility.append(node.visible)
        node.visible = false
        node.set_meta("replaced_by_urbis_building", "1654360")
        if node is CSGShape3D:
            (node as CSGShape3D).use_collision = false
        masked_osm_count += 1

func set_candidate_visible(enabled: bool) -> void:
    if _candidate_root != null:
        _candidate_root.visible = enabled
    for i: int in range(_masked_nodes.size()):
        var node := _masked_nodes[i]
        if not is_instance_valid(node):
            continue
        node.visible = false if enabled else _masked_visibility[i]
        if node is CSGShape3D:
            (node as CSGShape3D).use_collision = not enabled

func candidate_visible() -> bool:
    return _candidate_root != null and _candidate_root.visible
