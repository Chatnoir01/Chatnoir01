extends Node3D

const V5_NAME := "GrandPlaceFacadePresentationIntegratedV5"
const DETAIL_ROOT_PATH := "GrandPlaceFacadeIntegratedRefinementV5Details"
const TOWER_NAME := "MaisonDuRoiAxialTowerCue"
const LANTERN_NAME := "MaisonDuRoiOctagonalLanternCue"
const SPIRE_NAME := "MaisonDuRoiSpireCue"

# Urban Brussels 31143 documents an axial tower of square plan. Exact dimensions
# are not published in the source used by this campaign, so this ratio remains an
# authored presentation choice bounded to the already source-derived axial bay.
const TOWER_DEPTH_TO_WIDTH := 0.72
const MIN_DEPTH_RATIO := 0.60
const MAX_DEPTH_RATIO := 0.85
const PLANE_EPSILON_M := 0.001

var built := false
var failed := false
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

    var normal := tower.global_basis.z.normalized()
    if normal.length_squared() < 0.99:
        _fail("tower facade normal invalid"); return
    var old_front_plane := tower.global_position.dot(normal) + depth_before * 0.5
    var target_depth := width * TOWER_DEPTH_TO_WIDTH
    var ratio := target_depth / width
    if ratio < MIN_DEPTH_RATIO or ratio > MAX_DEPTH_RATIO:
        _fail("authored square-plan depth ratio escaped bounds: %.4f" % ratio); return

    # Preserve the exact player-facing plane from V5 and grow depth only toward
    # the building. This avoids moving the validated facade relief toward the
    # camera while making the documented square-plan tower read in oblique views.
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

    tower.set_meta("heritage_fact", "axial_square_tower")
    tower.set_meta("square_plan_depth_authored", true)
    tower.set_meta("depth_ratio_to_width", TOWER_DEPTH_TO_WIDTH)
    tower.set_meta("depth_dimension_surveyed", false)
    tower.set_meta("front_plane_preserved", true)
    tower.set_meta("depth_extended_behind_facade", true)
    tower.set_meta("source_record", "Urban Brussels 31143")

    set_meta("source_record", "Urban Brussels 31143")
    set_meta("source_fact", "axial tower of square plan")
    set_meta("source_geometry_changed", false)
    set_meta("source_collision_changed", false)
    set_meta("camera_changed", false)
    set_meta("threshold_changed", false)
    set_meta("front_plane_preserved", true)
    set_meta("depth_extended_behind_facade", true)
    set_meta("tower_depth_ratio", TOWER_DEPTH_TO_WIDTH)
    set_meta("tower_depth_dimension_surveyed", false)
    set_meta("finished_perfect", false)

    built = true
    print("GRAND_PLACE_MAISON_DU_ROI_TOWER_DEPTH_V7_READY: width=%.3f old_depth=%.3f new_depth=%.3f ratio=%.3f front_plane_error=%.6f source=Urban_Brussels_31143 collisions=0" % [size_after.x,depth_before,size_after.z,size_after.z/size_after.x,front_plane_error])
