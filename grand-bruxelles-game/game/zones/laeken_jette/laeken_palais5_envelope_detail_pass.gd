extends Node3D

## Source-backed envelope detail layered onto Palais 5 hero geometry.
## Architectural organization/material families come from the Brussels heritage
## inventory. Exact skin thicknesses, band heights, mullion spacing and door
## positions are deliberately treated as non-surveyed game geometry.

const PROVENANCE_PATH := "res://data/sources/laeken_jette/palais5_hero_provenance.json"
const MAX_WAIT_FRAMES := 90

var detail_ready: bool = false
var front_window_bands: int = 0
var copper_gutters: int = 0
var side_brick_elevations: int = 0
var side_window_bands: int = 0
var side_doors: int = 0
var rear_grid_members: int = 0
var rear_glazing_panels: int = 0

var _brick: StandardMaterial3D
var _glass: StandardMaterial3D
var _copper: StandardMaterial3D
var _concrete: StandardMaterial3D
var _door: StandardMaterial3D


func _ready() -> void:
    call_deferred("_build")


func _load_json(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        return {}
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return {}
    var parsed = JSON.parse_string(file.get_as_text())
    return parsed as Dictionary if parsed is Dictionary else {}


func _material(color: Color, roughness: float, metallic: float = 0.0) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = roughness
    material.metallic = metallic
    return material


func _make_materials() -> void:
    # Muted material values intentionally avoid claiming sampled historic colors.
    _brick = _material(Color(0.34, 0.20, 0.14, 1.0), 0.92)
    _glass = _material(Color(0.055, 0.09, 0.105, 0.86), 0.18, 0.06)
    _glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    _copper = _material(Color(0.31, 0.23, 0.14, 1.0), 0.52, 0.62)
    _concrete = _material(Color(0.38, 0.40, 0.40, 1.0), 0.88)
    _door = _material(Color(0.15, 0.17, 0.18, 1.0), 0.54, 0.30)


func _add_box(parent: Node3D, node_name: String, size: Vector3, position: Vector3, material: Material) -> MeshInstance3D:
    var mesh := BoxMesh.new()
    mesh.size = size
    mesh.material = material
    var instance := MeshInstance3D.new()
    instance.name = node_name
    instance.mesh = mesh
    instance.position = position
    parent.add_child(instance)
    return instance


func _build_front_roof_returns(hero: Node3D, span: float) -> void:
    # Heritage inventory: front roof return stacks continuous window bands below copper gutters.
    # Exact vertical spacing is not published; use restrained proportional placement behind the porch.
    var band_width := span - 4.0
    for y in [9.7, 11.55]:
        _add_box(hero, "FrontRoofContinuousWindowBand", Vector3(band_width, 1.05, 0.16), Vector3(0.0, y, 5.25), _glass)
        front_window_bands += 1
        _add_box(hero, "FrontRoofCopperGutter", Vector3(band_width + 0.35, 0.18, 0.24), Vector3(0.0, y + 0.66, 5.22), _copper)
        copper_gutters += 1


func _build_side_elevations(hero: Node3D, span: float, hall_length: float) -> void:
    # Heritage inventory: low brick side facades, thin horizontal window band, three doors.
    var side_x := span * 0.5
    var facade_length := maxf(30.0, hall_length - 15.0)
    var centre_z := hall_length * 0.5 + 1.0
    var wall_height := 8.4
    for side_sign in [-1.0, 1.0]:
        var x := float(side_sign) * (side_x - 0.18)
        _add_box(hero, "SideBrickElevation", Vector3(0.42, wall_height, facade_length), Vector3(x, wall_height * 0.5, centre_z), _brick)
        side_brick_elevations += 1
        _add_box(hero, "SideThinWindowBand", Vector3(0.16, 1.05, facade_length - 10.0), Vector3(x + float(side_sign) * 0.24, 5.85, centre_z), _glass)
        side_window_bands += 1

        # The source records three doors but not their exact longitudinal positions.
        # Keep them evenly distributed and explicitly non-surveyed in provenance.
        for fraction in [0.24, 0.50, 0.76]:
            var z := centre_z - facade_length * 0.5 + facade_length * float(fraction)
            _add_box(hero, "SideEnvelopeDoor", Vector3(0.20, 3.1, 2.65), Vector3(x + float(side_sign) * 0.27, 1.55, z), _door)
            side_doors += 1


func _build_rear_facade(hero: Node3D, span: float, hall_length: float) -> void:
    # Heritage inventory: rear facade is flat, concrete-gridded and centrally glazed.
    var rear_z := hall_length - 5.7
    var rear_height := 9.0
    _add_box(hero, "RearConcreteEnvelope", Vector3(span - 2.0, rear_height, 0.45), Vector3(0.0, rear_height * 0.5, rear_z), _concrete)

    var glass_width := 30.0
    var glass_height := 6.0
    _add_box(hero, "RearCentralGlazing", Vector3(glass_width, glass_height, 0.18), Vector3(0.0, 4.9, rear_z - 0.34), _glass)
    rear_glazing_panels += 1

    for index in range(1, 7):
        var x := -glass_width * 0.5 + glass_width * float(index) / 7.0
        _add_box(hero, "RearGridVertical", Vector3(0.18, glass_height, 0.24), Vector3(x, 4.9, rear_z - 0.46), _concrete)
        rear_grid_members += 1
    for index in range(1, 4):
        var y := 1.9 + glass_height * float(index) / 4.0
        _add_box(hero, "RearGridHorizontal", Vector3(glass_width, 0.18, 0.24), Vector3(0.0, y, rear_z - 0.46), _concrete)
        rear_grid_members += 1


func _build() -> void:
    _make_materials()
    var provenance := _load_json(PROVENANCE_PATH)
    var facts = provenance.get("architectural_facts", {})
    if not (facts is Dictionary):
        push_warning("LaekenPalais5EnvelopeDetailPass: provenance unavailable")
        return

    var hero_pass = get_parent().get_node_or_null("Palais5HeroPass")
    if hero_pass == null:
        push_warning("LaekenPalais5EnvelopeDetailPass: Palais5HeroPass missing")
        return
    for _frame in range(MAX_WAIT_FRAMES):
        if bool(hero_pass.get("hero_ready")):
            break
        await get_tree().process_frame
    if not bool(hero_pass.get("hero_ready")):
        push_warning("LaekenPalais5EnvelopeDetailPass: hero geometry never became ready")
        return

    var hero := hero_pass.get_node_or_null("Palais5HeroGeometry") as Node3D
    if hero == null:
        push_warning("LaekenPalais5EnvelopeDetailPass: hero root missing")
        return

    var span := float(facts.get("structural_span_m", 86.0))
    var hall_length := float(facts.get("approx_historic_length_m", 165.0))
    _build_front_roof_returns(hero, span)
    _build_side_elevations(hero, span, hall_length)
    _build_rear_facade(hero, span, hall_length)

    detail_ready = (
        front_window_bands == 2
        and copper_gutters == 2
        and side_brick_elevations == 2
        and side_window_bands == 2
        and side_doors == 6
        and rear_grid_members == 9
        and rear_glazing_panels == 1
    )
    print("LAEKEN_PALAIS5_ENVELOPE_READY: ready=%s front_bands=%d copper_gutters=%d side_brick=%d side_window_bands=%d side_doors=%d rear_grid=%d rear_glazing=%d" % [
        detail_ready,
        front_window_bands,
        copper_gutters,
        side_brick_elevations,
        side_window_bands,
        side_doors,
        rear_grid_members,
        rear_glazing_panels,
    ])
