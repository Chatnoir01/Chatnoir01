extends SceneTree

const REQUIRED_VERTEX_COUNT := 3306
const REQUIRED_FRAME_COUNT := 120
const WEIGHT_SUM_TOLERANCE := 0.0001

func _initialize() -> void:
    var args := OS.get_cmdline_user_args()
    if args.size() != 6:
        push_error("CIV1_GROUND_GEOMETRY_WINDOWS_FAIL:args"); quit(2); return
    var bind_basis: Variant = _read_json(args[0])
    var skeleton_bundle: Variant = _read_json(args[1])
    var toe_pose: Variant = _read_json(args[2])
    var windows_receipt: Variant = _read_json(args[3])
    var ground_receipt: Variant = _read_json(args[4])
    if not bind_basis is Dictionary or bind_basis.get("schema", "") != "grand-bruxelles-civ1-rightfoot-bind-pose-basis-v1":
        push_error("CIV1_GROUND_GEOMETRY_WINDOWS_FAIL:bind"); quit(3); return
    if not skeleton_bundle is Dictionary or skeleton_bundle.get("schema", "") != "grand-bruxelles-civ1-skeleton-witness-bundle-v1":
        push_error("CIV1_GROUND_GEOMETRY_WINDOWS_FAIL:skeleton"); quit(4); return
    if not toe_pose is Dictionary or toe_pose.get("schema", "") != "grand-bruxelles-civ1-righttoebase-full-pose-v1":
        push_error("CIV1_GROUND_GEOMETRY_WINDOWS_FAIL:toe"); quit(5); return
    if not bool(toe_pose.get("same_sample_ground_geometry_ready", false)):
        push_error("CIV1_GROUND_GEOMETRY_WINDOWS_FAIL:toe-readiness"); quit(6); return
    if not windows_receipt is Dictionary or windows_receipt.get("schema", "") != "grand-bruxelles-civ1-ground-candidate-windows-v1":
        push_error("CIV1_GROUND_GEOMETRY_WINDOWS_FAIL:windows"); quit(7); return
    if not ground_receipt is Dictionary or ground_receipt.get("schema", "") != "grand-bruxelles-civ1-rightfoot-same-sample-ground-v1":
        push_error("CIV1_GROUND_GEOMETRY_WINDOWS_FAIL:ground"); quit(8); return
    var vertices: Array = bind_basis.get("vertices", [])
    var frames: Array = skeleton_bundle.get("frames", [])
    var toe_samples: Array = toe_pose.get("samples", [])
    if vertices.size() != REQUIRED_VERTEX_COUNT or frames.size() != REQUIRED_FRAME_COUNT or toe_samples.size() != REQUIRED_FRAME_COUNT:
        push_error("CIV1_GROUND_GEOMETRY_WINDOWS_FAIL:shape"); quit(9); return
    var windows: Array = windows_receipt.get("same_sample_ground_geometry_windows", [])
    if windows.size() != 10:
        push_error("CIV1_GROUND_GEOMETRY_WINDOWS_FAIL:window-count"); quit(10); return
    var sample_set := {}
    for window in windows:
        if not window is Array or window.size() != 3:
            push_error("CIV1_GROUND_GEOMETRY_WINDOWS_FAIL:window-shape"); quit(11); return
        for sample in window:
            var index := int(sample)
            if index < 0 or index >= REQUIRED_FRAME_COUNT:
                push_error("CIV1_GROUND_GEOMETRY_WINDOWS_FAIL:window-index"); quit(12); return
            sample_set[index] = true
    var sample_indices: Array = sample_set.keys()
    sample_indices.sort()
    var ground_top_y := float(ground_receipt.get("ground_top_y_m", INF))
    if not is_finite(ground_top_y):
        push_error("CIV1_GROUND_GEOMETRY_WINDOWS_FAIL:ground-value"); quit(13); return
    var toe_by_sample := {}
    for row in toe_samples:
        toe_by_sample[int(row.get("sample_index", -1))] = row
    var reports: Array = []
    for sample_index in sample_indices:
        if not toe_by_sample.has(sample_index):
            push_error("CIV1_GROUND_GEOMETRY_WINDOWS_FAIL:toe-join"); quit(14); return
        var poses := (frames[sample_index] as Dictionary).get("poses", {}) as Dictionary
        var toe_row := toe_by_sample[sample_index] as Dictionary
        var raw_min_y := INF
        var raw_max_y := -INF
        var nonfinite_count := 0
        var bad_weight_sum_count := 0
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
                if w <= 0.0: continue
                var posed_bone := _posed_bone_transform(str(influence.get("bone_name", "")), poses, toe_row)
                var inverse_bind := _transform_from_array(influence.get("inverse_bind_transform", []))
                if not _finite_transform(posed_bone) or not _finite_transform(inverse_bind):
                    nonfinite_count += 1; continue
                accum += (posed_bone * inverse_bind * p_skeleton_rest) * w
                weight_sum += w
            if abs(weight_sum - 1.0) > WEIGHT_SUM_TOLERANCE:
                bad_weight_sum_count += 1
            if not _finite_v3(accum):
                nonfinite_count += 1; continue
            raw_min_y = min(raw_min_y, accum.y)
            raw_max_y = max(raw_max_y, accum.y)
        if nonfinite_count != 0 or bad_weight_sum_count != 0 or not is_finite(raw_min_y) or not is_finite(raw_max_y):
            push_error("CIV1_GROUND_GEOMETRY_WINDOWS_FAIL:replay-integrity"); quit(15); return
        reports.append({
            "sample_index":sample_index,
            "replayed_vertex_count":REQUIRED_VERTEX_COUNT,
            "raw_skinned_lower_envelope_y_m":raw_min_y,
            "raw_skinned_upper_envelope_y_m":raw_max_y,
            "geometry_derived_placement_to_ground_m":ground_top_y - raw_min_y
        })
    var report := {
        "schema":"grand-bruxelles-civ1-ground-geometry-windows-v1",
        "diagnostic_only":true,
        "fixed_vertex_count":REQUIRED_VERTEX_COUNT,
        "window_count":windows.size(),
        "windows":windows,
        "sample_indices":sample_indices,
        "ground_top_y_m":ground_top_y,
        "samples":reports,
        "same_sample_ground_geometry_ready":reports.size() == sample_indices.size(),
        "canonical_character_placement_available":false,
        "ground_contact_classifiable":false,
        "contact_proof_claimed":false,
        "planted_interval_claimable":false,
        "quantitative_foot_slide_candidate":false,
        "animation_correction_authorized":false,
        "runtime_authorized":false,
        "visual_approval_claimed":false,
        "player_view_claimed":false
    }
    if not _write_json(args[5], report):
        push_error("CIV1_GROUND_GEOMETRY_WINDOWS_FAIL:output"); quit(16); return
    print("CIV1_GROUND_GEOMETRY_WINDOWS_OK samples=", sample_indices.size(), " windows=", windows.size())
    quit(0)

func _posed_bone_transform(bone_name: String, poses: Dictionary, toe_row: Dictionary) -> Transform3D:
    if bone_name == "mixamorig_RightToeBase": return _pose(toe_row.get("derived_righttoebase_global", {}) as Dictionary)
    if bone_name == "mixamorig_RightFoot" and poses.has("RightFoot"): return _pose(poses["RightFoot"] as Dictionary)
    if bone_name == "mixamorig_RightLeg" and poses.has("RightLowerLeg"): return _pose(poses["RightLowerLeg"] as Dictionary)
    return Transform3D(Basis(Vector3(INF,0,0),Vector3(0,INF,0),Vector3(0,0,INF)), Vector3(INF,INF,INF))

func _transform_from_array(v: Variant) -> Transform3D:
    if not v is Array or v.size() != 12: return Transform3D(Basis(Vector3(INF,0,0),Vector3(0,INF,0),Vector3(0,0,INF)), Vector3(INF,INF,INF))
    return Transform3D(Basis(Vector3(float(v[0]),float(v[1]),float(v[2])),Vector3(float(v[3]),float(v[4]),float(v[5])),Vector3(float(v[6]),float(v[7]),float(v[8]))), Vector3(float(v[9]),float(v[10]),float(v[11])))

func _pose(rec: Dictionary) -> Transform3D:
    var o := _v3(rec.get("origin", [])); var qv: Variant = rec.get("rotation_xyzw", [])
    if not qv is Array or qv.size() != 4: return Transform3D(Basis(Vector3(INF,0,0),Vector3(0,INF,0),Vector3(0,0,INF)), Vector3(INF,INF,INF))
    return Transform3D(Basis(Quaternion(float(qv[0]),float(qv[1]),float(qv[2]),float(qv[3])).normalized()), o)
func _v3(v: Variant) -> Vector3:
    if not v is Array or v.size() != 3: return Vector3(INF,INF,INF)
    return Vector3(float(v[0]),float(v[1]),float(v[2]))
func _finite_v3(v: Vector3) -> bool: return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)
func _finite_transform(t: Transform3D) -> bool: return _finite_v3(t.basis.x) and _finite_v3(t.basis.y) and _finite_v3(t.basis.z) and _finite_v3(t.origin)
func _read_json(path: String) -> Variant:
    var f := FileAccess.open(path, FileAccess.READ); if f == null: return null
    var value: Variant = JSON.parse_string(f.get_as_text()); f.close(); return value
func _write_json(path: String, data: Dictionary) -> bool:
    var f := FileAccess.open(path, FileAccess.WRITE); if f == null: return false
    f.store_string(JSON.stringify(data, "  ") + "\n"); f.close(); return true
