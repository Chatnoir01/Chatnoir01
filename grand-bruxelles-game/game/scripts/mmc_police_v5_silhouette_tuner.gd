extends Node

const TARGET_PROFILES: Array[String] = [
    "brussels_capitale_sedan",
    "brussels_rapid_response_coupe",
]
const SHELL_NAME := "PoliceBodySilhouetteV5"

var _attempts: int = 0
var _installed: Dictionary = {}

func _ready() -> void:
    set_process(true)

func _process(_delta: float) -> void:
    _attempts += 1
    for value: Node in get_tree().get_nodes_in_group("belgian_police_vehicle"):
        var vehicle := value as Node3D
        if vehicle == null:
            continue
        var holder := vehicle.get_node_or_null(NodePath("BelgianPoliceFleetVisual")) as Node3D
        if holder == null:
            continue
        var profile_id: String = str(holder.get_meta("police_profile_id", ""))
        if TARGET_PROFILES.has(profile_id) and install_silhouette(holder, profile_id):
            _installed[profile_id] = true
    if _installed.size() >= TARGET_PROFILES.size():
        set_process(false)
        print("MMC_POLICE_V5_SILHOUETTE_READY: profiles=2 smooth_lower_hull=true curved_roof=true renderer_only=true")
    elif _attempts > 600:
        set_process(false)
        push_warning("MMC police V5 silhouette targets were not ready after 600 frames")

func get_contract() -> Dictionary:
    return {
        "profiles": TARGET_PROFILES.duplicate(),
        "renderer_only": true,
        "changes_existing_physics": false,
        "changes_existing_collision": false,
        "changes_traffic_motion": false,
        "changes_geography": false,
        "project_owned_silhouette": true,
        "source_glb_bytes_required": false,
    }

func _paint_material() -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = Color(0.91, 0.925, 0.94, 1.0)
    material.roughness = 0.30
    material.metallic = 0.12
    return material

func _add_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
    surface.set_uv(Vector2.ZERO)
    surface.add_vertex(a)
    surface.set_uv(Vector2(1.0, 0.0))
    surface.add_vertex(b)
    surface.set_uv(Vector2(0.5, 1.0))
    surface.add_vertex(c)

func _add_quad(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
    _add_triangle(surface, a, b, c)
    _add_triangle(surface, a, c, d)

func _lower_sections(is_coupe: bool) -> Array[Vector4]:
    if is_coupe:
        return [
            Vector4(-2.18, 0.55, 0.37, 0.56), Vector4(-1.96, 0.76, 0.36, 0.64), Vector4(-1.65, 0.88, 0.34, 0.72), Vector4(-1.30, 0.91, 0.33, 0.77), Vector4(-0.90, 0.92, 0.33, 0.81), Vector4(-0.45, 0.93, 0.33, 0.83), Vector4(0.00, 0.93, 0.33, 0.83), Vector4(0.45, 0.93, 0.33, 0.82), Vector4(0.90, 0.92, 0.33, 0.79), Vector4(1.28, 0.90, 0.34, 0.75), Vector4(1.62, 0.86, 0.35, 0.69), Vector4(1.92, 0.73, 0.37, 0.61), Vector4(2.12, 0.53, 0.40, 0.54),
        ]
    return [
        Vector4(-2.25, 0.56, 0.37, 0.57), Vector4(-2.03, 0.78, 0.36, 0.65), Vector4(-1.70, 0.89, 0.34, 0.73), Vector4(-1.34, 0.92, 0.33, 0.78), Vector4(-0.94, 0.93, 0.33, 0.82), Vector4(-0.48, 0.94, 0.33, 0.84), Vector4(0.00, 0.94, 0.33, 0.84), Vector4(0.48, 0.94, 0.33, 0.84), Vector4(0.94, 0.93, 0.33, 0.81), Vector4(1.35, 0.91, 0.34, 0.77), Vector4(1.72, 0.87, 0.35, 0.70), Vector4(2.04, 0.75, 0.37, 0.62), Vector4(2.24, 0.54, 0.40, 0.55),
    ]

func _roof_sections(is_coupe: bool) -> Array[Vector3]:
    if is_coupe:
        return [Vector3(-0.78, 0.55, 1.05), Vector3(-0.55, 0.63, 1.17), Vector3(-0.25, 0.66, 1.23), Vector3(0.10, 0.67, 1.25), Vector3(0.45, 0.65, 1.22), Vector3(0.73, 0.59, 1.14), Vector3(0.92, 0.50, 1.02)]
    return [Vector3(-0.82, 0.57, 1.08), Vector3(-0.58, 0.64, 1.21), Vector3(-0.28, 0.67, 1.28), Vector3(0.08, 0.68, 1.31), Vector3(0.46, 0.67, 1.29), Vector3(0.78, 0.62, 1.21), Vector3(0.98, 0.53, 1.08)]

func _build_lower_hull(is_coupe: bool) -> ArrayMesh:
    var sections: Array[Vector4] = _lower_sections(is_coupe)
    var surface := SurfaceTool.new()
    surface.begin(Mesh.PRIMITIVE_TRIANGLES)
    for index: int in range(sections.size() - 1):
        var a: Vector4 = sections[index]
        var b: Vector4 = sections[index + 1]
        var a_lb := Vector3(-a.y, a.z, a.x)
        var a_lt := Vector3(-a.y, a.w, a.x)
        var a_rb := Vector3(a.y, a.z, a.x)
        var a_rt := Vector3(a.y, a.w, a.x)
        var b_lb := Vector3(-b.y, b.z, b.x)
        var b_lt := Vector3(-b.y, b.w, b.x)
        var b_rb := Vector3(b.y, b.z, b.x)
        var b_rt := Vector3(b.y, b.w, b.x)
        _add_quad(surface, a_lb, b_lb, b_lt, a_lt)
        _add_quad(surface, a_rt, b_rt, b_rb, a_rb)
        _add_quad(surface, a_lt, b_lt, b_rt, a_rt)
        _add_quad(surface, a_rb, b_rb, b_lb, a_lb)
    var first: Vector4 = sections[0]
    var last: Vector4 = sections[sections.size() - 1]
    _add_quad(surface, Vector3(-first.y, first.z, first.x), Vector3(first.y, first.z, first.x), Vector3(first.y, first.w, first.x), Vector3(-first.y, first.w, first.x))
    _add_quad(surface, Vector3(last.y, last.z, last.x), Vector3(-last.y, last.z, last.x), Vector3(-last.y, last.w, last.x), Vector3(last.y, last.w, last.x))
    surface.generate_normals()
    return surface.commit()

func _build_roof(is_coupe: bool) -> ArrayMesh:
    var sections: Array[Vector3] = _roof_sections(is_coupe)
    var surface := SurfaceTool.new()
    surface.begin(Mesh.PRIMITIVE_TRIANGLES)
    for index: int in range(sections.size() - 1):
        var a: Vector3 = sections[index]
        var b: Vector3 = sections[index + 1]
        _add_quad(surface, Vector3(-a.y, a.z, a.x), Vector3(-b.y, b.z, b.x), Vector3(b.y, b.z, b.x), Vector3(a.y, a.z, a.x))
    surface.generate_normals()
    return surface.commit()

func install_silhouette(holder: Node3D, profile_id: String) -> bool:
    if holder == null or not TARGET_PROFILES.has(profile_id):
        return false
    if str(holder.get_meta("police_profile_id", "")) != profile_id:
        return false
    var existing := holder.get_node_or_null(NodePath(SHELL_NAME)) as Node3D
    if existing != null:
        existing.visible = true
        return true
    var shell := Node3D.new()
    shell.name = SHELL_NAME
    shell.set_meta("renderer_only", true)
    shell.set_meta("project_owned_geometry", true)
    shell.set_meta("profile_id", profile_id)
    var is_coupe: bool = profile_id == "brussels_rapid_response_coupe"
    var material: StandardMaterial3D = _paint_material()
    var lower := MeshInstance3D.new()
    lower.name = "SmoothLowerHull"
    lower.mesh = _build_lower_hull(is_coupe)
    lower.material_override = material
    lower.position.y = -0.015
    shell.add_child(lower)
    var roof := MeshInstance3D.new()
    roof.name = "CurvedRoofSkin"
    roof.mesh = _build_roof(is_coupe)
    roof.material_override = material
    roof.position.y = -0.015
    shell.add_child(roof)
    holder.add_child(shell)
    var closure := holder.get_node_or_null(NodePath("PoliceBodyClosureV3")) as Node3D
    if closure != null:
        for child_name: String in ["ClosedLowerBody", "HoodClosure", "TrunkClosure", "RoofPanel"]:
            var old_piece := closure.get_node_or_null(NodePath(child_name)) as Node3D
            if old_piece != null:
                old_piece.visible = false
    holder.set_meta("v5_silhouette_tuned", true)
    holder.set_meta("v5_smooth_lower_hull", true)
    holder.set_meta("v5_curved_roof_skin", true)
    holder.set_meta("v5_renderer_only", true)
    return true
