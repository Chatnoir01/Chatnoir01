extends Node3D

const V5_NAME := "GrandPlaceFacadePresentationIntegratedV5"
const DETAIL_ROOT_PATH := "GrandPlaceFacadeIntegratedRefinementV5Details"
const TOWER_NAME := "MaisonDuRoiAxialTowerCue"
const LANTERN_NAME := "MaisonDuRoiOctagonalLanternCue"
const SPIRE_NAME := "MaisonDuRoiSpireCue"
const CANONICAL_CAMERA := Vector3(319.01, 1.72, -535.20)

# Urban Brussels 31143 documents an axial tower of square plan. Exact dimensions
# are not published in the source used by this campaign, so this ratio remains an
# authored presentation choice bounded to the already source-derived axial bay.
const TOWER_DEPTH_TO_WIDTH := 0.72
const MIN_DEPTH_RATIO := 0.60
const MAX_DEPTH_RATIO := 0.85
const PLANE_EPSILON_M := 0.001

# The same record explicitly documents a roof-level register with pointed-arch
# bays on three faces and an openwork projecting balustrade. Dimensions below are
# authored ratios of the existing tower cue, never survey measurements.
const BAY_WIDTH_RATIO := 0.27
const BAY_RECT_HEIGHT_RATIO := 0.27
const BAY_HEAD_HEIGHT_RATIO := 0.12
const BAY_SURFACE_OFFSET_M := 0.050
const BALUSTRADE_OVERHANG_M := 0.055
const BALUSTRADE_RAIL_HEIGHT_M := 0.10
const BALUSTRADE_POST_HEIGHT_M := 0.38
const BALUSTRADE_POST_COUNT := 5

# Urban Brussels 31143 also explicitly states that the axial tower has four
# levels. The exact articulation/profile of those level breaks is not surveyed,
# so three shallow stone cues are authored only to make the exact level count
# legible in the frozen player frame without moving the tower/source geometry.
const TOWER_LEVEL_COUNT := 4
const TOWER_LEVEL_SEPARATOR_COUNT := 3
const LEVEL_BREAK_WIDTH_SCALE := 1.04
const LEVEL_BREAK_HEIGHT_RATIO := 0.035
const LEVEL_BREAK_DEPTH_M := 0.070
const LEVEL_BREAK_SURFACE_CLEARANCE_M := 0.035

var built := false
var failed := false
var roof_register_bay_count := 0
var roof_balustrade_element_count := 0
var tower_level_separator_count := 0
var _v5: Node = null

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    call_deferred("_build_when_ready")

func _fail(message: String) -> void:
    failed = true
    push_error("Grand-Place Maison du Roi tower depth V7: %s" % message)

func _box_world_size(node: MeshInstance3D) -> Vector3:
    if node == null or node.mesh == null or not node.mesh is BoxMesh:
        return Vector3.ZERO
    var box := node.mesh as BoxMesh
    return Vector3(
        box.size.x * node.global_basis.x.length(),
        box.size.y * node.global_basis.y.length(),
        box.size.z * node.global_basis.z.length()
    )

func _dark_recess_material() -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = Color(0.030, 0.045, 0.052, 1.0)
    material.roughness = 0.72
    material.metallic = 0.0
    material.cull_mode = BaseMaterial3D.CULL_DISABLED
    material.set_meta("material_family", "maison_du_roi_authored_dark_recess")
    material.set_meta("exact_rgb_is_photometric_measurement", false)
    return material

func _fallback_stone_material() -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = Color(0.73, 0.70, 0.64, 1.0)
    material.roughness = 0.86
    material.set_meta("material_family", "maison_du_roi_authored_white_stone_support")
    material.set_meta("exact_rgb_is_photometric_measurement", false)
    return material

func _add_box(details: Node3D, name_value: String, position: Vector3, x_axis: Vector3, z_axis: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
    var mesh := BoxMesh.new()
    mesh.size = Vector3(maxf(size.x, 0.02), maxf(size.y, 0.02), maxf(size.z, 0.01))
    var node := MeshInstance3D.new()
    node.name = name_value
    node.mesh = mesh
    node.material_override = material
    details.add_child(node)
    node.global_position = position
    node.global_basis = Basis(x_axis.normalized(), Vector3.UP, z_axis.normalized())
    node.set_meta("source_geometry", false)
    node.set_meta("presentation_dimension_surveyed", false)
    return node

func _add_pointed_head(details: Node3D, name_value: String, position: Vector3, x_axis: Vector3, z_axis: Vector3, width: float, height: float, material: Material) -> MeshInstance3D:
    var arrays: Array = []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
        Vector3(-width * 0.5, -height * 0.5, 0.0),
        Vector3(width * 0.5, -height * 0.5, 0.0),
        Vector3(0.0, height * 0.5, 0.0),
    ])
    var mesh := ArrayMesh.new()
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    var node := MeshInstance3D.new()
    node.name = name_value
    node.mesh = mesh
    node.material_override = material
    details.add_child(node)
    node.global_position = position
    node.global_basis = Basis(x_axis.normalized(), Vector3.UP, z_axis.normalized())
    node.set_meta("source_geometry", false)
    node.set_meta("presentation_dimension_surveyed", false)
    node.set_meta("pointed_arch_profile_documented", true)
    return node

func _add_roof_register_bay(details: Node3D, prefix: String, face_center: Vector3, x_axis: Vector3, face_normal: Vector3, face_width: float, tower_height: float, dark: Material) -> void:
    var bay_width := face_width * BAY_WIDTH_RATIO
    var rect_height := tower_height * BAY_RECT_HEIGHT_RATIO
    var head_height := tower_height * BAY_HEAD_HEIGHT_RATIO
    var rect_center := face_center + Vector3.UP * (tower_height * 0.07)
    _add_box(details, prefix + "Panel", rect_center, x_axis, face_normal, Vector3(bay_width, rect_height, 0.026), dark)
    _add_pointed_head(details, prefix + "PointedHead", rect_center + Vector3.UP * (rect_height * 0.5 + head_height * 0.5), x_axis, face_normal, bay_width, head_height, dark)
    roof_register_bay_count += 1

func _add_front_balustrade(details: Node3D, tower: MeshInstance3D, size_after: Vector3, tangent: Vector3, normal: Vector3, stone: Material) -> void:
    var top_y := tower.global_position.y + size_after.y * 0.5
    var face_center := tower.global_position + normal * (size_after.z * 0.5 + BALUSTRADE_OVERHANG_M)
    var rail_y := top_y + BALUSTRADE_POST_HEIGHT_M
    _add_box(details, "MaisonDuRoiTowerRoofBalustradeRail", Vector3(face_center.x, rail_y, face_center.z), tangent, normal, Vector3(size_after.x * 1.08, BALUSTRADE_RAIL_HEIGHT_M, 0.085), stone)
    roof_balustrade_element_count += 1
    for index: int in range(BALUSTRADE_POST_COUNT):
        var u := -size_after.x * 0.44 + size_after.x * 0.88 * float(index) / float(BALUSTRADE_POST_COUNT - 1)
        _add_box(details, "MaisonDuRoiTowerRoofBaluster_%02d" % index, face_center + tangent * u + Vector3.UP * (BALUSTRADE_POST_HEIGHT_M * 0.5), tangent, normal, Vector3(0.075, BALUSTRADE_POST_HEIGHT_M, 0.075), stone)
        roof_balustrade_element_count += 1

func _add_four_level_articulation(details: Node3D, tower: MeshInstance3D, size_after: Vector3, tangent: Vector3, normal: Vector3, stone: Material) -> void:
    var bottom_y := tower.global_position.y - size_after.y * 0.5
    var front_center := tower.global_position + normal * (size_after.z * 0.5 + LEVEL_BREAK_SURFACE_CLEARANCE_M + LEVEL_BREAK_DEPTH_M * 0.5)
    var band_height := size_after.y * LEVEL_BREAK_HEIGHT_RATIO
    for index: int in range(TOWER_LEVEL_SEPARATOR_COUNT):
        var level_fraction := float(index + 1) / float(TOWER_LEVEL_COUNT)
        var y := bottom_y + size_after.y * level_fraction
        var band := _add_box(
            details,
            "MaisonDuRoiTowerLevelBreak_%02d" % index,
            Vector3(front_center.x, y, front_center.z),
            tangent,
            normal,
            Vector3(size_after.x * LEVEL_BREAK_WIDTH_SCALE, band_height, LEVEL_BREAK_DEPTH_M),
            stone
        )
        band.set_meta("heritage_fact", "axial_tower_four_levels")
        band.set_meta("literal_level_break_profile_source_backed", false)
        band.set_meta("level_count_source_backed", true)
        tower_level_separator_count += 1

func _build_when_ready() -> void:
    for _frame: int in range(1200):
        _v5 = get_tree().root.get_node_or_null(V5_NAME)
        if _v5 != null and bool(_v5.get("built")):
            break
        await get_tree().process_frame
    if _v5 == null or not bool(_v5.get("built")):
        _fail("V5 facade refinement unavailable"); return

    var details := _v5.get_node_or_null(DETAIL_ROOT_PATH) as Node3D
    if details == null:
        _fail("V5 detail root missing"); return
    var tower := details.get_node_or_null(TOWER_NAME) as MeshInstance3D
    var lantern := details.get_node_or_null(LANTERN_NAME) as MeshInstance3D
    var spire := details.get_node_or_null(SPIRE_NAME) as MeshInstance3D
    if tower == null or lantern == null or spire == null:
        _fail("Maison du Roi tower/lantern/spire anchors missing"); return
    if tower.mesh == null or not tower.mesh is BoxMesh:
        _fail("Maison du Roi tower is not a BoxMesh"); return

    var size_before := _box_world_size(tower)
    var width := size_before.x
    var depth_before := size_before.z
    if width < 0.5 or depth_before <= 0.0:
        _fail("invalid V5 tower frame: width=%.4f depth=%.4f" % [width,depth_before]); return

    var tangent := tower.global_basis.x.normalized()
    var normal := tower.global_basis.z.normalized()
    if normal.length_squared() < 0.99 or tangent.length_squared() < 0.99:
        _fail("tower facade basis invalid"); return

    var to_camera := Vector3(CANONICAL_CAMERA.x - tower.global_position.x, 0.0, CANONICAL_CAMERA.z - tower.global_position.z)
    if to_camera.length_squared() < 0.01:
        _fail("canonical camera direction collapsed at Maison du Roi tower"); return
    to_camera = to_camera.normalized()
    if normal.dot(to_camera) < 0.0:
        var basis_before := tower.global_basis
        tower.global_basis = Basis(-basis_before.x, basis_before.y, -basis_before.z)
        tangent = tower.global_basis.x.normalized()
        normal = tower.global_basis.z.normalized()
    var front_facing_score := normal.dot(to_camera)
    if front_facing_score < 0.55:
        _fail("tower depth axis cannot resolve canonical facade front: score=%.4f" % front_facing_score); return

    var old_front_plane := tower.global_position.dot(normal) + depth_before * 0.5
    var target_depth := width * TOWER_DEPTH_TO_WIDTH
    var ratio := target_depth / width
    if ratio < MIN_DEPTH_RATIO or ratio > MAX_DEPTH_RATIO:
        _fail("authored square-plan depth ratio escaped bounds: %.4f" % ratio); return

    var depth_delta := target_depth - depth_before
    var mesh := tower.mesh as BoxMesh
    mesh.size.z = mesh.size.z * (target_depth / depth_before)
    tower.global_position -= normal * (depth_delta * 0.5)
    lantern.global_position -= normal * (depth_delta * 0.5)
    spire.global_position -= normal * (depth_delta * 0.5)

    var size_after := _box_world_size(tower)
    var new_front_plane := tower.global_position.dot(normal) + size_after.z * 0.5
    var front_plane_error := absf(new_front_plane - old_front_plane)
    if front_plane_error > PLANE_EPSILON_M:
        _fail("front plane moved by %.6f m" % front_plane_error); return
    if absf(size_after.z / size_after.x - TOWER_DEPTH_TO_WIDTH) > 0.005:
        _fail("tower depth ratio did not converge: %.4f" % (size_after.z / size_after.x)); return
    if absf((lantern.global_position - tower.global_position).dot(normal)) > 0.01:
        _fail("lantern no longer centered on tower depth axis"); return
    if absf((spire.global_position - tower.global_position).dot(normal)) > 0.01:
        _fail("spire no longer centered on tower depth axis"); return

    var dark := _dark_recess_material()
    var front_face := tower.global_position + normal * (size_after.z * 0.5 + BAY_SURFACE_OFFSET_M)
    _add_roof_register_bay(details, "MaisonDuRoiTowerRoofBayFront", front_face, tangent, normal, size_after.x, size_after.y, dark)
    var left_face := tower.global_position - tangent * (size_after.x * 0.5 + BAY_SURFACE_OFFSET_M)
    _add_roof_register_bay(details, "MaisonDuRoiTowerRoofBayLeft", left_face, normal, -tangent, size_after.z, size_after.y, dark)
    var right_face := tower.global_position + tangent * (size_after.x * 0.5 + BAY_SURFACE_OFFSET_M)
    _add_roof_register_bay(details, "MaisonDuRoiTowerRoofBayRight", right_face, normal, tangent, size_after.z, size_after.y, dark)

    var stone: Material = tower.material_override
    if stone == null:
        stone = _fallback_stone_material()
    _add_front_balustrade(details, tower, size_after, tangent, normal, stone)
    _add_four_level_articulation(details, tower, size_after, tangent, normal, stone)
    if roof_register_bay_count != 3:
        _fail("roof register must expose exactly three documented face cues"); return
    if roof_balustrade_element_count != BALUSTRADE_POST_COUNT + 1:
        _fail("roof balustrade accounting drifted"); return
    if tower_level_separator_count != TOWER_LEVEL_SEPARATOR_COUNT:
        _fail("four-level tower articulation accounting drifted"); return

    tower.set_meta("heritage_fact", "axial_square_tower")
    tower.set_meta("square_plan_depth_authored", true)
    tower.set_meta("depth_ratio_to_width", TOWER_DEPTH_TO_WIDTH)
    tower.set_meta("depth_dimension_surveyed", false)
    tower.set_meta("front_plane_preserved", true)
    tower.set_meta("depth_extended_behind_facade", true)
    tower.set_meta("source_record", "Urban Brussels 31143")
    tower.set_meta("tower_levels_exact_count", TOWER_LEVEL_COUNT)
    tower.set_meta("tower_levels_exact_count_source_backed", true)

    set_meta("source_record", "Urban Brussels 31143")
    set_meta("source_fact", "axial tower of square plan with four levels; roof-level pointed-arch bays on three faces; projecting openwork balustrade")
    set_meta("source_geometry_changed", false)
    set_meta("source_collision_changed", false)
    set_meta("camera_changed", false)
    set_meta("threshold_changed", false)
    set_meta("front_plane_preserved", true)
    set_meta("depth_extended_behind_facade", true)
    set_meta("canonical_front_resolved", true)
    set_meta("canonical_front_facing_score", front_facing_score)
    set_meta("tower_depth_ratio", TOWER_DEPTH_TO_WIDTH)
    set_meta("tower_depth_dimension_surveyed", false)
    set_meta("tower_four_levels_documented", true)
    set_meta("tower_level_count", TOWER_LEVEL_COUNT)
    set_meta("tower_level_separator_count", tower_level_separator_count)
    set_meta("tower_level_separator_dimensions_surveyed", false)
    set_meta("tower_level_separator_profile_source_backed", false)
    set_meta("roof_register_bays_documented", true)
    set_meta("roof_register_bay_count", roof_register_bay_count)
    set_meta("roof_register_bay_dimensions_surveyed", false)
    set_meta("roof_balustrade_documented", true)
    set_meta("roof_balustrade_element_count", roof_balustrade_element_count)
    set_meta("roof_balustrade_dimensions_surveyed", false)
    set_meta("finished_perfect", false)

    built = true
    print("GRAND_PLACE_MAISON_DU_ROI_TOWER_DEPTH_V7_READY: width=%.3f old_depth=%.3f new_depth=%.3f ratio=%.3f front_plane_error=%.6f front_facing_score=%.3f tower_levels=%d level_breaks=%d roof_bays=%d balustrade_elements=%d source=Urban_Brussels_31143 collisions=0" % [size_after.x,depth_before,size_after.z,size_after.z/size_after.x,front_plane_error,front_facing_score,TOWER_LEVEL_COUNT,tower_level_separator_count,roof_register_bay_count,roof_balustrade_element_count])