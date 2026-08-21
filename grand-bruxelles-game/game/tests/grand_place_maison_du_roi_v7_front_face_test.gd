extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const V5_NAME := "GrandPlaceFacadePresentationIntegratedV5"
const V7_NAME := "GrandPlaceMaisonDuRoiTowerDepthV7"
const DETAILS_PATH := "GrandPlaceFacadeIntegratedRefinementV5Details"
const TOWER_NAME := "MaisonDuRoiAxialTowerCue"
const CAMERA := Vector3(319.01, 1.72, -535.20)
const MIN_SURFACE_CLEARANCE_M := 0.03
const Y_FRACTION_TOLERANCE := 0.03

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("GRAND_PLACE_MAISON_DU_ROI_V7_FRONT_FACE_FAIL: " + message)
    quit(1)

func _box_world_size(node: MeshInstance3D) -> Vector3:
    if node == null or node.mesh == null or not node.mesh is BoxMesh:
        return Vector3.ZERO
    var box := node.mesh as BoxMesh
    return Vector3(
        box.size.x * node.global_basis.x.length(),
        box.size.y * node.global_basis.y.length(),
        box.size.z * node.global_basis.z.length()
    )

func _run() -> void:
    var main := MAIN_SCENE.instantiate()
    root.add_child(main)
    current_scene = main

    var v5: Node = null
    var v7: Node = null
    for _frame: int in range(1200):
        v5 = root.get_node_or_null(V5_NAME)
        v7 = root.get_node_or_null(V7_NAME)
        if v5 != null and v7 != null and bool(v5.get("built")) and bool(v7.get("built")):
            break
        await process_frame

    if v5 == null or v7 == null:
        _fail("required V5/V7 runtimes missing"); return
    if bool(v5.get("failed")) or bool(v7.get("failed")) or not bool(v7.get("built")):
        _fail("V5/V7 failed to build"); return
    if str(v7.get_meta("source_record", "")) != "Urban Brussels 31143":
        _fail("exact heritage source record drifted"); return
    for key: String in ["source_geometry_changed", "source_collision_changed", "camera_changed", "threshold_changed"]:
        if bool(v7.get_meta(key, true)):
            _fail("forbidden mutation: %s" % key); return
    if int(v7.get_meta("tower_level_count", -1)) != 4 or int(v7.get_meta("tower_level_separator_count", -1)) != 3:
        _fail("four-level structural accounting drifted"); return
    if bool(v7.get_meta("tower_level_separator_dimensions_surveyed", true)):
        _fail("authored level-break dimensions mislabeled surveyed"); return

    var details := v5.get_node_or_null(DETAILS_PATH) as Node3D
    var tower := details.get_node_or_null(TOWER_NAME) as MeshInstance3D if details != null else null
    if details == null or tower == null:
        _fail("Maison du Roi detail root/tower missing"); return

    var tower_size := _box_world_size(tower)
    if tower_size.x <= 0.5 or tower_size.y <= 1.0 or tower_size.z <= 0.2:
        _fail("invalid tower frame"); return
    var normal := tower.global_basis.z.normalized()
    var tangent := tower.global_basis.x.normalized()
    var to_camera := Vector3(CAMERA.x - tower.global_position.x, 0.0, CAMERA.z - tower.global_position.z)
    if to_camera.length_squared() < 0.01 or normal.dot(to_camera.normalized()) < 0.55:
        _fail("tower front no longer resolves toward frozen player camera"); return

    var tower_front_plane := tower.global_position.dot(normal) + tower_size.z * 0.5
    var tower_bottom_y := tower.global_position.y - tower_size.y * 0.5
    var previous_y := -INF

    for index: int in range(3):
        var separator := details.get_node_or_null("MaisonDuRoiTowerLevelBreak_%02d" % index) as MeshInstance3D
        if separator == null:
            _fail("missing level break %d" % index); return
        var separator_size := _box_world_size(separator)
        var separator_normal := separator.global_basis.z.normalized()
        var separator_tangent := separator.global_basis.x.normalized()
        if separator_normal.dot(normal) < 0.995 or separator_tangent.dot(tangent) < 0.995:
            _fail("level break %d rotated off canonical tower face" % index); return
        var separator_back_plane := separator.global_position.dot(normal) - separator_size.z * 0.5
        var clearance := separator_back_plane - tower_front_plane
        if clearance < MIN_SURFACE_CLEARANCE_M - 0.0005:
            _fail("level break %d depth-buffer unsafe: %.4f m" % [index, clearance]); return
        var expected_fraction := float(index + 1) / 4.0
        var actual_fraction := (separator.global_position.y - tower_bottom_y) / tower_size.y
        if absf(actual_fraction - expected_fraction) > Y_FRACTION_TOLERANCE:
            _fail("level break %d escaped quarter-height contract: expected=%.3f actual=%.3f" % [index, expected_fraction, actual_fraction]); return
        if separator.global_position.y <= previous_y:
            _fail("level breaks are not strictly bottom-to-top"); return
        previous_y = separator.global_position.y
        if separator_size.x < tower_size.x * 0.95 or separator_size.x > tower_size.x * 1.12:
            _fail("level break %d width escaped bounded structural cue" % index); return
        if not bool(separator.get_meta("level_count_source_backed", false)):
            _fail("level break %d lost source-backed count provenance" % index); return
        if bool(separator.get_meta("literal_level_break_profile_source_backed", true)):
            _fail("level break %d falsely claims literal profile provenance" % index); return
        if bool(separator.get_meta("presentation_dimension_surveyed", true)):
            _fail("level break %d falsely claims surveyed dimensions" % index); return

    print("GRAND_PLACE_MAISON_DU_ROI_V7_FRONT_FACE_OK: source=31143 levels=4 separators=3 front_facing=true min_clearance=%.2f quarter_height=true geometry_changed=false collision_changed=false" % MIN_SURFACE_CLEARANCE_M)
    quit(0)
