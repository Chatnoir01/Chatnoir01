extends RefCounted
class_name BrusselsTreeGroundContactAsset

## Local contact-shadow presentation for existing source-positioned corridor trees.
## OSM proves tree existence and horizontal position only. The dimensions,
## opacity and tone below are authored presentation values: they do not claim
## real soil, root flare, tree-pit geometry, species, health or photometry.

const ASSET_FAMILY := "brussels_tree_ground_contact_v1"
const GROUND_CONTACT_REVISION := 1
const GROUND_CONTACT_RADIUS := 0.62
const GROUND_CONTACT_HEIGHT := 0.012
const SOURCE_LABEL := "OpenStreetMap contributors via Overpass API; tree existence/position only; ODbL-1.0"

static func ground_contact_material() -> ShaderMaterial:
    var shader := Shader.new()
    shader.code = """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley;

uniform vec4 contact_color : source_color = vec4(0.055, 0.050, 0.042, 0.34);

void fragment() {
    vec2 p = UV * 2.0 - 1.0;
    float r = length(p);
    float fade = 1.0 - smoothstep(0.30, 1.0, r);
    ALBEDO = contact_color.rgb;
    ALPHA = contact_color.a * fade;
    ROUGHNESS = 1.0;
    METALLIC = 0.0;
    SPECULAR = 0.0;
}
"""
    var material := ShaderMaterial.new()
    material.shader = shader
    material.set_meta("asset_family", ASSET_FAMILY)
    material.set_meta("ground_contact_revision", GROUND_CONTACT_REVISION)
    material.set_meta("source", SOURCE_LABEL)
    material.set_meta("license", "ODbL-1.0")
    material.set_meta("source_ground_treatment_claimed", false)
    material.set_meta("source_dimensions_measured", false)
    material.set_meta("exact_rgb_is_photometric_measurement", false)
    material.set_meta("visual_recipe_provenance", "authored_presentation_not_source_measurement")
    return material

static func create_ground_contact_mesh(material: Material) -> PlaneMesh:
    var mesh := PlaneMesh.new()
    mesh.size = Vector2(GROUND_CONTACT_RADIUS * 2.0, GROUND_CONTACT_RADIUS * 2.0)
    mesh.subdivide_width = 0
    mesh.subdivide_depth = 0
    mesh.material = material
    return mesh

static func ground_contact_transform(base_position: Vector3, osm_id: int) -> Transform3D:
    var phase := deg_to_rad(float(abs(osm_id * 29 + 17) % 360))
    var sx := 0.90 + float(abs(osm_id * 13 + 5) % 9) * 0.018
    var sz := 0.88 + float(abs(osm_id * 17 + 3) % 11) * 0.016
    var basis := Basis(Vector3.UP, phase).scaled(Vector3(sx, 1.0, sz))
    return Transform3D(basis, base_position + Vector3(0.0, GROUND_CONTACT_HEIGHT, 0.0))
