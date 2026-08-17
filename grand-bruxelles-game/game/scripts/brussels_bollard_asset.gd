extends RefCounted
class_name BrusselsBollardAsset

## Reusable authored presentation for source-backed bollard points.
## OpenStreetMap proves bollard presence and point position only for this lot.
## Shape, dimensions, material and colour below are conservative deterministic
## presentation values and are explicitly not source measurements or a claim of
## one specific Brussels manufacturer/model.

const ASSET_FAMILY := "brussels_bollard_v1"
const BODY_HEIGHT := 0.82
const BODY_RADIUS := 0.105
const CAP_HEIGHT := 0.12
const CAP_RADIUS := 0.13
const COLLISION_HEIGHT := 0.94
const COLLISION_RADIUS := 0.13

static func create_materials() -> Dictionary:
    var body := StandardMaterial3D.new()
    body.albedo_color = Color(0.105, 0.115, 0.12, 1.0)
    body.roughness = 0.72
    body.metallic = 0.28

    var cap := StandardMaterial3D.new()
    cap.albedo_color = Color(0.18, 0.19, 0.19, 1.0)
    cap.roughness = 0.66
    cap.metallic = 0.34

    return {"body": body, "cap": cap}

static func create_body_mesh(material: Material) -> CylinderMesh:
    var mesh := CylinderMesh.new()
    mesh.top_radius = BODY_RADIUS * 0.94
    mesh.bottom_radius = BODY_RADIUS
    mesh.height = BODY_HEIGHT
    mesh.radial_segments = 10
    mesh.rings = 1
    mesh.material = material
    return mesh

static func create_cap_mesh(material: Material) -> CylinderMesh:
    var mesh := CylinderMesh.new()
    mesh.top_radius = CAP_RADIUS * 0.78
    mesh.bottom_radius = CAP_RADIUS
    mesh.height = CAP_HEIGHT
    mesh.radial_segments = 10
    mesh.rings = 1
    mesh.material = material
    return mesh

static func body_transform(base_position: Vector3) -> Transform3D:
    return Transform3D(Basis.IDENTITY, base_position + Vector3(0.0, BODY_HEIGHT * 0.5, 0.0))

static func cap_transform(base_position: Vector3) -> Transform3D:
    return Transform3D(Basis.IDENTITY, base_position + Vector3(0.0, BODY_HEIGHT + CAP_HEIGHT * 0.5, 0.0))

static func collision_shape() -> CylinderShape3D:
    var shape := CylinderShape3D.new()
    shape.radius = COLLISION_RADIUS
    shape.height = COLLISION_HEIGHT
    return shape
