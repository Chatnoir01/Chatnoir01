extends Node3D
class_name BrusselsHistoricShopfront

## Reusable Brussels historic commercial-frontage vocabulary.
## Source-backed traits: wood + marble monumental shopfront language at Café
## Cirio, and the repeated commercial glazing/awning character of Rue de la
## Bourse. Exact envelope, bay widths, colours and PBR values are authored.

var visual_built := false
var glazed_bay_count := 0
var frame_pillar_count := 0
var has_marble_base := true
var has_wood_frame := true
var has_glazing := true
var has_shallow_awning := true
var embeds_business_branding := false
var claims_surveyed_dimensions := false
var claims_surveyed_mount := false

var _wood: StandardMaterial3D
var _marble: StandardMaterial3D
var _glass: StandardMaterial3D
var _metal: StandardMaterial3D
var _warm_interior: StandardMaterial3D

func _ready() -> void:
    build()

func build() -> bool:
    if visual_built:
        return true
    _make_materials()

    var glazing := Node3D.new()
    glazing.name = "Glazing"
    add_child(glazing)
    var frame := Node3D.new()
    frame.name = "Frame"
    add_child(frame)

    # Authored 7.2 m presentation envelope. It is a reusable family, not a
    # measured reconstruction of one protected storefront.
    _box(frame, "MarblePlinth", Vector3(7.2, 0.42, 0.24), Vector3(0.0, 0.21, 0.0), _marble)
    _box(frame, "WoodHeader", Vector3(7.2, 0.38, 0.26), Vector3(0.0, 3.12, 0.0), _wood)

    var bay_centers := [-2.35, 0.0, 2.35]
    for index: int in range(bay_centers.size()):
        var x := float(bay_centers[index])
        _box(glazing, "GlassBay_%d" % index, Vector3(2.02, 2.50, 0.075), Vector3(x, 1.72, 0.03), _glass)
        _box(glazing, "InteriorWarmth_%d" % index, Vector3(1.88, 2.34, 0.035), Vector3(x, 1.72, -0.04), _warm_interior)
        glazed_bay_count += 1

    for index: int in range(4):
        var x := -3.56 + float(index) * 2.37
        _box(frame, "WoodPillar_%d" % index, Vector3(0.22, 2.72, 0.27), Vector3(x, 1.78, 0.0), _wood)
        _box(frame, "MarblePillarBase_%d" % index, Vector3(0.34, 0.56, 0.31), Vector3(x, 0.28, 0.0), _marble)
        frame_pillar_count += 1

    # A restrained metal-and-glass-like canopy silhouette reflects the
    # documented common awning language of Rue de la Bourse without copying a
    # current tenant's branding or claiming exact historic dimensions.
    _box(self, "Awning", Vector3(7.45, 0.10, 1.12), Vector3(0.0, 3.48, 0.47), _metal)
    _box(self, "AwningFrontRail", Vector3(7.45, 0.12, 0.10), Vector3(0.0, 3.42, 1.00), _metal)

    visual_built = true
    return true

func _make_materials() -> void:
    _wood = StandardMaterial3D.new()
    _wood.albedo_color = Color(0.19, 0.075, 0.035, 1.0)
    _wood.roughness = 0.66
    _wood.metallic = 0.0

    _marble = StandardMaterial3D.new()
    _marble.albedo_color = Color(0.72, 0.67, 0.58, 1.0)
    _marble.roughness = 0.58
    _marble.metallic = 0.0

    _glass = StandardMaterial3D.new()
    _glass.albedo_color = Color(0.20, 0.31, 0.34, 0.42)
    _glass.roughness = 0.12
    _glass.metallic = 0.0
    _glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

    _metal = StandardMaterial3D.new()
    _metal.albedo_color = Color(0.09, 0.10, 0.11, 1.0)
    _metal.roughness = 0.38
    _metal.metallic = 0.72

    _warm_interior = StandardMaterial3D.new()
    _warm_interior.albedo_color = Color(0.42, 0.19, 0.075, 1.0)
    _warm_interior.emission_enabled = true
    _warm_interior.emission = Color(0.52, 0.22, 0.07, 1.0)
    _warm_interior.emission_energy_multiplier = 0.32
    _warm_interior.roughness = 0.82
    _warm_interior.metallic = 0.0

func _box(parent: Node, node_name: String, size: Vector3, pos: Vector3, material: Material) -> MeshInstance3D:
    var mesh := BoxMesh.new()
    mesh.size = size
    mesh.material = material
    var instance := MeshInstance3D.new()
    instance.name = node_name
    instance.mesh = mesh
    instance.position = pos
    instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
    parent.add_child(instance)
    return instance
