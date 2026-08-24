extends Node

const TARGET_PROFILES: Array[String] = [
    "brussels_capitale_sedan",
    "brussels_rapid_response_coupe",
]
const SHELL_NAME := "PoliceBodySourceProfileV6"
const PROFILE_PATHS: Dictionary = {
    "brussels_capitale_sedan": "res://assets/vehicles/mmc_generic_sedan/authored_lod/source_profile_v6.txt",
    "brussels_rapid_response_coupe": "res://assets/vehicles/mmc_generic_sport_coupe/authored_lod/source_profile_v6.txt",
}
const SOURCE_SHA256: Dictionary = {
    "brussels_capitale_sedan": "a021faaf6427bebae58c9f380502d901d33415130772f4010c64bf4a2d84f1e2",
    "brussels_rapid_response_coupe": "5c3d5836d19b12347d9ab8e044fe9593b15255d211282ffa374f140e58d9eabd",
}

var _attempts: int = 0
var _installed: Dictionary = {}
var _settle_frames: int = 90
var _profile_cache: Dictionary = {}

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
        if TARGET_PROFILES.has(profile_id) and install_source_profile(holder, profile_id):
            _installed[profile_id] = true
            _hide_legacy_shells(holder)
    if _installed.size() >= TARGET_PROFILES.size():
        _settle_frames -= 1
        if _settle_frames <= 0:
            set_process(false)
            print("MMC_POLICE_V6_SOURCE_PROFILE_READY: profiles=2 source_derived=true renderer_only=true")
    elif _attempts > 600:
        set_process(false)
        push_warning("MMC police V6 source-profile targets were not ready after 600 frames")

func get_contract() -> Dictionary:
    return {
        "profiles": TARGET_PROFILES.duplicate(),
        "renderer_only": true,
        "source_profile_derived": true,
        "project_owned_mesh_builder": true,
        "changes_existing_physics": false,
        "changes_existing_collision": false,
        "changes_traffic_motion": false,
        "changes_geography": false,
        "source_glb_bytes_required": false,
    }

func _load_profile(profile_id: String) -> Dictionary:
    if _profile_cache.has(profile_id):
        return (_profile_cache[profile_id] as Dictionary).duplicate(true)
    var path: String = str(PROFILE_PATHS.get(profile_id, ""))
    if path.is_empty() or not FileAccess.file_exists(path):
        return {}
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return {}
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    if not parsed is Dictionary:
        return {}
    var data: Dictionary = parsed as Dictionary
    if str(data.get("schema", "")) != "grand-bruxelles-mmc-source-profile-v2":
        return {}
    if str(data.get("source_sha256", "")) != str(SOURCE_SHA256.get(profile_id, "")):
        return {}
    var lower: Array = data.get("lower_sections", []) as Array
    var roof: Array = data.get("roof_sections", []) as Array
    if lower.size() != 19 or roof.size() != 13:
        return {}
    _profile_cache[profile_id] = data.duplicate(true)
    return data

func _lower_sections(profile_id: String) -> Array[Vector4]:
    var data: Dictionary = _load_profile(profile_id)
    var result: Array[Vector4] = []
    var rows: Array = data.get("lower_sections", []) as Array
    for row_variant: Variant in rows:
        if not row_variant is Array:
            continue
        var row: Array = row_variant as Array
        if row.size() != 4:
            continue
        result.append(Vector4(float(row[0]), float(row[1]), float(row[2]), float(row[3])))
    return result

func _roof_sections(profile_id: String) -> Array[Vector3]:
    var data: Dictionary = _load_profile(profile_id)
    var result: Array[Vector3] = []
    var rows: Array = data.get("roof_sections", []) as Array
    for row_variant: Variant in rows:
        if not row_variant is Array:
            continue
        var row: Array = row_variant as Array
        if row.size() != 3:
            continue
        result.append(Vector3(float(row[0]), float(row[1]), float(row[2])))
    return result

func _paint_material() -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = Color(0.91, 0.925, 0.94, 1.0)
    material.roughness = 0.28
    material.metallic = 0.14
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

func _build_lower_hull(profile_id: String) -> ArrayMesh:
    var sections: Array[Vector4] = _lower_sections(profile_id)
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
    if not sections.is_empty():
        var first: Vector4 = sections[0]
        var last: Vector4 = sections[sections.size() - 1]
        _add_quad(surface, Vector3(-first.y, first.z, first.x), Vector3(first.y, first.z, first.x), Vector3(first.y, first.w, first.x), Vector3(-first.y, first.w, first.x))
        _add_quad(surface, Vector3(last.y, last.z, last.x), Vector3(-last.y, last.z, last.x), Vector3(-last.y, last.w, last.x), Vector3(last.y, last.w, last.x))
    surface.generate_normals()
    return surface.commit()

func _build_roof(profile_id: String) -> ArrayMesh:
    var sections: Array[Vector3] = _roof_sections(profile_id)
    var surface := SurfaceTool.new()
    surface.begin(Mesh.PRIMITIVE_TRIANGLES)
    for index: int in range(sections.size() - 1):
        var a: Vector3 = sections[index]
        var b: Vector3 = sections[index + 1]
        _add_quad(surface, Vector3(-a.y, a.z, a.x), Vector3(-b.y, b.z, b.x), Vector3(b.y, b.z, b.x), Vector3(a.y, a.z, a.x))
    surface.generate_normals()
    return surface.commit()

func _hide_legacy_shells(holder: Node3D) -> void:
    var v5 := holder.get_node_or_null(NodePath("PoliceBodySilhouetteV5")) as Node3D
    if v5 != null:
        v5.visible = false
    var closure := holder.get_node_or_null(NodePath("PoliceBodyClosureV3")) as Node3D
    if closure != null:
        for child_name: String in ["ClosedLowerBody", "HoodClosure", "TrunkClosure", "RoofPanel"]:
            var old_piece := closure.get_node_or_null(NodePath(child_name)) as Node3D
            if old_piece != null:
                old_piece.visible = false

func install_source_profile(holder: Node3D, profile_id: String) -> bool:
    if holder == null or not TARGET_PROFILES.has(profile_id):
        return false
    if str(holder.get_meta("police_profile_id", "")) != profile_id:
        return false
    var profile: Dictionary = _load_profile(profile_id)
    if profile.is_empty():
        return false
    var existing := holder.get_node_or_null(NodePath(SHELL_NAME)) as Node3D
    if existing != null:
        existing.visible = true
        _hide_legacy_shells(holder)
        return true
    var shell := Node3D.new()
    shell.name = SHELL_NAME
    shell.set_meta("renderer_only", true)
    shell.set_meta("source_profile_derived", true)
    shell.set_meta("source_sha256", str(profile.get("source_sha256", "")))
    shell.set_meta("lower_section_count", 19)
    shell.set_meta("roof_section_count", 13)
    shell.set_meta("profile_id", profile_id)
    var material: StandardMaterial3D = _paint_material()
    var lower := MeshInstance3D.new()
    lower.name = "SourceProfileLowerHull"
    lower.mesh = _build_lower_hull(profile_id)
    lower.material_override = material
    lower.position.y = -0.01
    shell.add_child(lower)
    var roof := MeshInstance3D.new()
    roof.name = "SourceProfileRoofSkin"
    roof.mesh = _build_roof(profile_id)
    roof.material_override = material
    roof.position.y = -0.01
    shell.add_child(roof)
    holder.add_child(shell)
    _hide_legacy_shells(holder)
    holder.set_meta("v6_source_profile_authoritative", true)
    holder.set_meta("v6_source_profile_sha256", str(profile.get("source_sha256", "")))
    holder.set_meta("v6_renderer_only", true)
    return true
