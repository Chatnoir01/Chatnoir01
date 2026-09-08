extends SceneTree

const TARGET_SAMPLES := [68, 69, 70, 71]
const REQUIRED_VERTEX_COUNT := 3306
const WEIGHT_SUM_TOLERANCE := 0.0001

func _initialize() -> void:
    var args := OS.get_cmdline_user_args()
    if args.size() != 5:
        push_error("CIV1_GEOMETRY_GROUND_FAIL:args"); quit(2); return
    var bind_basis: Variant = _read_json(args[0])
    var skeleton_bundle: Variant = _read_json(args[1])
    var toe_pose: Variant = _read_json(args[2])
    var ground_receipt: Variant = _read_json(args[3])
    if not bind_basis is Dictionary or bind_basis.get("schema", "") != "grand-bruxelles-civ1-rightfoot-bind-pose-basis-v1":
        push_error("CIV1_GEOMETRY_GROUND_FAIL:bind"); quit(3); return
    if not skeleton_bundle is Dictionary or skeleton_bundle.get("schema", "") != "grand-bruxelles-civ1-skeleton-witness-bundle-v1":
        push_error("CIV1_GEOMETRY_GROUND_FAIL:skeleton"); quit(4); return
    if not toe_pose is Dictionary or toe_pose.get("schema", "") != "grand-bruxelles-civ1-righttoebase-pose-v1":
        push_error("CIV1_GEOMETRY_GROUND_FAIL:toe"); quit(5); return
    if not ground_receipt is Dictionary or ground_receipt.get("schema", "") != "grand-bruxelles-civ1-rightfoot-same-sample-ground-v1":
        push_error("CIV1_GEOMETRY_GROUND_FAIL:ground"); quit(6); return
    if int(bind_basis.get("selection_vertex_count", -1)) != REQUIRED_VERTEX_COUNT or not bool(bind_basis.get("bind_space_complete", false)):
        push_error("CIV1_GEOMETRY_GROUND_FAIL:bind-completeness"); quit(7); return
    if not bool(ground_receipt.get("same_sample_ground_evidence", false)) or bool(ground_receipt.get("runtime_authorized", true)):
        push_error("CIV1_GEOMETRY_GROUND_FAIL:ground-rail"); quit(8); return

    var frames: Array = skeleton_bundle.get("frames", [])
    var vertices: Array = bind_basis.get("vertices", [])
    if frames.size() != 120 or vertices.size() != REQUIRED_VERTEX_COUNT:
        push_error("CIV1_GEOMETRY_GROUND_FAIL:shape"); quit(9); return
    var toe_by_sample := {}
    for row in toe_pose.get("samples", []):
        toe_by_sample[int(row.get("sample_index", -1))] = row
    var ground_by_sample := {}
    for row in ground_receipt.get("samples", []):
        ground_by_sample[int(row.get("sample_index", -1))] = row
    for sample_index in TARGET_SAMPLES:
        if not toe_by_sample.has(sample_index) or not ground_by_sample.has(sample_index):
            push_error("CIV1_GEOMETRY_GROUND_FAIL:sample-join"); quit(10); return

    var ground_top_y := float(ground_receipt.get("ground_top_y_m", INF))
    var placement_y := float(ground_receipt.get("placement_y_m", INF))
    if not is_finite(ground_top_y) or not is_finite(placement_y):
        push_error("CIV1_GEOMETRY_GROUND_FAIL:ground-values"); quit(11); return

    var sample_reports: Array = []
    var geometry_below_ground_sample_count := 0
    for sample_index in TARGET_SAMPLES:
        var frame := frames[sample_index] as Dictionary
        var poses := frame.get("poses", {}) as Dictionary
        var toe_row := toe_by_sample[sample_index] as Dictionary
        var ground_row := ground_by_sample[sample_index] as Dictionary
        var min_clearance_m := INF
        var min_vertex_id := ""
        var below_ground_vertex_count := 0
        var nonfinite_count := 0
        var bad_weight_sum_count := 0
        var replayed_vertex_count := 0
        for v in vertices:
            var p := _v3(v.get("vertex_position", []))
            var mesh_to_skeleton := _transform_from_array(v.get("mesh_to_skeleton_rest", []))
            if not _finite_v3(p) or not _finite_transform(mesh_to_skeleton):
                nonfinite_count += 1; continue
            var p_skeleton_rest := mesh_to_skeleton * p
            var accum := Vector3.ZERO
            var weight_sum := 0.0
            for influence in v.get("influences", []):
                var w := float(influence.get("weight", 0.0))
                if w <= 0.0:
                    continue
                var posed_bone := _posed_bone_transform(str(influence.get("bone_name", "")), poses, toe_row)
                var inverse_bind := _transform_from_array(influence.get("inverse_bind_transform", []))
                if not _finite_transform(posed_bone) or not _finite_transform(inverse_bind):
                    nonfinite_count += 1; continue
                accum += (posed_bone * inverse_bind * p_skeleton_rest) * w
                weight_sum += w
            if abs(weight_sum - 1.0) > WEIGHT_SUM_TOLERANCE:
                bad_weight_sum_count += 1
            var world_position := accum + Vector3(0.0, placement_y, 0.0)
            if not _finite_v3(world_position):
                nonfinite_count += 1; continue
            replayed_vertex_count += 1
            if world_position.y < ground_top_y:
                below_ground_vertex_count += 1
            if world_position.y - ground_top_y < min_clearance_m:
                min_clearance_m = world_position.y - ground_top_y
                min_vertex_id = _vertex_id(v)
        if replayed_vertex_count != REQUIRED_VERTEX_COUNT or nonfinite_count != 0 or bad_weight_sum_count != 0 or not is_finite(min_clearance_m):
            push_error("CIV1_GEOMETRY_GROUND_FAIL:replay-integrity"); quit(12); return
        if min_clearance_m < 0.0:
            geometry_below_ground_sample_count += 1
        sample_reports.append({
            "sample_index": sample_index,
            "geometry_lower_envelope_clearance_m": min_clearance_m,
            "below_ground_vertex_count": below_ground_vertex_count,
            "lower_envelope_vertex_id": min_vertex_id,
            "replayed_vertex_count": replayed_vertex_count,
            "rightfoot_landmark_clearance_m": float(ground_row.get("rightfoot_clearance_m", INF)),
            "righttoebase_landmark_clearance_m": float(ground_row.get("righttoebase_clearance_m", INF))
        })

    var report := {
        "schema":"grand-bruxelles-civ1-rightfoot-geometry-ground-v1",
        "diagnostic_only":true,
        "sample_indices":TARGET_SAMPLES,
        "fixed_vertex_count":REQUIRED_VERTEX_COUNT,
        "ground_top_y_m":ground_top_y,
        "placement_y_m":placement_y,
        "skinning_formula":"posed_bone_global * inverse_bind * mesh_to_skeleton_rest * source_vertex, weighted by stored positive Skin weights",
        "samples":sample_reports,
        "geometry_below_ground_sample_count":geometry_below_ground_sample_count,
        "landmark_only_explanation_rejected":geometry_below_ground_sample_count > 0,
        "quantitative_foot_slide_candidate":false,
        "animation_correction_authorized":false,
        "runtime_authorized":false,
        "visual_approval_claimed":false,
        "player_view_claimed":false
    }
    if not _write_json(args[4], report):
        push_error("CIV1_GEOMETRY_GROUND_FAIL:output"); quit(13); return
    print("CIV1_GEOMETRY_GROUND_OK samples=", TARGET_SAMPLES.size(), " below_ground_samples=", geometry_below_ground_sample_count)
    quit(0)

func _posed_bone_transform(bone_name: String, poses: Dictionary, toe_row: Dictionary) -> Transform3D:
    if bone_name == "mixamorig_RightToeBase":
        return _pose(toe_row.get("derived_righttoebase_global", {}) as Dictionary)
    if bone_name == "mixamorig_RightFoot" and poses.has("RightFoot"):
        return _pose(poses["RightFoot"] as Dictionary)
    if bone_name == "mixamorig_RightLeg" and poses.has("RightLowerLeg"):
        return _pose(poses["RightLowerLeg"] as Dictionary)
    return Transform3D(Basis(Vector3(INF,0,0),Vector3(0,INF,0),Vector3(0,0,INF)), Vector3(INF,INF,INF))

func _vertex_id(v: Dictionary) -> String:
    return "%s|%08d|%08d" % [str(v.get("mesh_path", "")), int(v.get("surface", -1)), int(v.get("vertex", -1))]

func _transform_from_array(v: Variant) -> Transform3D:
    if not v is Array or v.size() != 12:
        return Transform3D(Basis(Vector3(INF,0,0),Vector3(0,INF,0),Vector3(0,0,INF)), Vector3(INF,INF,INF))
    var bx := Vector3(float(v[0]),float(v[1]),float(v[2]))
    var by := Vector3(float(v[3]),float(v[4]),float(v[5]))
    var bz := Vector3(float(v[6]),float(v[7]),float(v[8]))
    return Transform3D(Basis(bx,by,bz), Vector3(float(v[9]),float(v[10]),float(v[11])))

func _pose(rec: Dictionary) -> Transform3D:
    var o := _v3(rec.get("origin", []))
    var qv: Variant = rec.get("rotation_xyzw", [])
    if not qv is Array or qv.size() != 4:
        return Transform3D(Basis(Vector3(INF,0,0),Vector3(0,INF,0),Vector3(0,0,INF)), Vector3(INF,INF,INF))
    var q := Quaternion(float(qv[0]),float(qv[1]),float(qv[2]),float(qv[3])).normalized()
    return Transform3D(Basis(q), o)

func _v3(v: Variant) -> Vector3:
    if not v is Array or v.size() != 3:
        return Vector3(INF,INF,INF)
    return Vector3(float(v[0]),float(v[1]),float(v[2]))

func _finite_v3(v: Vector3) -> bool:
    return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)

func _finite_transform(t: Transform3D) -> bool:
    return _finite_v3(t.basis.x) and _finite_v3(t.basis.y) and _finite_v3(t.basis.z) and _finite_v3(t.origin)

func _read_json(path: String) -> Variant:
    var f := FileAccess.open(path, FileAccess.READ)
    if f == null:
        return null
    var value: Variant = JSON.parse_string(f.get_as_text())
    f.close()
    return value

func _write_json(path: String, data: Dictionary) -> bool:
    var f := FileAccess.open(path, FileAccess.WRITE)
    if f == null:
        return false
    f.store_string(JSON.stringify(data, "  ") + "\n")
    f.close()
    return true
