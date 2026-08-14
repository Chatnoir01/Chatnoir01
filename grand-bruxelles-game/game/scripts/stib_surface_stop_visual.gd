extends Node3D
class_name StibSurfaceStopVisual

## Reusable authored surface-stop visual vocabulary for Brussels.
## Functional components and clearance minima are grounded in the official
## STIB/MIVB surface-stop Vademecum / Fiche Memo. Exact vendor geometry,
## colors, finish and dimensions below are authored presentation values and
## must not be interpreted as surveyed or manufacturer specifications.
## Source: https://www.stib-mivb.be/support-client/vademecum-arrets

@export var build_shelter: bool = true
@export var rear_clearance_m: float = 1.50
@export var front_clearance_m: float = 1.50

var visual_built := false
var pole_count := 0
var timetable_panel_count := 0
var shelter_count := 0
var bench_count := 0
var bin_count := 0

var _dark_metal: StandardMaterial3D
var _galvanized: StandardMaterial3D
var _glass: StandardMaterial3D
var _stib_blue_authored: StandardMaterial3D
var _stib_red_accent_authored: StandardMaterial3D
var _white_panel: StandardMaterial3D
var _bench_material: StandardMaterial3D
var _bin_material: StandardMaterial3D


func _ready() -> void:
    build()


func build() -> bool:
    if visual_built:
        return true
    _make_materials()
    _build_stop_pole(Vector3(-3.10, 0.0, 0.0))
    if build_shelter:
        _build_shelter(Vector3(0.0, 0.0, 0.0))
    _build_bin(Vector3(2.65, 0.0, 0.74))
    visual_built = pole_count == 1 and timetable_panel_count == 1 and bin_count == 1
    if build_shelter:
        visual_built = visual_built and shelter_count == 1 and bench_count == 1
    if visual_built:
        print("STIB_SURFACE_STOP_VISUAL_READY: pole=%d timetable=%d shelter=%d bench=%d bin=%d" % [pole_count, timetable_panel_count, shelter_count, bench_count, bin_count])
    return visual_built


func _make_materials() -> void:
    _dark_metal = _material(Color(0.045, 0.052, 0.060, 1.0), 0.55, 0.52)
    _galvanized = _material(Color(0.34, 0.37, 0.40, 1.0), 0.62, 0.58)
    _glass = _material(Color(0.070, 0.105, 0.125, 0.30), 0.18, 0.08)
    _glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    # Authored display colors: operator identity is descriptive, not calibrated.
    _stib_blue_authored = _material(Color(0.015, 0.34, 0.68, 1.0), 0.44, 0.10)
    _stib_red_accent_authored = _material(Color(0.88, 0.075, 0.095, 1.0), 0.48, 0.08)
    _white_panel = _material(Color(0.90, 0.92, 0.93, 1.0), 0.74)
    _bench_material = _material(Color(0.17, 0.19, 0.21, 1.0), 0.82, 0.18)
    _bin_material = _material(Color(0.095, 0.12, 0.115, 1.0), 0.86, 0.08)


func _build_stop_pole(origin: Vector3) -> void:
    _cylinder("StopPole", 0.065, 3.10, origin + Vector3(0.0, 1.55, 0.0), _galvanized)
    _box("StopIdentityPanel", Vector3(0.66, 0.88, 0.10), origin + Vector3(0.0, 2.56, 0.0), _stib_blue_authored)
    _box("StopRedAccent", Vector3(0.66, 0.10, 0.112), origin + Vector3(0.0, 2.16, 0.0), _stib_red_accent_authored)
    _box("TimetableHolder", Vector3(0.54, 0.78, 0.075), origin + Vector3(0.0, 1.54, 0.0), _white_panel)
    # Authored dark bands suggest route rows without embedding logos or copyrighted artwork.
    for row: int in range(4):
        _box("TimetableRow_%d" % row, Vector3(0.40, 0.055, 0.012), origin + Vector3(0.0, 1.78 - float(row) * 0.15, -0.044), _dark_metal)
    pole_count += 1
    timetable_panel_count += 1


func _build_shelter(origin: Vector3) -> void:
    # Authored 4.80 m x 1.65 m x 2.35 m envelope; Vademecum grounds the
    # shelter/bench/info functional vocabulary and >=1.50 m clear paths.
    var half_length := 2.40
    var half_depth := 0.825
    for x: float in [-half_length, half_length]:
        _box("ShelterPost", Vector3(0.10, 2.30, 0.10), origin + Vector3(x, 1.15, half_depth), _dark_metal)
        _box("ShelterPost", Vector3(0.10, 2.30, 0.10), origin + Vector3(x, 1.15, -half_depth), _dark_metal)
    _box("ShelterRoof", Vector3(5.05, 0.13, 1.88), origin + Vector3(0.0, 2.32, 0.0), _dark_metal)
    _box("ShelterBackGlass", Vector3(4.70, 2.05, 0.055), origin + Vector3(0.0, 1.12, half_depth), _glass)
    _box("ShelterSideGlassL", Vector3(0.055, 2.05, 1.52), origin + Vector3(-half_length, 1.12, 0.03), _glass)
    _box("ShelterSideGlassR", Vector3(0.055, 2.05, 1.52), origin + Vector3(half_length, 1.12, 0.03), _glass)
    _box("InfoValve", Vector3(1.04, 1.18, 0.045), origin + Vector3(1.62, 1.32, half_depth - 0.045), _stib_blue_authored)
    _box("InfoSheet", Vector3(0.82, 0.92, 0.018), origin + Vector3(1.62, 1.32, half_depth - 0.073), _white_panel)
    _build_bench(origin + Vector3(-0.55, 0.0, half_depth - 0.30))
    shelter_count += 1


func _build_bench(origin: Vector3) -> void:
    _box("ShelterBenchSeat", Vector3(2.10, 0.12, 0.44), origin + Vector3(0.0, 0.50, 0.0), _bench_material)
    _box("ShelterBenchBack", Vector3(2.10, 0.70, 0.10), origin + Vector3(0.0, 0.87, 0.17), _bench_material)
    for x: float in [-0.78, 0.78]:
        _box("ShelterBenchLeg", Vector3(0.09, 0.50, 0.34), origin + Vector3(x, 0.25, 0.0), _dark_metal)
    bench_count += 1


func _build_bin(origin: Vector3) -> void:
    _box("StopBin", Vector3(0.48, 0.90, 0.46), origin + Vector3(0.0, 0.45, 0.0), _bin_material)
    _box("StopBinOpening", Vector3(0.30, 0.10, 0.04), origin + Vector3(0.0, 0.66, -0.25), _dark_metal)
    bin_count += 1


func _material(color: Color, roughness: float, metallic: float = 0.0) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = roughness
    material.metallic = metallic
    return material


func _box(name_value: String, size: Vector3, pos: Vector3, material: Material) -> MeshInstance3D:
    var mesh := BoxMesh.new()
    mesh.size = size
    mesh.material = material
    var instance := MeshInstance3D.new()
    instance.name = name_value
    instance.mesh = mesh
    instance.position = pos
    instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
    add_child(instance)
    return instance


func _cylinder(name_value: String, radius: float, height: float, pos: Vector3, material: Material) -> MeshInstance3D:
    var mesh := CylinderMesh.new()
    mesh.top_radius = radius
    mesh.bottom_radius = radius
    mesh.height = height
    mesh.radial_segments = 16
    mesh.material = material
    var instance := MeshInstance3D.new()
    instance.name = name_value
    instance.mesh = mesh
    instance.position = pos
    instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
    add_child(instance)
    return instance
