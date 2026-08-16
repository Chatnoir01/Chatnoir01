extends Node3D

## Reference-informed decorative pass for Gare de Jette.
## The authoritative plan envelope remains the UrbIS footprint built by
## jette_phase2_zone.gd. This script only adds bounded facade articulation
## derived from that already-loaded mesh AABB; it does not claim surveyed
## window/canopy dimensions.

const HERO_NODE := "JetteStationOfficialFootprintHero"
const MIN_EXTENT_M := 3.0

var visual_stats: Dictionary = {
    "window_panels": 0,
    "stone_bands": 0,
    "canopy_segments": 0,
}

var _glass: StandardMaterial3D
var _stone: StandardMaterial3D
var _metal: StandardMaterial3D


func _ready() -> void:
    call_deferred("_build_from_urbis_envelope")


func _material(color: Color, roughness: float, metallic: float = 0.0) -> StandardMaterial3D:
    var mat := StandardMaterial3D.new()
    mat.albedo_color = color
    mat.roughness = roughness
    mat.metallic = metallic
    return mat


func _make_materials() -> void:
    _glass = _material(Color(0.11, 0.15, 0.17, 1.0), 0.24, 0.12)
    _stone = _material(Color(0.73, 0.70, 0.63, 1.0), 0.9)
    _metal = _material(Color(0.13, 0.14, 0.15, 1.0), 0.46, 0.55)


func _build_from_urbis_envelope() -> void:
    _make_materials()
    var hero := get_parent().get_node_or_null(HERO_NODE) as MeshInstance3D
    if hero == null or hero.mesh == null:
        push_warning("JETTE_STATION_VISUAL_PASS_SKIP: UrbIS station hero unavailable")
        return

    var aabb := hero.get_aabb()
    if aabb.size.x < MIN_EXTENT_M or aabb.size.z < MIN_EXTENT_M:
        push_warning("JETTE_STATION_VISUAL_PASS_SKIP: station envelope too small")
        return

    var center := hero.position + aabb.get_center()
    var half_x := aabb.size.x * 0.5
    var half_z := aabb.size.z * 0.5
    var facade_y := maxf(2.15, minf(aabb.size.y * 0.48, 4.2))
    var panel_h := maxf(1.15, minf(aabb.size.y * 0.24, 2.0))

    _add_window_row(center, Vector3(1, 0, 0), Vector3(0, 0, 1), half_x, half_z + 0.055, facade_y, panel_h, aabb.size.x)
    _add_window_row(center, Vector3(1, 0, 0), Vector3(0, 0, -1), half_x, half_z + 0.055, facade_y, panel_h, aabb.size.x)
    _add_window_row(center, Vector3(0, 0, 1), Vector3(1, 0, 0), half_z, half_x + 0.055, facade_y, panel_h, aabb.size.z)
    _add_window_row(center, Vector3(0, 0, 1), Vector3(-1, 0, 0), half_z, half_x + 0.055, facade_y, panel_h, aabb.size.z)

    _add_box("JetteStationUpperStoneDatum", Vector3(aabb.size.x * 0.96, 0.24, 0.16), center + Vector3(0, facade_y + panel_h * 0.75, half_z + 0.07), _stone)
    _add_box("JetteStationLowerStoneDatum", Vector3(aabb.size.x * 0.96, 0.18, 0.14), center + Vector3(0, 1.05, half_z + 0.07), _stone)
    visual_stats["stone_bands"] = 2

    var canopy_length := clampf(aabb.size.x * 0.58, 8.0, 24.0)
    _add_box("JetteStationCanopy", Vector3(canopy_length, 0.16, 1.8), center + Vector3(0, 3.15, -half_z - 0.85), _metal)
    visual_stats["canopy_segments"] = 1

    print("JETTE_STATION_VISUAL_OK: %s" % JSON.stringify(visual_stats))


func _add_window_row(center: Vector3, tangent: Vector3, normal: Vector3, half_span: float, normal_offset: float, y: float, panel_h: float, facade_span: float) -> void:
    var count := clampi(int(floor(facade_span / 3.6)), 3, 10)
    var usable := half_span * 1.55
    var step := (usable * 2.0) / float(maxi(count - 1, 1))
    for i in range(count):
        var offset := -usable + step * float(i)
        var pos := center + tangent * offset + normal * normal_offset + Vector3(0, y, 0)
        var size := Vector3(1.35, panel_h, 0.08) if absf(tangent.x) > 0.5 else Vector3(0.08, panel_h, 1.35)
        _add_box("JetteStationWindow_%02d" % visual_stats["window_panels"], size, pos, _glass)
        visual_stats["window_panels"] = int(visual_stats["window_panels"]) + 1


func _add_box(node_name: String, size: Vector3, position: Vector3, material: Material) -> void:
    var mesh := BoxMesh.new()
    mesh.size = size
    mesh.material = material
    var instance := MeshInstance3D.new()
    instance.name = node_name
    instance.mesh = mesh
    instance.position = position
    add_child(instance)
