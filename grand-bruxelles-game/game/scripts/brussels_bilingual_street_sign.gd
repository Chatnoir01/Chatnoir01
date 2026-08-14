extends Node3D
class_name BrusselsBilingualStreetSign

## Reusable bilingual Brussels street-name plaque.
## The bilingual naming contract is source-backed; panel geometry, colors and
## typography are authored presentation values and do not claim a surveyed or
## manufacturer-specific City of Brussels plaque.

@export var french_name: String = "RUE DE LA BOURSE"
@export var dutch_name: String = "BEURSSTRAAT"

var visual_built := false
var plaque_count := 0
var language_line_count := 0
var display_french := ""
var display_dutch := ""
var authored_geometry := true
var claims_surveyed_mount := false

var _panel_material: StandardMaterial3D
var _border_material: StandardMaterial3D

func _ready() -> void:
    build()

func build() -> bool:
    if visual_built:
        return true
    display_french = french_name.strip_edges().to_upper()
    display_dutch = dutch_name.strip_edges().to_upper()
    if display_french.is_empty() or display_dutch.is_empty():
        return false

    _panel_material = _material(Color(0.035, 0.145, 0.31, 1.0), 0.72)
    _border_material = _material(Color(0.90, 0.92, 0.94, 1.0), 0.80)

    # Authored presentation envelope. It is intentionally not presented as a
    # measured municipal plaque dimension.
    _box("PlaquePanel", Vector3(0.78, 0.34, 0.045), Vector3.ZERO, _panel_material)
    _box("PlaqueBorderTop", Vector3(0.74, 0.014, 0.052), Vector3(0.0, 0.145, -0.006), _border_material)
    _box("PlaqueBorderBottom", Vector3(0.74, 0.014, 0.052), Vector3(0.0, -0.145, -0.006), _border_material)
    _box("PlaqueBorderLeft", Vector3(0.014, 0.29, 0.052), Vector3(-0.37, 0.0, -0.006), _border_material)
    _box("PlaqueBorderRight", Vector3(0.014, 0.29, 0.052), Vector3(0.37, 0.0, -0.006), _border_material)

    _label("FrenchStreetName", display_french, Vector3(0.0, 0.065, -0.031))
    _label("DutchStreetName", display_dutch, Vector3(0.0, -0.065, -0.031))

    plaque_count = 1
    language_line_count = 2
    visual_built = true
    return true

func _label(node_name: String, text_value: String, pos: Vector3) -> Label3D:
    var label := Label3D.new()
    label.name = node_name
    label.text = text_value
    label.position = pos
    label.font_size = 56
    label.pixel_size = 0.0017
    label.modulate = Color(0.96, 0.97, 0.98, 1.0)
    label.outline_size = 2
    label.outline_modulate = Color(0.01, 0.03, 0.06, 0.9)
    label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    label.no_depth_test = false
    add_child(label)
    return label

func _material(color: Color, roughness: float) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = roughness
    material.metallic = 0.0
    return material

func _box(node_name: String, size: Vector3, pos: Vector3, material: Material) -> MeshInstance3D:
    var mesh := BoxMesh.new()
    mesh.size = size
    mesh.material = material
    var instance := MeshInstance3D.new()
    instance.name = node_name
    instance.mesh = mesh
    instance.position = pos
    instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
    add_child(instance)
    return instance
