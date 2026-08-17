extends RefCounted
class_name BrusselsStreetTreeAsset

## Reusable low-poly Brussels street-tree presentation asset.
## OSM may prove that a tree exists at a point, but the source snapshot used by
## Grand Bruxelles does not prove species, trunk diameter, crown size or height.
## All dimensions/colors below are therefore deterministic authored presentation
## values. Location/provenance remain owned by the caller.

const ASSET_FAMILY := "brussels_street_tree_v1"
const FOLIAGE_LOBE_COUNT := 6
const TRUNK_HEIGHT := 2.6
const TRUNK_TOP_RADIUS := 0.15
const TRUNK_BOTTOM_RADIUS := 0.22
const FOLIAGE_RADIUS := 1.05
const FOLIAGE_HEIGHT := 2.10
const LIGHT_LOBE_INDICES := [0, 4]
const LOBE_OFFSETS := [
    Vector3(0.0, 3.35, 0.0),
    Vector3(0.72, 3.18, 0.02),
    Vector3(-0.62, 3.20, 0.38),
    Vector3(0.05, 3.10, -0.72),
    Vector3(0.22, 3.82, 0.22),
    Vector3(-0.38, 3.62, -0.30),
]
const LOBE_SCALES := [
    Vector3(1.02, 0.92, 1.08),
    Vector3(0.82, 0.78, 0.88),
    Vector3(0.88, 0.82, 0.78),
    Vector3(0.86, 0.74, 0.92),
    Vector3(0.72, 0.78, 0.70),
    Vector3(0.74, 0.70, 0.82),
]

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
    return {"foliage_dark": foliage_dark, "foliage_light": foliage_light, "trunk": trunk}

static func create_trunk_mesh(material: Material) -> CylinderMesh:
    var mesh := CylinderMesh.new()
    mesh.top_radius = TRUNK_TOP_RADIUS
    mesh.bottom_radius = TRUNK_BOTTOM_RADIUS
    mesh.height = TRUNK_HEIGHT
    mesh.radial_segments = 8
    mesh.rings = 1
    mesh.material = material
    return mesh

static func create_foliage_mesh(material: Material) -> SphereMesh:
    var mesh := SphereMesh.new()
    mesh.radius = FOLIAGE_RADIUS
    mesh.height = FOLIAGE_HEIGHT
    mesh.radial_segments = 12
    mesh.rings = 6
    mesh.material = material
    return mesh

static func trunk_transform(base_position: Vector3) -> Transform3D:
    return Transform3D(Basis.IDENTITY, base_position + Vector3(0.0, TRUNK_HEIGHT * 0.5, 0.0))

static func foliage_is_light(index: int) -> bool:
    return index in LIGHT_LOBE_INDICES

static func foliage_lobe_transform(base_position: Vector3, osm_id: int, index: int) -> Transform3D:
    var phase := deg_to_rad(float(abs(osm_id) % 360))
    var jitter := float((abs(osm_id) % 13) - 6) * 0.018
    var offset: Vector3 = LOBE_OFFSETS[index]
    var rotated := Vector3(
        offset.x * cos(phase) - offset.z * sin(phase),
        offset.y + jitter,
        offset.x * sin(phase) + offset.z * cos(phase)
    )
    var basis := Basis.IDENTITY.scaled(LOBE_SCALES[index] as Vector3)
    return Transform3D(basis, base_position + rotated)

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
    trunk_mesh.mesh = create_trunk_mesh(materials["trunk"] as Material)
    trunk_mesh.transform = trunk_transform(Vector3.ZERO)
    visual.add_child(trunk_mesh)

    for index: int in range(FOLIAGE_LOBE_COUNT):
        var lobe := MeshInstance3D.new()
        lobe.name = "FoliageLobe_%d" % index
        var key := "foliage_light" if foliage_is_light(index) else "foliage_dark"
        lobe.mesh = create_foliage_mesh(materials[key] as Material)
        lobe.transform = foliage_lobe_transform(Vector3.ZERO, osm_id, index)
        visual.add_child(lobe)
    return visual
