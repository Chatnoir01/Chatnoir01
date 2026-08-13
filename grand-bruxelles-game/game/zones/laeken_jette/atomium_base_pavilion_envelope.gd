extends Node3D

## QA-only source-bounded plan envelope for the Atomium base pavilion.
## The official heritage inventory gives a circular plan of 26 m diameter but no
## defensible pavilion height. This component therefore renders only a terrain-
## following outline and must never be treated as production pavilion volume.

@export_file("*.json") var evidence_path := "res://data/sources/laeken_jette/atomium_hero_core_evidence.json"
@export var segment_count := 96
@export var vertical_offset_m := 0.08

var envelope_built := false
var plan_only := true
var source_diameter_m := 0.0
var source_radius_m := 0.0
var anchor_position := Vector3.ZERO
var sampled_points: Array[Vector3] = []

func build_on_terrain(terrain: Node) -> bool:
    if envelope_built:
        return true
    if terrain == null or not terrain.has_method("sample_height"):
        push_error("AtomiumBasePavilionEnvelope: terrain sampler unavailable")
        return false
    if not bool(terrain.get("terrain_loaded")):
        push_error("AtomiumBasePavilionEnvelope: terrain is not loaded")
        return false
    var evidence := _load_evidence()
    if evidence.is_empty():
        return false
    var status: Dictionary = evidence.get("status", {})
    if not bool(status.get("base_pavilion_plan_resolved", false)):
        push_error("AtomiumBasePavilionEnvelope: plan is not source-resolved")
        return false
    if bool(status.get("base_pavilion_height_resolved", true)):
        push_error("AtomiumBasePavilionEnvelope: unresolved height was incorrectly promoted")
        return false
    var dimensions: Dictionary = evidence.get("authoritative_dimensions", {})
    source_diameter_m = float(dimensions.get("base_pavilion_diameter_m", 0.0))
    source_radius_m = source_diameter_m * 0.5
    if absf(source_diameter_m - 26.0) > 0.001:
        push_error("AtomiumBasePavilionEnvelope: official 26 m diameter drifted")
        return false
    var atomium_anchor: Vector3 = terrain.get("atomium_game_position")
    var anchor_y := float(terrain.call("sample_height", atomium_anchor.x, atomium_anchor.z))
    anchor_position = Vector3(atomium_anchor.x, anchor_y, atomium_anchor.z)
    position = anchor_position
    sampled_points.clear()
    var segments := maxi(segment_count, 24)
    for i: int in range(segments):
        var angle := TAU * float(i) / float(segments)
        var local_x := cos(angle) * source_radius_m
        var local_z := sin(angle) * source_radius_m
        var world_x := anchor_position.x + local_x
        var world_z := anchor_position.z + local_z
        var world_y := float(terrain.call("sample_height", world_x, world_z))
        sampled_points.append(Vector3(local_x, world_y - anchor_position.y + vertical_offset_m, local_z))
    _build_outline()
    envelope_built = sampled_points.size() == segments
    if envelope_built:
        print("ATOMIUM_BASE_PAVILION_ENVELOPE_READY: diameter=%.3f points=%d plan_only=true" % [source_diameter_m, sampled_points.size()])
    return envelope_built

func _load_evidence() -> Dictionary:
    if not FileAccess.file_exists(evidence_path):
        push_error("AtomiumBasePavilionEnvelope: evidence missing")
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(evidence_path))
    if typeof(parsed) != TYPE_DICTIONARY:
        push_error("AtomiumBasePavilionEnvelope: evidence is not a dictionary")
        return {}
    var evidence := parsed as Dictionary
    if str(evidence.get("crs", "")) != "EPSG:31370":
        push_error("AtomiumBasePavilionEnvelope: evidence CRS is not EPSG:31370")
        return {}
    var status: Dictionary = evidence.get("status", {})
    if bool(status.get("runtime_approved", true)) or bool(status.get("realism_complete", true)):
        push_error("AtomiumBasePavilionEnvelope: provisional evidence was incorrectly promoted")
        return {}
    var contract: Dictionary = evidence.get("integration_contract", {})
    if not bool(contract.get("no_pavilion_volume_without_height_source", false)):
        push_error("AtomiumBasePavilionEnvelope: no-volume safety contract missing")
        return {}
    return evidence

func _build_outline() -> void:
    var immediate := ImmediateMesh.new()
    var material := StandardMaterial3D.new()
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    material.albedo_color = Color(1.0, 0.55, 0.08, 1.0)
    material.no_depth_test = true
    immediate.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, material)
    for point: Vector3 in sampled_points:
        immediate.surface_add_vertex(point)
    immediate.surface_add_vertex(sampled_points[0])
    immediate.surface_end()
    var instance := MeshInstance3D.new()
    instance.name = "BasePavilionPlanEnvelope26m_QAOnly"
    instance.mesh = immediate
    add_child(instance)

func measured_plan_diameter() -> float:
    if sampled_points.size() < 2:
        return 0.0
    var max_distance := 0.0
    for i: int in range(sampled_points.size()):
        var a := Vector2(sampled_points[i].x, sampled_points[i].z)
        for j: int in range(i + 1, sampled_points.size()):
            var b := Vector2(sampled_points[j].x, sampled_points[j].z)
            max_distance = maxf(max_distance, a.distance_to(b))
    return max_distance
