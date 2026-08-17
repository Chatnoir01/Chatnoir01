extends RefCounted
class_name BrusselsStreetLampAsset

## Reusable authored presentation for source-backed OSM street-lamp points.
## OSM proves lamp presence and horizontal position only. Height, silhouette,
## material, colour and lighting below are presentation conventions, not survey
## measurements, manufacturer identification or photometric claims.

const ASSET_FAMILY := "brussels_street_lamp_v1"
const POLE_HEIGHT := 6.3
const POLE_RADIUS := 0.085
const ARM_HEIGHT := 0.12
const ARM_LENGTH := 0.90
const LUMINAIRE_LENGTH := 0.62
const LUMINAIRE_WIDTH := 0.28
const LUMINAIRE_HEIGHT := 0.18
const COLLISION_HEIGHT := 6.3
const COLLISION_RADIUS := 0.11

static func create_materials() -> Dictionary:
    var metal := StandardMaterial3D.new()
    metal.albedo_color = Color(0.115, 0.125, 0.13, 1.0)
    metal.roughness = 0.68
    metal.metallic = 0.32

    var luminaire := StandardMaterial3D.new()
    luminaire.albedo_color = Color(0.44, 0.45, 0.43, 1.0)
    luminaire.roughness = 0.58
    luminaire.metallic = 0.18
    return {"metal": metal, "luminaire": luminaire}

static func create_pole_mesh(material: Material) -> CylinderMesh:
    var mesh := CylinderMesh.new()
    mesh.top_radius = POLE_RADIUS * 0.82
    mesh.bottom_radius = POLE_RADIUS
    mesh.height = POLE_HEIGHT
    mesh.radial_segments = 10
    mesh.rings = 1
    mesh.material = material
    return mesh

static func create_arm_mesh(material: Material) -> BoxMesh:
    var mesh := BoxMesh.new()
    mesh.size = Vector3(ARM_LENGTH, ARM_HEIGHT, ARM_HEIGHT)
    mesh.material = material
    return mesh

static func create_luminaire_mesh(material: Material) -> BoxMesh:
    var mesh := BoxMesh.new()
    mesh.size = Vector3(LUMINAIRE_LENGTH, LUMINAIRE_HEIGHT, LUMINAIRE_WIDTH)
    mesh.material = material
    return mesh

static func pole_transform(base_position: Vector3) -> Transform3D:
    return Transform3D(Basis.IDENTITY, base_position + Vector3(0.0, POLE_HEIGHT * 0.5, 0.0))

static func arm_transform(base_position: Vector3) -> Transform3D:
    return Transform3D(Basis.IDENTITY, base_position + Vector3(ARM_LENGTH * 0.5, POLE_HEIGHT - 0.15, 0.0))

static func luminaire_transform(base_position: Vector3) -> Transform3D:
    return Transform3D(Basis.IDENTITY, base_position + Vector3(ARM_LENGTH + LUMINAIRE_LENGTH * 0.28, POLE_HEIGHT - 0.18, 0.0))

static func collision_shape() -> CylinderShape3D:
    var shape := CylinderShape3D.new()
    shape.radius = COLLISION_RADIUS
    shape.height = COLLISION_HEIGHT
    return shape
