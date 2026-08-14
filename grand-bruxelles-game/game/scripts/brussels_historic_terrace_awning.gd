extends Node3D
class_name BrusselsHistoricTerraceAwning

## Reusable Brussels historic terrace-awning vocabulary.
## Source-backed facts: Rue de la Bourse awnings were restored from historic
## models; the Grand Café study recovered a green metal structure.
## Dimensions, panel rhythm, glass tint and all PBR values below are authored.

var visual_built := false
var bay_count := 0
var roof_panel_count := 0
var support_count := 0
var source_confirms_green_metal_structure := true
var claims_surveyed_dimensions := false
var embeds_source_branding := false
var authored_geometry := true

var _green_metal: StandardMaterial3D
var _roof_glass: StandardMaterial3D
var _dark_trim: StandardMaterial3D

func _ready() -> void:
    build()

func build() -> bool:
    if visual_built:
        return true

    _green_metal = _material(Color(0.055, 0.24, 0.16, 1.0), 0.58, 0.18)
    _dark_trim = _material(Color(0.055, 0.065, 0.06, 1.0), 0.70, 0.10)
    _roof_glass = StandardMaterial3D.new()
    _roof_glass.albedo_color = Color(0.78, 0.82, 0.74, 0.72)
    _roof_glass.roughness = 0.34
    _roof_glass.metallic = 0.0
    _roof_glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    _roof_glass.cull_mode = BaseMaterial3D.CULL_DISABLED

    var frame := Node3D.new()
    frame.name = "GreenMetalFrame"
    add_child(frame)
    var roof := Node3D.new()
    roof.name = "RoofPanels"
    add_child(roof)

    # Authored street-scale envelope: three readable bays, deliberately not
    # claimed as the measured Grand Café or Cirio dimensions.
    const TOTAL_WIDTH := 8.4
    const DEPTH := 2.25
    const FRONT_Y := 2.72
    const WALL_Y := 3.02
    const BAY_WIDTH := TOTAL_WIDTH / 3.0

    _box(frame, "WallRail", Vector3(TOTAL_WIDTH, 0.10, 0.10), Vector3(0.0, WALL_Y, 0.04), _green_metal)
    _box(frame, "FrontRail", Vector3(TOTAL_WIDTH, 0.12, 0.12), Vector3(0.0, FRONT_Y, -DEPTH), _green_metal)
    _box(frame, "FrontFascia", Vector3(TOTAL_WIDTH, 0.28, 0.07), Vector3(0.0, FRONT_Y - 0.13, -DEPTH - 0.02), _dark_trim)

    for i: int in range(4):
        var x := -TOTAL_WIDTH * 0.5 + float(i) * BAY_WIDTH
        _box(frame, "Support_%02d" % i, Vector3(0.095, FRONT_Y, 0.095), Vector3(x, FRONT_Y * 0.5, -DEPTH), _green_metal)
        support_count += 1
        var brace_mid := Vector3(x, FRONT_Y + 0.02, -DEPTH * 0.50)
        _beam_between(frame, "Brace_%02d" % i, Vector3(x, WALL_Y, 0.0), brace_mid, 0.055, _green_metal)
        support_count += 1

    # Four narrow roof panels per bay create a visible historic canopy rhythm
    # without copying source glazing dimensions.
    const PANELS_PER_BAY := 4
    var panel_width := BAY_WIDTH / float(PANELS_PER_BAY)
    for bay: int in range(3):
        for panel: int in range(PANELS_PER_BAY):
            var x := -TOTAL_WIDTH * 0.5 + (float(bay * PANELS_PER_BAY + panel) + 0.5) * panel_width
            var panel_mesh := _box(roof, "RoofPanel_%02d_%02d" % [bay, panel], Vector3(panel_width - 0.035, 0.045, DEPTH - 0.10), Vector3(x, 2.89, -DEPTH * 0.5), _roof_glass)
            panel_mesh.rotation_degrees.x = -7.5
            roof_panel_count += 1
        var divider_x := -TOTAL_WIDTH * 0.5 + float(bay + 1) * BAY_WIDTH
        if bay < 2:
            _box(frame, "BayDivider_%02d" % bay, Vector3(0.065, 0.07, DEPTH), Vector3(divider_x, 2.90, -DEPTH * 0.5), _green_metal)

    bay_count = 3
    visual_built = true
    return true

func _material(color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = roughness
    material.metallic = metallic
    return material

func _box(parent: Node3D, node_name: String, size: Vector3, pos: Vector3, material: Material) -> MeshInstance3D:
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

func _beam_between(parent: Node3D, node_name: String, start: Vector3, finish: Vector3, thickness: float, material: Material) -> MeshInstance3D:
    var midpoint := (start + finish) * 0.5
    var direction := finish - start
    var length := direction.length()
    var beam := _box(parent, node_name, Vector3(thickness, thickness, length), midpoint, material)
    beam.look_at(finish, Vector3.UP)
    return beam
