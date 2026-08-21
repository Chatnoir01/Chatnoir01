extends RefCounted
class_name BrusselsBollardAsset

## Reusable authored presentation for source-backed bollard points.
## OpenStreetMap proves bollard presence and point position only for this lot.
## Shape, dimensions, material and colour below are conservative deterministic
## presentation values and are explicitly not source measurements or a claim of
## one specific Brussels manufacturer/model.

const ASSET_FAMILY := "brussels_bollard_v1"
const PRESENTATION_REVISION := 2
const BODY_HEIGHT := 0.80
const BODY_RADIUS := 0.115
const CAP_HEIGHT := 0.14
const CAP_RADIUS := 0.14
const COLLISION_HEIGHT := 0.94
const COLLISION_RADIUS := 0.13

static func create_materials() -> Dictionary:
    var body := StandardMaterial3D.new()
    body.albedo_color = Color(0.075, 0.082, 0.086, 1.0)
    body.roughness = 0.78
    body.metallic = 0.20

    var cap := StandardMaterial3D.new()
    cap.albedo_color = Color(0.16, 0.17, 0.17, 1.0)
    cap.roughness = 0.60
    cap.metallic = 0.36

    return {"body": body, "cap": cap}

static func create_body_mesh(material: Material) -> CylinderMesh:
    var mesh := CylinderMesh.new()
    mesh.top_radius = BODY_RADIUS * 0.76
    mesh.bottom_radius = BODY_RADIUS
    mesh.height = BODY_HEIGHT
    mesh.radial_segments = 12
    mesh.rings = 1
    mesh.material = material
    return mesh

static func create_cap_mesh(material: Material) -> CylinderMesh:
    var mesh := CylinderMesh.new()
    mesh.top_radius = CAP_RADIUS * 0.57
    mesh.bottom_radius = CAP_RADIUS
    mesh.height = CAP_HEIGHT
    mesh.radial_segments = 12
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
