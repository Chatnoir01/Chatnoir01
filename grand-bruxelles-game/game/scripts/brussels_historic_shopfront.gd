extends Node3D
class_name BrusselsHistoricShopfront

## Reusable Brussels historic commercial-frontage vocabulary.
## Source-backed traits: wood + marble monumental neo-Renaissance shopfront
## language at Café Cirio, and the repeated commercial glazing/awning character
## of Rue de la Bourse. Exact envelope, bay widths, colours and PBR values are
## authored and are not a measured reconstruction.

var visual_built := false
var glazed_bay_count := 0
var transom_count := 0
var frame_pillar_count := 0
var capital_count := 0
var has_marble_base := true
var has_wood_frame := true
var has_glazing := true
var has_shallow_awning := true
var has_neo_renaissance_cornice := true
var embeds_business_branding := false
var claims_surveyed_dimensions := false
var claims_surveyed_mount := false

var _wood: StandardMaterial3D
var _wood_highlight: StandardMaterial3D
var _marble: StandardMaterial3D
var _glass: StandardMaterial3D
var _transom_glass: StandardMaterial3D
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

    # Authored 7.2 m presentation envelope. This family communicates the
    # documented material/commercial vocabulary without claiming Cirio's exact
    # bay dimensions or ornament profile.
    _box(frame, "MarblePlinth", Vector3(7.2, 0.42, 0.24), Vector3(0.0, 0.21, 0.0), _marble)
    _box(frame, "WoodBelt", Vector3(7.2, 0.24, 0.27), Vector3(0.0, 3.05, 0.0), _wood)
    _box(frame, "WoodCorniceLower", Vector3(7.35, 0.18, 0.31), Vector3(0.0, 3.79, -0.01), _wood_highlight)
    _box(frame, "WoodCorniceUpper", Vector3(7.58, 0.16, 0.36), Vector3(0.0, 4.00, -0.02), _wood)

    var bay_centers := [-2.35, 0.0, 2.35]
    for index: int in range(bay_centers.size()):
        var x := float(bay_centers[index])
        _box(glazing, "GlassBay_%d" % index, Vector3(2.02, 2.36, 0.075), Vector3(x, 1.65, 0.03), _glass)
        _box(glazing, "InteriorWarmth_%d" % index, Vector3(1.88, 2.20, 0.035), Vector3(x, 1.65, -0.04), _warm_interior)
        _box(glazing, "TransomGlass_%d" % index, Vector3(1.88, 0.48, 0.07), Vector3(x, 3.39, 0.03), _transom_glass)
        _box(frame, "TransomSill_%d" % index, Vector3(2.08, 0.12, 0.26), Vector3(x, 3.12, 0.0), _wood_highlight)
        glazed_bay_count += 1
        transom_count += 1

    for index: int in range(4):
        var x := -3.56 + float(index) * 2.37
        _box(frame, "WoodPillar_%d" % index, Vector3(0.22, 3.20, 0.27), Vector3(x, 1.86, 0.0), _wood)
        _box(frame, "MarblePillarBase_%d" % index, Vector3(0.36, 0.56, 0.32), Vector3(x, 0.28, 0.0), _marble)
        _box(frame, "PillarCapital_%d" % index, Vector3(0.48, 0.20, 0.34), Vector3(x, 3.69, 0.0), _wood_highlight)
        frame_pillar_count += 1
        capital_count += 1

    # The street inventory documents a common awning protecting the commercial
    # ground floors. Its exact depth, structure and material here are authored.
    _box(self, "Awning", Vector3(7.68, 0.10, 1.18), Vector3(0.0, 4.23, 0.48), _metal)
    _box(self, "AwningFrontRail", Vector3(7.68, 0.14, 0.10), Vector3(0.0, 4.16, 1.03), _metal)

    visual_built = true
    return true

func _make_materials() -> void:
    _wood = StandardMaterial3D.new()
    _wood.albedo_color = Color(0.16, 0.052, 0.025, 1.0)
    _wood.roughness = 0.64
    _wood.metallic = 0.0

    _wood_highlight = StandardMaterial3D.new()
    _wood_highlight.albedo_color = Color(0.29, 0.115, 0.055, 1.0)
    _wood_highlight.roughness = 0.60
    _wood_highlight.metallic = 0.0

    _marble = StandardMaterial3D.new()
    _marble.albedo_color = Color(0.72, 0.67, 0.58, 1.0)
    _marble.roughness = 0.58
    _marble.metallic = 0.0

    _glass = StandardMaterial3D.new()
    _glass.albedo_color = Color(0.16, 0.26, 0.29, 0.43)
    _glass.roughness = 0.12
    _glass.metallic = 0.0
    _glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

    _transom_glass = StandardMaterial3D.new()
    _transom_glass.albedo_color = Color(0.30, 0.19, 0.10, 0.54)
    _transom_glass.roughness = 0.18
    _transom_glass.metallic = 0.0
    _transom_glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

    _metal = StandardMaterial3D.new()
    _metal.albedo_color = Color(0.075, 0.08, 0.085, 1.0)
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
