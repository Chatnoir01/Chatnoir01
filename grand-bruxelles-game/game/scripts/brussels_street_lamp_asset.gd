extends RefCounted
class_name BrusselsStreetLampAsset

## Reusable authored presentation for source-backed OSM street-lamp points.
## OSM proves lamp presence and horizontal position only. Height, silhouette,
## material, colour and lighting below are presentation conventions, not survey
## measurements, manufacturer identification or photometric claims.

const ASSET_FAMILY := "brussels_street_lamp_v1"
const PRESENTATION_REVISION := 4
const POLE_HEIGHT := 6.3
const POLE_RADIUS := 0.14
const ARM_RADIUS := 0.09
const ARM_LENGTH := 1.12
const LUMINAIRE_LENGTH := 1.00
const LUMINAIRE_RADIUS := 0.22
const LUMINAIRE_DEPTH_SCALE := 0.76
const COLLISION_HEIGHT := 6.3
const COLLISION_RADIUS := 0.11

static func create_materials() -> Dictionary:
    var metal := StandardMaterial3D.new()
    metal.albedo_color = Color(0.055, 0.062, 0.066, 1.0)
    metal.roughness = 0.54
    metal.metallic = 0.45

    var luminaire := StandardMaterial3D.new()
    luminaire.albedo_color = Color(0.78, 0.75, 0.64, 1.0)
    luminaire.roughness = 0.38
    luminaire.metallic = 0.06
    return {"metal": metal, "luminaire": luminaire}

static func create_pole_mesh(material: Material) -> CylinderMesh:
    var mesh := CylinderMesh.new()
    mesh.top_radius = POLE_RADIUS * 0.66
    mesh.bottom_radius = POLE_RADIUS
    mesh.height = POLE_HEIGHT
    mesh.radial_segments = 10
    mesh.rings = 1
    mesh.material = material
    return mesh

static func create_arm_mesh(material: Material) -> CylinderMesh:
    var mesh := CylinderMesh.new()
    mesh.top_radius = ARM_RADIUS * 0.84
    mesh.bottom_radius = ARM_RADIUS
    mesh.height = ARM_LENGTH
    mesh.radial_segments = 8
    mesh.rings = 1
    mesh.material = material
    return mesh

static func create_luminaire_mesh(material: Material) -> CapsuleMesh:
    var mesh := CapsuleMesh.new()
    mesh.radius = LUMINAIRE_RADIUS
    mesh.height = LUMINAIRE_LENGTH
    mesh.radial_segments = 10
    mesh.rings = 4
    mesh.material = material
    return mesh

static func pole_transform(base_position: Vector3) -> Transform3D:
    return Transform3D(Basis.IDENTITY, base_position + Vector3(0.0, POLE_HEIGHT * 0.5, 0.0))

static func arm_transform(base_position: Vector3) -> Transform3D:
    var basis := Basis(Vector3(0.0, 0.0, 1.0), deg_to_rad(-90.0))
    return Transform3D(basis, base_position + Vector3(ARM_LENGTH * 0.5, POLE_HEIGHT - 0.13, 0.0))

static func luminaire_transform(base_position: Vector3) -> Transform3D:
    var basis := Basis(Vector3(0.0, 0.0, 1.0), deg_to_rad(-90.0))
    basis = basis.scaled(Vector3(1.0, 1.0, LUMINAIRE_DEPTH_SCALE))
    return Transform3D(basis, base_position + Vector3(ARM_LENGTH + LUMINAIRE_LENGTH * 0.30, POLE_HEIGHT - 0.20, 0.0))

static func collision_shape() -> CylinderShape3D:
    var shape := CylinderShape3D.new()
    shape.radius = COLLISION_RADIUS
    shape.height = COLLISION_HEIGHT
    return shape
