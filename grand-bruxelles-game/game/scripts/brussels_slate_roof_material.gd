extends RefCounted

const SLATE_COLOR := Color(0.115, 0.135, 0.155, 1.0)
const SLATE_ROUGHNESS := 0.84

static func create_material() -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = SLATE_COLOR
    material.roughness = SLATE_ROUGHNESS
    material.metallic = 0.0
    material.cull_mode = BaseMaterial3D.CULL_BACK
    return material
