extends Node3D

## Source-bounded presentation cue for Atomium topology sphere_id=0.
## Stable source/topology IDs are binding truth; node names are debug-only.
## Official sources resolve lower-sphere window presence and the 18 m sphere
## diameter, but not an exact contemporary bay count, mullion layout or dimensions.

@export_file("*.json") var evidence_path := "res://data/sources/laeken_jette/atomium_visible_production_pass_evidence.json"

const EXPECTED_SPHERE_DIAMETER_M := 18.0
const EXPECTED_TARGET_SPHERE_ID := 0
const EXPECTED_MONUMENT_RELATION_ID := 1243821
const EXPECTED_HERITAGE_RECORD_ID := 38328
const RADIAL_SEGMENTS := 48
const RINGS := 24

var band_built := false
var exact_layout_resolved := false
var authored_presentation_not_survey := true
var overlay: MeshInstance3D
var bound_sphere_id := -1
var monument_relation_id := -1
var heritage_record_id := -1

var _enabled := true
var _band_center_uv := 0.53
var _band_half_width_uv := 0.075
var _surface_offset_m := 0.03

func build_on_sphere(sphere_id: int, sphere_center: Vector3, sphere_diameter_m: float) -> bool:
    if band_built:
        return true
    var evidence := _load_evidence()
    if evidence.is_empty():
        return false
    if sphere_id != EXPECTED_TARGET_SPHERE_ID:
        push_error("AtomiumBaseSphereWindowBand: target sphere id drifted: %d" % sphere_id)
        return false
    if absf(sphere_diameter_m - EXPECTED_SPHERE_DIAMETER_M) > 0.001:
        push_error("AtomiumBaseSphereWindowBand: source sphere diameter drifted")
        return false

    var ids: Dictionary = evidence.get("source_ids", {})
    monument_relation_id = int(ids.get("osm_monument_relation_id", -1))
    heritage_record_id = int(ids.get("heritage_record_id", -1))
    var evidence_sphere_id := int(ids.get("target_base_sphere_id", -1))
    if monument_relation_id != EXPECTED_MONUMENT_RELATION_ID:
        push_error("AtomiumBaseSphereWindowBand: monument relation id drifted")
        return false
    if heritage_record_id != EXPECTED_HERITAGE_RECORD_ID:
        push_error("AtomiumBaseSphereWindowBand: heritage record id drifted")
        return false
    if evidence_sphere_id != sphere_id:
        push_error("AtomiumBaseSphereWindowBand: evidence topology id does not match runtime id")
        return false

    var identity: Dictionary = evidence.get("identity_contract", {})
    if not bool(identity.get("selection_by_display_name_forbidden", false)):
        push_error("AtomiumBaseSphereWindowBand: stable-id selection rail missing")
        return false
    if int(identity.get("target_base_sphere_id", -1)) != sphere_id:
        push_error("AtomiumBaseSphereWindowBand: identity target sphere drifted")
        return false

    var presentation: Dictionary = evidence.get("presentation_contract", {})
    var cue: Dictionary = presentation.get("base_sphere_glazing_cue", {})
    _band_center_uv = float(cue.get("band_center_uv", -1.0))
    _band_half_width_uv = float(cue.get("band_half_width_uv", -1.0))
    _surface_offset_m = float(cue.get("surface_offset_m", -1.0))
    authored_presentation_not_survey = bool(presentation.get("values_are_authored_presentation_not_measured_photometry", false))
    if _band_center_uv <= 0.0 or _band_center_uv >= 1.0 or _band_half_width_uv <= 0.0 or _band_half_width_uv >= 0.25:
        push_error("AtomiumBaseSphereWindowBand: authored UV cue contract invalid")
        return false
    if _surface_offset_m <= 0.0 or _surface_offset_m > 0.10:
        push_error("AtomiumBaseSphereWindowBand: surface offset outside presentation rail")
        return false
    if not authored_presentation_not_survey or bool(cue.get("exact_layout_claim", true)):
        push_error("AtomiumBaseSphereWindowBand: no-invented-layout disclaimer missing")
        return false

    bound_sphere_id = sphere_id
    position = sphere_center
    _build_overlay(sphere_diameter_m)
    band_built = overlay != null
    if band_built:
        set_meta("osm_monument_relation_id", monument_relation_id)
        set_meta("heritage_record_id", heritage_record_id)
        set_meta("target_sphere_id", bound_sphere_id)
        set_meta("selection_by_display_name", false)
        set_meta("exact_layout_resolved", false)
        set_meta("authored_presentation_not_survey", true)
        set_meta("source_geometry_moved", false)
        set_meta("collision_changed", false)
        print("ATOMIUM_BASE_SPHERE_WINDOW_BAND_READY: relation_id=%d heritage_id=%d sphere_id=%d exact_layout=false authored_not_survey=true geometry_moved=false collision_changed=false" % [monument_relation_id, heritage_record_id, bound_sphere_id])
    return band_built

func _load_evidence() -> Dictionary:
    if not FileAccess.file_exists(evidence_path):
        push_error("AtomiumBaseSphereWindowBand: evidence missing")
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(evidence_path))
    if typeof(parsed) != TYPE_DICTIONARY:
        push_error("AtomiumBaseSphereWindowBand: evidence is not a dictionary")
        return {}
    var evidence := parsed as Dictionary
    if str(evidence.get("crs", "")) != "EPSG:31370":
        push_error("AtomiumBaseSphereWindowBand: evidence CRS drifted")
        return {}
    var status: Dictionary = evidence.get("status", {})
    if not bool(status.get("base_sphere_window_presence_resolved", false)):
        push_error("AtomiumBaseSphereWindowBand: source window semantics unresolved")
        return {}
    exact_layout_resolved = bool(status.get("exact_window_layout_resolved", true))
    if exact_layout_resolved or bool(status.get("exact_window_count_resolved", true)) or bool(status.get("exact_window_dimensions_resolved", true)):
        push_error("AtomiumBaseSphereWindowBand: unresolved exact glazing layout was incorrectly promoted")
        return {}
    var presentation: Dictionary = evidence.get("presentation_contract", {})
    if not bool(presentation.get("no_source_geometry_movement", false)) or not bool(presentation.get("no_collision_change", false)) or not bool(presentation.get("no_camera_rescue", false)):
        push_error("AtomiumBaseSphereWindowBand: production safety rails missing")
        return {}
    return evidence

func _build_overlay(sphere_diameter_m: float) -> void:
    var shader := Shader.new()
    shader.code = """
shader_type spatial;
render_mode cull_back;

uniform float band_center = 0.53;
uniform float band_half_width = 0.075;
uniform vec3 glass_color = vec3(0.030, 0.050, 0.075);

void fragment() {
    if (abs(UV.y - band_center) > band_half_width) {
        discard;
    }
    ALBEDO = glass_color;
    METALLIC = 0.20;
    ROUGHNESS = 0.095;
}
"""
    var material := ShaderMaterial.new()
    material.shader = shader
    material.set_shader_parameter("band_center", _band_center_uv)
    material.set_shader_parameter("band_half_width", _band_half_width_uv)
    material.set_meta("atomium_target_sphere_id", bound_sphere_id)
    material.set_meta("atomium_window_band_semantics_only", true)
    material.set_meta("atomium_exact_window_layout", false)
    material.set_meta("atomium_authored_not_survey", true)

    var sphere := SphereMesh.new()
    sphere.radius = sphere_diameter_m * 0.5 + _surface_offset_m
    sphere.height = sphere_diameter_m + _surface_offset_m * 2.0
    sphere.radial_segments = RADIAL_SEGMENTS
    sphere.rings = RINGS
    sphere.material = material

    overlay = MeshInstance3D.new()
    overlay.name = "AtomiumSphereID0WindowBand"
    overlay.mesh = sphere
    overlay.visible = _enabled
    overlay.set_meta("atomium_target_sphere_id", bound_sphere_id)
    overlay.set_meta("selection_by_display_name", false)
    add_child(overlay)

func set_enabled(enabled: bool) -> void:
    _enabled = enabled
    if is_instance_valid(overlay):
        overlay.visible = enabled

func enabled() -> bool:
    return _enabled

func target_sphere_id() -> int:
    return bound_sphere_id

func source_geometry_moved() -> bool:
    return false

func collision_changed() -> bool:
    return false
