extends Node3D

## Source-bounded Atomium core silhouette plus a player-visible presentation finish.
## Published geometry stays authoritative: 9 spheres / 20 tubes and dimensions.
## The three support pillars and global yaw remain unresolved and are deliberately
## not fabricated by this pass.

@export_file("*.json") var evidence_path := "res://data/sources/laeken_jette/atomium_hero_core_evidence.json"
@export_file("*.json") var visible_finish_evidence_path := "res://data/sources/laeken_jette/atomium_visible_production_pass_evidence.json"

const LANDCOVER_CONTEXT_SCRIPT := preload("res://game/zones/laeken_jette/atomium_landcover_context.gd")
const SPHERE_SKIN_SEMANTICS_SCRIPT := preload("res://game/zones/laeken_jette/atomium_sphere_skin_semantics.gd")
const BASE_SPHERE_WINDOW_BAND_SCRIPT := preload("res://game/zones/laeken_jette/atomium_base_sphere_window_band.gd")
const BASE_SPHERE_TOPOLOGY_ID := 0
const SPHERE_RADIAL_SEGMENTS := 48
const SPHERE_RINGS := 24
const TUBE_RADIAL_SEGMENTS := 32
const VISIBLE_FINISH_REVISION := 3

const BASELINE_SPHERE_ALBEDO := Color(0.82, 0.85, 0.87, 1.0)
const BASELINE_SPHERE_METALLIC := 0.96
const BASELINE_SPHERE_ROUGHNESS := 0.16
const CANDIDATE_SPHERE_ALBEDO := Color(0.90, 0.925, 0.95, 1.0)
const CANDIDATE_SPHERE_METALLIC := 0.985
const CANDIDATE_SPHERE_ROUGHNESS := 0.105
const BASELINE_TUBE_ALBEDO := Color(0.57, 0.61, 0.64, 1.0)
const BASELINE_TUBE_METALLIC := 0.78
const BASELINE_TUBE_ROUGHNESS := 0.28
const CANDIDATE_TUBE_ALBEDO := Color(0.66, 0.69, 0.72, 1.0)
const CANDIDATE_TUBE_METALLIC := 0.88
const CANDIDATE_TUBE_ROUGHNESS := 0.205

var hero_built := false
var sphere_count := 0
var tube_count := 0
var source_height_m := 0.0
var source_sphere_diameter_m := 0.0
var source_tube_diameter_m := 0.0
var unresolved_support_pillars := 0
var anchor_position := Vector3.ZERO
var landcover_context: Node3D
var base_sphere_window_band: Node3D
var sphere_skin_semantics_applied := false
var visible_finish_enabled := true
var visible_finish_contract_valid := false
var visible_finish_revision := VISIBLE_FINISH_REVISION

var _sphere_material: StandardMaterial3D
var _tube_material: StandardMaterial3D

func build_on_terrain(terrain: Node) -> bool:
    if hero_built:
        return true
    if terrain == null or not terrain.has_method("sample_height"):
        push_error("AtomiumHeroCore: terrain sampler unavailable")
        return false
    var evidence := _load_evidence()
    if evidence.is_empty():
        return false
    if not _load_visible_finish_contract():
        return false
    var dimensions: Dictionary = evidence.get("authoritative_dimensions", {})
    var centres_raw: Variant = evidence.get("core_sphere_centres_m", [])
    var tubes_raw: Variant = evidence.get("connecting_tubes", [])
    if not centres_raw is Array or not tubes_raw is Array:
        push_error("AtomiumHeroCore: invalid topology payload")
        return false
    source_height_m = float(dimensions.get("total_height_m", 0.0))
    source_sphere_diameter_m = float(dimensions.get("sphere_diameter_m", 0.0))
    source_tube_diameter_m = float(dimensions.get("tube_diameter_m", 0.0))
    unresolved_support_pillars = int(dimensions.get("support_pillar_count", 0))
    if centres_raw.size() != int(dimensions.get("sphere_count", -1)) or tubes_raw.size() != int(dimensions.get("connecting_tube_count", -1)):
        push_error("AtomiumHeroCore: source counts do not match topology")
        return false
    if not terrain.get("terrain_loaded"):
        push_error("AtomiumHeroCore: terrain is not loaded")
        return false
    var atomium_anchor: Vector3 = terrain.get("atomium_game_position")
    var sampled_y := float(terrain.call("sample_height", atomium_anchor.x, atomium_anchor.z))
    anchor_position = Vector3(atomium_anchor.x, sampled_y, atomium_anchor.z)
    position = anchor_position
    _make_materials()
    if not sphere_skin_semantics_applied:
        push_error("AtomiumHeroCore: source-bounded sphere skin semantics unavailable")
        return false
    var centres: Array[Vector3] = []
    for raw: Variant in centres_raw:
        if not raw is Array or raw.size() != 3:
            push_error("AtomiumHeroCore: invalid sphere centre")
            return false
        centres.append(Vector3(float(raw[0]), float(raw[1]), float(raw[2])))
    for i: int in range(centres.size()):
        _add_sphere(i, centres[i])
    if not _mount_base_sphere_window_band(centres):
        return false
    for raw_edge: Variant in tubes_raw:
        if not raw_edge is Array or raw_edge.size() != 2:
            push_error("AtomiumHeroCore: invalid tube edge")
            return false
        var a := int(raw_edge[0])
        var b := int(raw_edge[1])
        if a < 0 or b < 0 or a >= centres.size() or b >= centres.size() or a == b:
            push_error("AtomiumHeroCore: tube edge outside sphere topology")
            return false
        _add_tube(centres[a], centres[b])
    hero_built = sphere_count == 9 and tube_count == 20 and is_instance_valid(base_sphere_window_band)
    if hero_built:
        _mount_landcover_context(terrain)
        print("ATOMIUM_HERO_CORE_READY: spheres=%d tubes=%d anchor_y=%.3f unresolved_pillars=%d sphere_skin_semantics=%s visible_finish_rev=%d base_window_sphere_id=%d exact_seams=false" % [sphere_count, tube_count, anchor_position.y, unresolved_support_pillars, str(sphere_skin_semantics_applied), visible_finish_revision, BASE_SPHERE_TOPOLOGY_ID])
    return hero_built

func _mount_base_sphere_window_band(centres: Array[Vector3]) -> bool:
    if BASE_SPHERE_TOPOLOGY_ID < 0 or BASE_SPHERE_TOPOLOGY_ID >= centres.size():
        push_error("AtomiumHeroCore: target sphere id unavailable")
        return false
    base_sphere_window_band = BASE_SPHERE_WINDOW_BAND_SCRIPT.new()
    base_sphere_window_band.name = "AtomiumBaseSphereWindowBand"
    add_child(base_sphere_window_band)
    if not bool(base_sphere_window_band.call("build_on_sphere", BASE_SPHERE_TOPOLOGY_ID, centres[BASE_SPHERE_TOPOLOGY_ID], source_sphere_diameter_m)):
        base_sphere_window_band.queue_free()
        base_sphere_window_band = null
        push_error("AtomiumHeroCore: sphere-id window cue failed to build")
        return false
    return int(base_sphere_window_band.call("target_sphere_id")) == BASE_SPHERE_TOPOLOGY_ID

func set_visible_finish_enabled(enabled: bool) -> void:
    visible_finish_enabled = enabled
    _apply_finish_materials(enabled)
    if is_instance_valid(base_sphere_window_band):
        base_sphere_window_band.call("set_enabled", enabled)

func visible_finish_is_enabled() -> bool:
    return visible_finish_enabled

func visible_finish_is_source_bounded() -> bool:
    return visible_finish_contract_valid and unresolved_support_pillars == 3

func _mount_landcover_context(terrain: Node) -> void:
    var world_parent := get_parent()
    if world_parent == null:
        return
    landcover_context = LANDCOVER_CONTEXT_SCRIPT.new()
    landcover_context.name = "AtomiumLandCoverContext"
    world_parent.add_child(landcover_context)
    if not bool(landcover_context.call("build_on_terrain", terrain)):
        landcover_context.queue_free()
        landcover_context = null
        push_warning("AtomiumHeroCore: official LandCover context unavailable; hero remains valid")

func _load_evidence() -> Dictionary:
    if not FileAccess.file_exists(evidence_path):
        push_error("AtomiumHeroCore: evidence missing")
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(evidence_path))
    if typeof(parsed) != TYPE_DICTIONARY:
        push_error("AtomiumHeroCore: evidence is not a dictionary")
        return {}
    var evidence := parsed as Dictionary
    if str(evidence.get("crs", "")) != "EPSG:31370":
        push_error("AtomiumHeroCore: evidence CRS is not EPSG:31370")
        return {}
    var status: Dictionary = evidence.get("status", {})
    if bool(status.get("runtime_approved", true)) or bool(status.get("realism_complete", true)):
        push_error("AtomiumHeroCore: provisional evidence was incorrectly promoted")
        return {}
    if not bool(status.get("sphere_skin_material_resolved", false)) or not bool(status.get("sphere_panel_topology_semantics_resolved", false)):
        push_error("AtomiumHeroCore: sphere skin source semantics unresolved")
        return {}
    if bool(status.get("sphere_panel_exact_runtime_layout_resolved", true)):
        push_error("AtomiumHeroCore: exact sphere seam layout was incorrectly promoted")
        return {}
    var contract: Dictionary = evidence.get("integration_contract", {})
    if not bool(contract.get("no_invented_panel_seams_without_layout_source", false)):
        push_error("AtomiumHeroCore: no-invented-panel-seams contract missing")
        return {}
    return evidence

func _load_visible_finish_contract() -> bool:
    if not FileAccess.file_exists(visible_finish_evidence_path):
        push_error("AtomiumHeroCore: visible finish evidence missing")
        return false
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(visible_finish_evidence_path))
    if typeof(parsed) != TYPE_DICTIONARY:
        push_error("AtomiumHeroCore: visible finish evidence invalid")
        return false
    var evidence := parsed as Dictionary
    if str(evidence.get("schema", "")) != "grand-bruxelles-atomium-visible-production-pass-v1" or str(evidence.get("crs", "")) != "EPSG:31370":
        push_error("AtomiumHeroCore: visible finish contract schema/CRS drifted")
        return false
    var ids: Dictionary = evidence.get("source_ids", {})
    if int(ids.get("osm_monument_relation_id", -1)) != 1243821 or int(ids.get("heritage_record_id", -1)) != 38328 or int(ids.get("target_base_sphere_id", -1)) != BASE_SPHERE_TOPOLOGY_ID:
        push_error("AtomiumHeroCore: visible finish stable ids drifted")
        return false
    var status: Dictionary = evidence.get("status", {})
    if not bool(status.get("stainless_skin_resolved", false)) or bool(status.get("support_pillars_resolved", true)) or bool(status.get("orientation_resolved", true)):
        push_error("AtomiumHeroCore: visible finish source bounds drifted")
        return false
    if not bool(status.get("base_sphere_window_presence_resolved", false)) or bool(status.get("exact_window_layout_resolved", true)):
        push_error("AtomiumHeroCore: visible finish glazing bounds drifted")
        return false
    var presentation: Dictionary = evidence.get("presentation_contract", {})
    if int(presentation.get("stainless_finish_revision", -1)) != VISIBLE_FINISH_REVISION:
        push_error("AtomiumHeroCore: finish revision drifted")
        return false
    if not bool(presentation.get("values_are_authored_presentation_not_measured_photometry", false)):
        push_error("AtomiumHeroCore: authored-photometry disclaimer missing")
        return false
    if not bool(presentation.get("no_support_geometry_added", false)) or not bool(presentation.get("no_orientation_change", false)) or not bool(presentation.get("no_source_geometry_movement", false)) or not bool(presentation.get("no_collision_change", false)) or not bool(presentation.get("no_camera_rescue", false)):
        push_error("AtomiumHeroCore: visible finish safety rails missing")
        return false
    visible_finish_contract_valid = true
    return true

func _make_materials() -> void:
    _sphere_material = StandardMaterial3D.new()
    sphere_skin_semantics_applied = bool(SPHERE_SKIN_SEMANTICS_SCRIPT.apply_to(_sphere_material))
    _tube_material = StandardMaterial3D.new()
    _apply_finish_materials(true)

func _apply_finish_materials(enabled: bool) -> void:
    if _sphere_material == null or _tube_material == null:
        return
    if enabled:
        _sphere_material.albedo_color = CANDIDATE_SPHERE_ALBEDO
        _sphere_material.metallic = CANDIDATE_SPHERE_METALLIC
        _sphere_material.roughness = CANDIDATE_SPHERE_ROUGHNESS
        _tube_material.albedo_color = CANDIDATE_TUBE_ALBEDO
        _tube_material.metallic = CANDIDATE_TUBE_METALLIC
        _tube_material.roughness = CANDIDATE_TUBE_ROUGHNESS
    else:
        _sphere_material.albedo_color = BASELINE_SPHERE_ALBEDO
        _sphere_material.metallic = BASELINE_SPHERE_METALLIC
        _sphere_material.roughness = BASELINE_SPHERE_ROUGHNESS
        _tube_material.albedo_color = BASELINE_TUBE_ALBEDO
        _tube_material.metallic = BASELINE_TUBE_METALLIC
        _tube_material.roughness = BASELINE_TUBE_ROUGHNESS
    _sphere_material.set_meta("atomium_visible_finish_revision", VISIBLE_FINISH_REVISION if enabled else 2)
    _sphere_material.set_meta("atomium_authored_non_photometric", true)
    _tube_material.set_meta("atomium_visible_finish_revision", VISIBLE_FINISH_REVISION if enabled else 2)
    _tube_material.set_meta("atomium_authored_non_photometric", true)

func _add_sphere(sphere_id: int, centre: Vector3) -> void:
    var sphere := SphereMesh.new()
    sphere.radius = source_sphere_diameter_m * 0.5
    sphere.height = source_sphere_diameter_m
    sphere.radial_segments = SPHERE_RADIAL_SEGMENTS
    sphere.rings = SPHERE_RINGS
    sphere.material = _sphere_material
    var instance := MeshInstance3D.new()
    instance.name = "Sphere_%02d" % sphere_id
    instance.mesh = sphere
    instance.position = centre
    instance.set_meta("atomium_sphere_id", sphere_id)
    add_child(instance)
    sphere_count += 1

func _add_tube(a: Vector3, b: Vector3) -> void:
    var delta := b - a
    var length := delta.length()
    if length <= 0.01:
        return
    var cylinder := CylinderMesh.new()
    cylinder.top_radius = source_tube_diameter_m * 0.5
    cylinder.bottom_radius = source_tube_diameter_m * 0.5
    cylinder.height = length
    cylinder.radial_segments = TUBE_RADIAL_SEGMENTS
    cylinder.material = _tube_material
    var instance := MeshInstance3D.new()
    instance.name = "Tube_%02d" % tube_count
    instance.mesh = cylinder
    instance.position = (a + b) * 0.5
    instance.quaternion = Quaternion(Vector3.UP, delta.normalized())
    add_child(instance)
    tube_count += 1

func measured_vertical_extent() -> Vector2:
    if not hero_built:
        return Vector2.ZERO
    var half_diameter := source_sphere_diameter_m * 0.5
    var min_y := INF
    var max_y := -INF
    for child: Node in get_children():
        if child is MeshInstance3D and child.has_meta("atomium_sphere_id"):
            var y := (child as MeshInstance3D).position.y
            min_y = minf(min_y, y - half_diameter)
            max_y = maxf(max_y, y + half_diameter)
    return Vector2(min_y, max_y)
