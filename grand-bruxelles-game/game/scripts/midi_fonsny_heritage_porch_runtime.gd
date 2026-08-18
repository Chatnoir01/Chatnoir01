extends Node

## Source-backed architectural articulation for the Avenue Fonsny access porch.
## Identity comes from Brussels-Capital Region heritage inventory Urban 9423.
## Exact porch dimensions below are bounded visualization conventions: they are
## not promoted as survey/LiDAR geometry and do not replace the official UrbIS
## station plan envelope.

const PORCH_BAY_COUNT := 3
const PORCH_REGISTER_COUNT := 3
const MODE_ENV := "GB_MIDI_FONSNY_PORCH_MODE"
const MODE_BASELINE := "baseline"

var _built := false
var _build_failure := false
var _porch: Node3D

func _ready() -> void:
    call_deferred("_build_when_hero_ready")

func _material(color: Color, roughness: float = 0.85, metallic: float = 0.0, alpha: float = 1.0) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = Color(color.r, color.g, color.b, alpha)
    material.roughness = roughness
    material.metallic = metallic
    if alpha < 0.999:
        material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    return material

func _add_box(parent: Node3D, name: String, size: Vector3, position: Vector3, material: Material) -> MeshInstance3D:
    var mesh := BoxMesh.new()
    mesh.size = size
    mesh.material = material
    var instance := MeshInstance3D.new()
    instance.name = name
    instance.mesh = mesh
    instance.position = position
    parent.add_child(instance)
    return instance

func _add_polygonal_column(parent: Node3D, index: int, position: Vector3, material: Material) -> MeshInstance3D:
    var mesh := CylinderMesh.new()
    mesh.top_radius = 0.23
    mesh.bottom_radius = 0.23
    mesh.height = 4.3
    mesh.radial_segments = 6
    mesh.material = material
    var instance := MeshInstance3D.new()
    instance.name = "PorchPolygonalColumn_%02d" % index
    instance.mesh = mesh
    instance.position = position
    parent.add_child(instance)
    return instance

func _build_when_hero_ready() -> void:
    await get_tree().process_frame
    if OS.get_environment(MODE_ENV).strip_edges().to_lower() == MODE_BASELINE:
        _built = true
        return
    var entrance := get_tree().root.find_child("MidiMainEntranceFonsny", true, false) as Node3D
    if entrance == null:
        push_error("Midi Fonsny heritage porch: production entrance anchor missing")
        _build_failure = true
        return
    if entrance.get_node_or_null("FonsnyHeritagePorch") != null:
        _porch = entrance.get_node("FonsnyHeritagePorch") as Node3D
        _built = true
        return
    _build_fonsny_heritage_porch(entrance)
    _built = true

func _build_fonsny_heritage_porch(entrance: Node3D) -> void:
    var porch := Node3D.new()
    porch.name = "FonsnyHeritagePorch"
    porch.set_meta("source_id", "heritage_midi_9423")
    porch.set_meta("source_urban_id", 9423)
    porch.set_meta("porch_dimensions_are_visualization_convention", true)
    porch.set_meta("plan_envelope_authority", "official_urbis")
    entrance.add_child(porch)
    _porch = porch

    var concrete := _material(Color(0.47, 0.48, 0.46), 0.90)
    var blue_stone := _material(Color(0.235, 0.255, 0.27), 0.88)
    var yellow_brick := _material(Color(0.61, 0.53, 0.36), 0.94)
    var glass_block := _material(Color(0.36, 0.48, 0.50), 0.28, 0.03, 0.78)
    var dark_glass := _material(Color(0.055, 0.085, 0.105), 0.18, 0.18, 0.84)

    _add_box(porch, "PorchLowerRegisterBase", Vector3(0.30, 0.65, 20.8), Vector3(-15.34, 0.45, 0.0), blue_stone)
    _add_box(porch, "PorchLowerRegisterGlazing", Vector3(0.18, 2.45, 19.2), Vector3(-15.53, 1.65, 0.0), dark_glass)
    _add_box(porch, "PorchLowerRegisterLintel", Vector3(0.42, 0.34, 20.8), Vector3(-15.36, 3.02, 0.0), concrete)

    var bay_span := 5.35
    var bay_centres := [-6.15, 0.0, 6.15]
    for bay_index: int in range(PORCH_BAY_COUNT):
        var z := float(bay_centres[bay_index])
        _add_box(porch, "PorchGlassBlockBay_%02d" % bay_index, Vector3(0.20, 3.55, bay_span), Vector3(-15.50, 4.95, z), glass_block)
        _add_box(porch, "PorchBayVerticalCross_%02d" % bay_index, Vector3(0.34, 3.85, 0.26), Vector3(-15.66, 4.95, z), concrete)
        _add_box(porch, "PorchBayHorizontalCross_%02d" % bay_index, Vector3(0.34, 0.28, bay_span + 0.12), Vector3(-15.66, 4.95, z), concrete)
    for separator_index: int in range(4):
        var z := -9.25 + float(separator_index) * 6.17
        _add_box(porch, "PorchBayPier_%02d" % separator_index, Vector3(0.48, 4.0, 0.48), Vector3(-15.62, 4.95, z), concrete)

    _add_box(porch, "PorchBlindUpperRegister", Vector3(0.34, 1.75, 20.8), Vector3(-15.42, 7.72, 0.0), yellow_brick)
    _add_box(porch, "PorchUpperConcreteCap", Vector3(0.50, 0.32, 21.2), Vector3(-15.40, 8.72, 0.0), concrete)

    var canopy := Node3D.new()
    canopy.name = "PorchPerforatedCanopy"
    porch.add_child(canopy)
    _add_box(canopy, "CanopyFrontBeam", Vector3(8.8, 0.34, 0.38), Vector3(-11.10, 3.58, -10.15), concrete)
    _add_box(canopy, "CanopyBackBeam", Vector3(8.8, 0.34, 0.38), Vector3(-11.10, 3.58, 10.15), concrete)
    for rib_index: int in range(5):
        var z := -8.0 + float(rib_index) * 4.0
        _add_box(canopy, "CanopyConcreteRib_%02d" % rib_index, Vector3(8.8, 0.34, 0.30), Vector3(-11.10, 3.58, z), concrete)
    for panel_index: int in range(4):
        var z := -6.0 + float(panel_index) * 4.0
        _add_box(canopy, "CanopyGlassBlockPanel_%02d" % panel_index, Vector3(7.9, 0.12, 3.35), Vector3(-11.10, 3.58, z), glass_block)
    for column_index: int in range(4):
        var z := -8.7 + float(column_index) * 5.8
        _add_polygonal_column(porch, column_index, Vector3(-8.05, 2.15, z), concrete)

func built() -> bool:
    return _built

func build_failure() -> bool:
    return _build_failure

func porch_node() -> Node3D:
    return _porch
