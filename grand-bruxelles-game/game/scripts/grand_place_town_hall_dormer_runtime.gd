extends Node3D
class_name GrandPlaceTownHallDormerRuntime

## Source-backed visual reconstruction for the right-of-tower Gothic wing of
## Brussels Town Hall. UrbIS fixes the roof plane; Urban Brussels 31125 fixes
## the four-row/hipped-dormer identity; three independent Commons photographs
## constrain the visible 3/4/4/5 staggered pattern. Exact dormer coordinates and
## dimensions are deliberately NOT claimed as survey facts.

const BrusselsSlateRoofMaterial := preload("res://game/scripts/brussels_slate_roof_material.gd")
const BrusselsWhiteStoneMaterial := preload("res://game/scripts/brussels_white_stone_material.gd")
const BrusselsArchitecturalGlazingMaterial := preload("res://game/scripts/brussels_architectural_glazing_material.gd")

const TARGET_FACE_ID := "9369301"
const PLACEMENT_SOURCE := "photo_fit_visualization_convention_not_survey_coordinates"
const EAVE_START := Vector3(292.0918, 23.712, -515.2239)
const EAVE_END := Vector3(302.2418, 23.712, -502.9279)
const EAVE_SPAN_M := 15.9440934873
const EAVE_TANGENT := Vector3(0.63659938, 0.0, 0.77119468)
const ROOF_SLOPE_UP := Vector3(-0.37115981, 0.87665575, 0.30618874)
const OUTWARD := Vector3(0.77119468, 0.0, -0.63659938)
const UP := Vector3.UP
const ROW_SLOPE_M := [9.8, 7.4, 5.2, 3.0]
const ROW_U := [
    [0.20, 0.50, 0.80],
    [0.12, 0.38, 0.64, 0.90],
    [0.20, 0.43, 0.66, 0.89],
    [0.10, 0.30, 0.50, 0.70, 0.90],
]
const DORMER_WIDTH_M := 0.72
const FRONT_HEIGHT_M := 0.82
const HIP_DEPTH_M := 0.72
const HIP_RISE_M := 0.34

var _dormer_count := 0
var _ready_complete := false
var _slate: Material
var _stone: Material
var _glass: Material

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_DISABLED
    set_meta("zone", "Grand-Place")
    set_meta("urbis_building_id", "1655673")
    set_meta("urbis_roof_face_id", TARGET_FACE_ID)
    set_meta("placement_source", PLACEMENT_SOURCE)
    set_meta("exact_3d_positions_resolved", false)
    set_meta("exact_dimensions_resolved", false)
    set_meta("urbis_mesh_modified", false)
    _build_materials()
    _build_dormers()
    _ready_complete = _dormer_count == 16
    if not _ready_complete:
        push_error("GRAND_PLACE_TOWN_HALL_DORMERS_FAIL: expected 16 dormers, got %d" % _dormer_count)
        return
    print("GRAND_PLACE_TOWN_HALL_DORMERS_READY: face=9369301 rows=4 dormers=16 morphology=hipped source=photo_fit_not_survey")

func _build_materials() -> void:
    var source_label := "Urban Brussels 31125 + Commons Michielverbeek 2015 / Zairon 2016 / EmDee 2011"
    _slate = BrusselsSlateRoofMaterial.create(Color(0.045, 0.055, 0.068, 1.0), Color(0.145, 0.148, 0.155, 1.0), 0.74, source_label)
    _stone = BrusselsWhiteStoneMaterial.create(Color(0.70, 0.68, 0.62, 1.0), Color(0.84, 0.81, 0.73, 1.0), 0.82, source_label)
    _glass = BrusselsArchitecturalGlazingMaterial.create(source_label)

func _build_dormers() -> void:
    for row_index: int in range(ROW_U.size()):
        var row: Array = ROW_U[row_index]
        var slope_distance := float(ROW_SLOPE_M[row_index])
        for index_in_row: int in range(row.size()):
            var u := float(row[index_in_row])
            var anchor := EAVE_START + EAVE_TANGENT * (u * EAVE_SPAN_M) + ROOF_SLOPE_UP * slope_distance
            _add_hipped_dormer(anchor, row_index, index_in_row)
            _dormer_count += 1

func _add_hipped_dormer(anchor: Vector3, row_index: int, index_in_row: int) -> void:
    var dormer_root := Node3D.new()
    dormer_root.name = "Dormer_R%d_%02d" % [row_index + 1, index_in_row + 1]
    dormer_root.set_meta("row_top_to_bottom", row_index + 1)
    dormer_root.set_meta("index_in_row", index_in_row + 1)
    dormer_root.set_meta("morphology", "hipped")
    dormer_root.set_meta("placement_source", PLACEMENT_SOURCE)
    dormer_root.set_meta("survey_coordinate", false)
    add_child(dormer_root)

    var front_center := anchor + OUTWARD * 0.34 + UP * 0.08
    var half_width := DORMER_WIDTH_M * 0.5
    var frame := 0.105
    var front_bottom_left := front_center - EAVE_TANGENT * half_width
    var front_bottom_right := front_center + EAVE_TANGENT * half_width
    var front_top_left := front_bottom_left + UP * FRONT_HEIGHT_M
    var front_top_right := front_bottom_right + UP * FRONT_HEIGHT_M

    var stone_vertices := PackedVector3Array()
    _push_quad(stone_vertices, front_bottom_left, front_bottom_right, front_bottom_right + UP * frame, front_bottom_left + UP * frame)
    _push_quad(stone_vertices, front_top_left - UP * frame, front_top_right - UP * frame, front_top_right, front_top_left)
    _push_quad(stone_vertices, front_bottom_left + UP * frame, front_bottom_left + EAVE_TANGENT * frame + UP * frame, front_top_left + EAVE_TANGENT * frame - UP * frame, front_top_left - UP * frame)
    _push_quad(stone_vertices, front_bottom_right - EAVE_TANGENT * frame + UP * frame, front_bottom_right + UP * frame, front_top_right - UP * frame, front_top_right - EAVE_TANGENT * frame - UP * frame)

    var rear_left := anchor - EAVE_TANGENT * half_width + ROOF_SLOPE_UP * 0.42
    var rear_right := anchor + EAVE_TANGENT * half_width + ROOF_SLOPE_UP * 0.42
    _push_quad(stone_vertices, front_bottom_left, front_top_left, rear_left + UP * 0.36, rear_left)
    _push_quad(stone_vertices, front_bottom_right, rear_right, rear_right + UP * 0.36, front_top_right)
    _add_mesh(dormer_root, "StoneFrame", stone_vertices, _stone)

    var glass_offset := OUTWARD * 0.012
    var glass_vertices := PackedVector3Array()
    _push_quad(glass_vertices, front_bottom_left + EAVE_TANGENT * frame + UP * frame + glass_offset, front_bottom_right - EAVE_TANGENT * frame + UP * frame + glass_offset, front_top_right - EAVE_TANGENT * frame - UP * frame + glass_offset, front_top_left + EAVE_TANGENT * frame - UP * frame + glass_offset)
    _add_mesh(dormer_root, "Glazing", glass_vertices, _glass)

    var cap_half_width := half_width + 0.10
    var cap_front_center := front_center + UP * (FRONT_HEIGHT_M + 0.06)
    var cap_back_center := anchor + ROOF_SLOPE_UP * HIP_DEPTH_M + OUTWARD * 0.02 + UP * 0.06
    var front_left := cap_front_center - EAVE_TANGENT * cap_half_width
    var front_right := cap_front_center + EAVE_TANGENT * cap_half_width
    var back_left := cap_back_center - EAVE_TANGENT * cap_half_width
    var back_right := cap_back_center + EAVE_TANGENT * cap_half_width
    var ridge_center := (cap_front_center + cap_back_center) * 0.5 + UP * HIP_RISE_M
    var ridge_half := 0.14
    var ridge_left := ridge_center - EAVE_TANGENT * ridge_half
    var ridge_right := ridge_center + EAVE_TANGENT * ridge_half

    var slate_vertices := PackedVector3Array()
    _push_quad(slate_vertices, front_left, front_right, ridge_right, ridge_left)
    _push_quad(slate_vertices, back_left, ridge_left, ridge_right, back_right)
    _push_tri(slate_vertices, front_left, ridge_left, back_left)
    _push_tri(slate_vertices, front_right, back_right, ridge_right)
    _add_mesh(dormer_root, "HippedSlateCap", slate_vertices, _slate)

func _push_tri(vertices: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3) -> void:
    vertices.append(a)
    vertices.append(b)
    vertices.append(c)

func _push_quad(vertices: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
    _push_tri(vertices, a, b, c)
    _push_tri(vertices, a, c, d)

func _add_mesh(parent: Node3D, mesh_name: String, vertices: PackedVector3Array, material: Material) -> void:
    var surface := SurfaceTool.new()
    surface.begin(Mesh.PRIMITIVE_TRIANGLES)
    for vertex: Vector3 in vertices:
        surface.add_vertex(vertex)
    surface.generate_normals()
    var array_mesh := surface.commit()
    if array_mesh == null:
        push_error("GRAND_PLACE_TOWN_HALL_DORMERS_FAIL: mesh commit failed for %s" % mesh_name)
        return
    var mesh_instance := MeshInstance3D.new()
    mesh_instance.name = mesh_name
    mesh_instance.mesh = array_mesh
    mesh_instance.material_override = material
    mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
    parent.add_child(mesh_instance)

func dormer_count() -> int:
    return _dormer_count

func row_population_top_to_bottom() -> Array[int]:
    return [3, 4, 4, 5]

func ready_complete() -> bool:
    return _ready_complete

func source_truth() -> Dictionary:
    return {"urbis_roof_face_id": TARGET_FACE_ID, "placement_source": PLACEMENT_SOURCE, "exact_3d_positions_resolved": false, "exact_dimensions_resolved": false, "urbis_mesh_modified": false}
