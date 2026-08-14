extends Node

const SIDEWALK_OVERLAY_SCRIPT := preload("res://game/scripts/bourse_official_sidewalk_overlay.gd")
const PERISTYLE_VAULT_SCRIPT := preload("res://game/scripts/bourse_peristyle_vault.gd")

@export var hero_builder_path: NodePath = NodePath("../UrbISHeroGeometry")
@export var portico_path: NodePath = NodePath("../BoursePorticoArticulation")
@export_file("*.json") var candidate_path: String = "res://data/qa/bourse_portico_articulation_candidate.json"
@export var tangent_margin_m: float = 0.75
@export var front_alignment_min: float = 0.82
@export var vertical_margin_m: float = 0.25

var _removed_triangles := 0
var _kept_triangles := 0
var _roof_backface_cull_applied := false
var _portico_white_stone_applied := false
var _sidewalk_overlay: Node3D
var _peristyle_vault: Node3D

func _ready() -> void:
    _mount_sidewalk_overlay()
    _mount_peristyle_vault()
    call_deferred("_apply_reveal")

func _mount_sidewalk_overlay() -> void:
    _sidewalk_overlay = SIDEWALK_OVERLAY_SCRIPT.new() as Node3D
    if _sidewalk_overlay == null:
        push_error("Bourse front reveal: sidewalk overlay script failed to instantiate")
        return
    _sidewalk_overlay.name = "OfficialSidewalkOverlay"
    add_child(_sidewalk_overlay)

func _mount_peristyle_vault() -> void:
    _peristyle_vault = PERISTYLE_VAULT_SCRIPT.new() as Node3D
    if _peristyle_vault == null:
        push_error("Bourse front reveal: peristyle vault script failed to instantiate")
        return
    _peristyle_vault.name = "SourceBoundedPeristyleInterior"
    add_child(_peristyle_vault)

func _vec2(raw: Variant) -> Vector2:
    if typeof(raw) != TYPE_ARRAY or raw.size() != 2:
        return Vector2.ZERO
    return Vector2(float(raw[0]), float(raw[1]))

func _is_front_facing_triangle(a: Vector3, b: Vector3, c: Vector3, plane: Vector2, normal: Vector2, tangent: Vector2, t_min: float, t_max: float, y_min: float, y_max: float) -> bool:
    var centroid_3d: Vector3 = (a + b + c) / 3.0
    if centroid_3d.y < y_min - vertical_margin_m or centroid_3d.y > y_max + vertical_margin_m:
        return false
    var centroid := Vector2(centroid_3d.x, centroid_3d.z)
    var along: float = (centroid - plane).dot(tangent)
    if along < t_min - tangent_margin_m or along > t_max + tangent_margin_m:
        return false
    var face_normal: Vector3 = (b - a).cross(c - a).normalized()
    if not face_normal.is_finite() or face_normal.length_squared() < 0.5:
        return false
    var horizontal := Vector2(face_normal.x, face_normal.z)
    if horizontal.length_squared() < 0.25:
        return false
    horizontal = horizontal.normalized()
    return absf(horizontal.dot(normal)) >= front_alignment_min

func _apply_bourse_roof_backface_cull(hero: Node) -> bool:
    var roofs := hero.get_node_or_null("Roofs") as MeshInstance3D
    if roofs == null or roofs.mesh == null or roofs.mesh.get_surface_count() == 0:
        push_error("Bourse front reveal: roof mesh missing")
        return false
    var source_material := roofs.mesh.surface_get_material(0) as StandardMaterial3D
    if source_material == null:
        push_error("Bourse front reveal: roof material missing")
        return false
    var roof_material := source_material.duplicate() as StandardMaterial3D
    if roof_material == null:
        push_error("Bourse front reveal: roof material duplication failed")
        return false
    roof_material.cull_mode = BaseMaterial3D.CULL_BACK
    roofs.material_override = roof_material
    roofs.set_meta("bourse_roof_backface_cull", true)
    roofs.set_meta("bourse_roof_triangle_count_preserved", roofs.mesh.surface_get_array_len(0) / 3)
    _roof_backface_cull_applied = true
    return true

func _apply_portico_white_stone_presentation() -> bool:
    var portico := get_node_or_null(portico_path)
    if portico == null:
        push_error("Bourse front reveal: portico articulation missing")
        return false
    var white_stone := StandardMaterial3D.new()
    white_stone.albedo_color = Color(0.84, 0.82, 0.76, 1.0)
    white_stone.metallic = 0.0
    white_stone.roughness = 0.76
    var applied := 0
    for child: Node in portico.get_children():
        var name_value := str(child.name)
        var is_white_stone_detail := name_value.begins_with("Column_") or name_value.begins_with("RearPilaster_") or name_value == "PorticoEntablature" or name_value == "RearCentralEntryLintel"
        if not is_white_stone_detail:
            continue
        if child is MeshInstance3D:
            (child as MeshInstance3D).material_override = white_stone
            applied += 1
        elif child is CSGBox3D:
            (child as CSGBox3D).material = white_stone
            applied += 1
    if applied < 20:
        push_error("Bourse front reveal: white-stone presentation applied to too few details: %d" % applied)
        return false
    portico.set_meta("bourse_white_stone_presentation", true)
    portico.set_meta("bourse_white_stone_source", "urban.brussels heritage inventory 31241")
    portico.set_meta("bourse_white_stone_authored_pbr", true)
    portico.set_meta("bourse_white_stone_detail_count", applied)
    _portico_white_stone_applied = true
    return true

func _apply_reveal() -> void:
    if not FileAccess.file_exists(candidate_path):
        push_error("Bourse front reveal: candidate evidence missing")
        return
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(candidate_path))
    if typeof(parsed) != TYPE_DICTIONARY:
        push_error("Bourse front reveal: invalid candidate evidence")
        return
    var data := parsed as Dictionary
    if bool(data.get("runtime_approved", true)) or bool(data.get("realism_complete", true)):
        push_error("Bourse front reveal: provisional evidence must remain unapproved")
        return
    var envelope: Dictionary = data.get("authoritative_front_envelope", {})
    var plane: Vector2 = _vec2(envelope.get("plane_point_game_x_z", []))
    var normal: Vector2 = _vec2(envelope.get("toward_camera_x_z", [])).normalized()
    var tangent: Vector2 = _vec2(envelope.get("tangent_x_z", [])).normalized()
    var t_min: float = float(envelope.get("tangent_min_m", 0.0))
    var t_max: float = float(envelope.get("tangent_max_m", 0.0))
    var y_min: float = float(envelope.get("y_min_m", 0.0))
    var y_max: float = float(envelope.get("y_max_m", 0.0))
    if normal.length_squared() < 0.99 or tangent.length_squared() < 0.99 or t_max <= t_min or y_max <= y_min:
        push_error("Bourse front reveal: invalid authoritative front envelope")
        return
    var builder := get_node_or_null(hero_builder_path)
    if builder == null:
        push_error("Bourse front reveal: hero builder missing")
        return
    var hero := builder.get_node_or_null("Hero_Bourse")
    if hero == null:
        push_error("Bourse front reveal: Hero_Bourse missing")
        return
    var walls := hero.get_node_or_null("Walls") as MeshInstance3D
    if walls == null or walls.mesh == null or walls.mesh.get_surface_count() == 0:
        push_error("Bourse front reveal: wall mesh missing")
        return
    var arrays: Array = walls.mesh.surface_get_arrays(0)
    var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
    if vertices.size() < 3 or vertices.size() % 3 != 0:
        push_error("Bourse front reveal: non-triangle wall mesh")
        return
    var tool := SurfaceTool.new()
    tool.begin(Mesh.PRIMITIVE_TRIANGLES)
    var material := walls.mesh.surface_get_material(0)
    if material != null:
        tool.set_material(material)
    _removed_triangles = 0
    _kept_triangles = 0
    for index: int in range(0, vertices.size(), 3):
        var a: Vector3 = vertices[index]
        var b: Vector3 = vertices[index + 1]
        var c: Vector3 = vertices[index + 2]
        if _is_front_facing_triangle(a, b, c, plane, normal, tangent, t_min, t_max, y_min, y_max):
            _removed_triangles += 1
            continue
        var face_normal: Vector3 = (b - a).cross(c - a).normalized()
        if not face_normal.is_finite() or face_normal.length_squared() < 0.5:
            continue
        for vertex: Vector3 in [a, b, c]:
            tool.set_normal(face_normal)
            tool.add_vertex(vertex)
        _kept_triangles += 1
    var revealed := tool.commit()
    if revealed == null or revealed.get_surface_count() == 0:
        push_error("Bourse front reveal: filtered wall mesh is empty")
        return
    if _removed_triangles <= 0 or _kept_triangles <= _removed_triangles:
        push_error("Bourse front reveal: unsafe source-bounded selection removed=%d kept=%d" % [_removed_triangles, _kept_triangles])
        return
    walls.mesh = revealed
    walls.set_meta("bourse_front_reveal_source_bounded", true)
    walls.set_meta("bourse_front_reveal_removed_triangles", _removed_triangles)
    walls.set_meta("bourse_front_reveal_kept_triangles", _kept_triangles)
    if not _apply_bourse_roof_backface_cull(hero):
        return
    if not _apply_portico_white_stone_presentation():
        return
    set_meta("runtime_approved", false)
    set_meta("realism_complete", false)
    print("Bourse front wall reveal: removed=%d kept=%d roof_backface_cull=true white_stone=true peristyle_vault=true runtime_approved=false" % [_removed_triangles, _kept_triangles])

func diagnostic_removed_triangles() -> int:
    return _removed_triangles
func diagnostic_kept_triangles() -> int:
    return _kept_triangles
func diagnostic_roof_backface_cull_applied() -> bool:
    return _roof_backface_cull_applied
func diagnostic_portico_white_stone_applied() -> bool:
    return _portico_white_stone_applied
func diagnostic_peristyle_vault_mounted() -> bool:
    return _peristyle_vault != null
