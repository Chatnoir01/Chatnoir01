extends Node3D

## Source-bounded presentation cue for the Atomium base-sphere glazing band.
##
## Official sources resolve that lower spheres carry windows and fix the sphere
## diameter at 18 m. They do not resolve an exact contemporary bay count, mullion
## layout or window dimensions. This component therefore adds only a continuous
## dark-glazing latitude cue on the already-existing Sphere_00 surface.
## Geometry, collision, hero anchor and camera remain unchanged.

@export_file("*.json") var evidence_path := "res://data/sources/laeken_jette/atomium_base_sphere_window_band_evidence.json"

const EXPECTED_SPHERE_DIAMETER_M := 18.0
const RADIAL_SEGMENTS := 48
const RINGS := 24

var band_built := false
var exact_layout_resolved := false
var authored_presentation_not_survey := true
var overlay: MeshInstance3D

var _enabled := true
var _band_center_uv := 0.53
var _band_half_width_uv := 0.075
var _surface_offset_m := 0.03

func build_on_sphere(base_center: Vector3, sphere_diameter_m: float) -> bool:
    if band_built:
        return true
    var evidence := _load_evidence()
    if evidence.is_empty():
        return false
    if absf(sphere_diameter_m - EXPECTED_SPHERE_DIAMETER_M) > 0.001:
        push_error("AtomiumBaseSphereWindowBand: source sphere diameter drifted")
        return false

    var binding: Dictionary = evidence.get("runtime_binding", {})
    var expected_center_raw: Variant = binding.get("base_sphere_local_center_m", [])
    if not expected_center_raw is Array or expected_center_raw.size() != 3:
        push_error("AtomiumBaseSphereWindowBand: base-sphere source centre missing")
        return false
    var expected_center := Vector3(
        float(expected_center_raw[0]),
        float(expected_center_raw[1]),
        float(expected_center_raw[2])
    )
    if base_center.distance_to(expected_center) > 0.001:
        push_error("AtomiumBaseSphereWindowBand: base-sphere topology binding drifted")
        return false

    var presentation: Dictionary = evidence.get("presentation_contract", {})
    _band_center_uv = float(presentation.get("band_center_uv", -1.0))
    _band_half_width_uv = float(presentation.get("band_half_width_uv", -1.0))
    _surface_offset_m = float(presentation.get("surface_offset_m", -1.0))
    authored_presentation_not_survey = bool(presentation.get("values_are_authored_presentation_not_survey", false))
    if _band_center_uv <= 0.0 or _band_center_uv >= 1.0 or _band_half_width_uv <= 0.0 or _band_half_width_uv >= 0.25:
        push_error("AtomiumBaseSphereWindowBand: authored UV cue contract invalid")
        return false
    if _surface_offset_m <= 0.0 or _surface_offset_m > 0.10:
        push_error("AtomiumBaseSphereWindowBand: surface offset outside presentation rail")
        return false
    if not authored_presentation_not_survey:
        push_error("AtomiumBaseSphereWindowBand: presentation disclaimer missing")
        return false

    position = base_center
    _build_overlay(sphere_diameter_m)
    band_built = overlay != null
    if band_built:
        set_meta("source_semantics", "official_lower_sphere_windows")
        set_meta("exact_layout_resolved", false)
        set_meta("authored_presentation_not_survey", true)
        set_meta("source_geometry_moved", false)
        set_meta("collision_changed", false)
        print("ATOMIUM_BASE_SPHERE_WINDOW_BAND_READY: sphere=Sphere_00 exact_layout=false authored_not_survey=true geometry_moved=false collision_changed=false")
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
    if bool(status.get("runtime_approved", true)) or bool(status.get("realism_complete", true)):
        push_error("AtomiumBaseSphereWindowBand: provisional cue was incorrectly promoted")
        return {}
    if not bool(status.get("base_sphere_window_presence_resolved", false)):
        push_error("AtomiumBaseSphereWindowBand: source window semantics unresolved")
        return {}
    exact_layout_resolved = bool(status.get("exact_window_layout_resolved", true))
    if exact_layout_resolved or bool(status.get("exact_window_count_resolved", true)) or bool(status.get("exact_window_dimensions_resolved", true)):
        push_error("AtomiumBaseSphereWindowBand: unresolved exact glazing layout was incorrectly promoted")
        return {}
    var presentation: Dictionary = evidence.get("presentation_contract", {})
    if not bool(presentation.get("no_exact_window_count_claim", false)) or not bool(presentation.get("no_exact_mullion_layout_claim", false)) or not bool(presentation.get("no_exact_window_dimensions_claim", false)):
        push_error("AtomiumBaseSphereWindowBand: no-invented-layout contract missing")
        return {}
    if not bool(presentation.get("no_source_geometry_movement", false)) or not bool(presentation.get("no_collision_change", false)) or not bool(presentation.get("no_camera_rescue", false)):
        push_error("AtomiumBaseSphereWindowBand: production safety rails missing")
        return {}
    return evidence

func _build_overlay(sphere_diameter_m: float) -> void:
    var shader := Shader.new()
    shader.code = """
shader_type spatial;

uniform float band_center = 0.53;
uniform float band_half_width = 0.075;
uniform vec3 glass_color = vec3(0.035, 0.055, 0.075);

void fragment() {
    if (abs(UV.y - band_center) > band_half_width) {
        discard;
    }
    ALBEDO = glass_color;
    METALLIC = 0.18;
    ROUGHNESS = 0.10;
}
"""
    var material := ShaderMaterial.new()
    material.shader = shader
    material.set_shader_parameter("band_center", _band_center_uv)
    material.set_shader_parameter("band_half_width", _band_half_width_uv)
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
    overlay.name = "BaseSphereWindowBand_SemanticsOnly"
    overlay.mesh = sphere
    overlay.visible = _enabled
    overlay.set_meta("source_semantics", "official_lower_sphere_windows")
    overlay.set_meta("exact_layout_resolved", false)
    overlay.set_meta("authored_presentation_not_survey", true)
    add_child(overlay)

func set_enabled(enabled: bool) -> void:
    _enabled = enabled
    if is_instance_valid(overlay):
        overlay.visible = enabled

func enabled() -> bool:
    return _enabled

func source_geometry_moved() -> bool:
    return false

func collision_changed() -> bool:
    return false
