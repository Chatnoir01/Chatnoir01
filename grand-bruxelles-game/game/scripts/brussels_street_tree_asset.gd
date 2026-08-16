extends RefCounted
class_name BrusselsStreetTreeAsset

## Reusable low-poly Brussels street-tree presentation asset.
## OSM may prove that a tree exists at a point, but the source snapshot used by
## Grand Bruxelles does not prove species, trunk diameter, crown size or height.
## All dimensions/colors below are therefore deterministic authored presentation
## values. Location/provenance remain owned by the caller.

const ASSET_FAMILY := "brussels_street_tree_v1"
const FOLIAGE_LOBE_COUNT := 6

static func create_materials() -> Dictionary:
    var foliage_dark := StandardMaterial3D.new()
    foliage_dark.albedo_color = Color(0.145, 0.245, 0.115, 1.0)
    foliage_dark.roughness = 0.97
    foliage_dark.metallic = 0.0

    var foliage_light := StandardMaterial3D.new()
    foliage_light.albedo_color = Color(0.235, 0.345, 0.165, 1.0)
    foliage_light.roughness = 0.96
    foliage_light.metallic = 0.0

    var trunk := StandardMaterial3D.new()
    trunk.albedo_color = Color(0.175, 0.125, 0.085, 1.0)
    trunk.roughness = 0.99
    trunk.metallic = 0.0

    return {
        "foliage_dark": foliage_dark,
        "foliage_light": foliage_light,
        "trunk": trunk,
    }

static func populate(tree: StaticBody3D, osm_id: int, materials: Dictionary) -> Node3D:
    var visual := Node3D.new()
    visual.name = "StreetTreeVisual"
    visual.set_meta("asset_family", ASSET_FAMILY)
    visual.set_meta("source_dimensions_measured", false)
    visual.set_meta("species_claimed", false)
    tree.add_child(visual)

    tree.set_meta("asset_family", ASSET_FAMILY)
    tree.set_meta("source_dimensions_measured", false)
    tree.set_meta("species_claimed", false)
    tree.set_meta("visual_dimensions_provenance", "authored_presentation_not_source_measurement")

    var trunk_mesh := MeshInstance3D.new()
    trunk_mesh.name = "Trunk"
    var cylinder := CylinderMesh.new()
    cylinder.top_radius = 0.15
    cylinder.bottom_radius = 0.22
    cylinder.height = 2.6
    cylinder.radial_segments = 8
    cylinder.rings = 1
    trunk_mesh.mesh = cylinder
    trunk_mesh.material_override = materials["trunk"] as Material
    trunk_mesh.position.y = 1.3
    visual.add_child(trunk_mesh)

    var phase := deg_to_rad(float(abs(osm_id) % 360))
    var crown_y_jitter := float((abs(osm_id) % 13) - 6) * 0.018
    var offsets := [
        Vector3(0.0, 3.35, 0.0),
        Vector3(0.72, 3.18, 0.02),
        Vector3(-0.62, 3.20, 0.38),
        Vector3(0.05, 3.10, -0.72),
        Vector3(0.22, 3.82, 0.22),
        Vector3(-0.38, 3.62, -0.30),
    ]
    var scales := [
        Vector3(1.02, 0.92, 1.08),
        Vector3(0.82, 0.78, 0.88),
        Vector3(0.88, 0.82, 0.78),
        Vector3(0.86, 0.74, 0.92),
        Vector3(0.72, 0.78, 0.70),
        Vector3(0.74, 0.70, 0.82),
    ]

    for index: int in range(FOLIAGE_LOBE_COUNT):
        var lobe := MeshInstance3D.new()
        lobe.name = "FoliageLobe_%d" % index
        var sphere := SphereMesh.new()
        sphere.radius = 1.05
        sphere.height = 2.10
        sphere.radial_segments = 12
        sphere.rings = 6
        lobe.mesh = sphere
        lobe.material_override = (materials["foliage_light"] if index in [0, 4] else materials["foliage_dark"]) as Material
        var offset: Vector3 = offsets[index]
        var rotated_x := offset.x * cos(phase) - offset.z * sin(phase)
        var rotated_z := offset.x * sin(phase) + offset.z * cos(phase)
        lobe.position = Vector3(rotated_x, offset.y + crown_y_jitter, rotated_z)
        lobe.scale = scales[index]
        visual.add_child(lobe)

    return visual
