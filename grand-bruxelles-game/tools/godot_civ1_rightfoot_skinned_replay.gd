extends SceneTree

const TARGET_SAMPLES := [68, 69, 70, 71]
const REQUIRED_VERTEX_COUNT := 3306
const WEIGHT_SUM_TOLERANCE := 0.0001

func _initialize() -> void:
    var args := OS.get_cmdline_user_args()
    if args.size() != 4:
        push_error("CIV1_SKINNED_REPLAY_FAIL:args"); quit(2); return
    var bind_basis: Variant = _read_json(args[0])
    var skeleton_bundle: Variant = _read_json(args[1])
    var toe_pose: Variant = _read_json(args[2])
    if not bind_basis is Dictionary or bind_basis.get("schema", "") != "grand-bruxelles-civ1-rightfoot-bind-pose-basis-v1":
        push_error("CIV1_SKINNED_REPLAY_FAIL:bind-basis"); quit(3); return
    if not skeleton_bundle is Dictionary or skeleton_bundle.get("schema", "") != "grand-bruxelles-civ1-skeleton-witness-bundle-v1":
        push_error("CIV1_SKINNED_REPLAY_FAIL:skeleton-bundle"); quit(4); return
    if not toe_pose is Dictionary or toe_pose.get("schema", "") != "grand-bruxelles-civ1-righttoebase-pose-v1":
        push_error("CIV1_SKINNED_REPLAY_FAIL:toe-pose"); quit(5); return
    if int(bind_basis.get("selection_vertex_count", -1)) != REQUIRED_VERTEX_COUNT or not bool(bind_basis.get("bind_space_complete", false)):
        push_error("CIV1_SKINNED_REPLAY_FAIL:bind-completeness"); quit(6); return
    var toe_sample_indices: Variant = toe_pose.get("sample_indices", [])
    if not _sample_indices_match(toe_sample_indices) or not bool(toe_pose.get("pose_coverage_ready", false)):
        push_error("CIV1_SKINNED_REPLAY_FAIL:pose-coverage samples=%s ready=%s" % [str(toe_sample_indices), str(toe_pose.get("pose_coverage_ready", null))]); quit(7); return

    var frames: Array = skeleton_bundle.get("frames", [])
    if frames.size() != 120:
        push_error("CIV1_SKINNED_REPLAY_FAIL:frame-count"); quit(8); return
    var toe_by_sample := {}
    for row in toe_pose.get("samples", []):
        toe_by_sample[int(row.get("sample_index", -1))] = row

    var vertices: Array = bind_basis.get("vertices", [])
    if vertices.size() != REQUIRED_VERTEX_COUNT:
        push_error("CIV1_SKINNED_REPLAY_FAIL:vertex-count"); quit(9); return
    var ids := {}
    for v in vertices:
        var id := _vertex_id(v)
        if ids.has(id):
            push_error("CIV1_SKINNED_REPLAY_FAIL:duplicate-id"); quit(10); return
        ids[id] = true

    var sample_reports: Array = []
    var stable_replay_sample_count := 0
    for sample_index in TARGET_SAMPLES:
        var frame := frames[sample_index] as Dictionary
        if int(frame.get("sample_index", -1)) != sample_index or not toe_by_sample.has(sample_index):
            push_error("CIV1_SKINNED_REPLAY_FAIL:sample-index"); quit(11); return
        var poses := frame.get("poses", {}) as Dictionary
        var toe_row := toe_by_sample[sample_index] as Dictionary
        var replayed: Array = []
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
                var bone_name := str(influence.get("bone_name", ""))
                var posed_bone := _posed_bone_transform(bone_name, poses, toe_row)
                var inverse_bind := _transform_from_array(influence.get("inverse_bind_transform", []))
                if not _finite_transform(posed_bone) or not _finite_transform(inverse_bind):
                    nonfinite_count += 1; continue
                accum += (posed_bone * inverse_bind * p_skeleton_rest) * w
                weight_sum += w
            if abs(weight_sum - 1.0) > WEIGHT_SUM_TOLERANCE:
                bad_weight_sum_count += 1
            replayed.append({"id":_vertex_id(v), "position":[accum.x, accum.y, accum.z], "weight_sum":weight_sum})
        var valid := replayed.size() == REQUIRED_VERTEX_COUNT and nonfinite_count == 0 and bad_weight_sum_count == 0
        if valid: stable_replay_sample_count += 1
        var centroid := _centroid(replayed)
        var bounds := _bounds(replayed)
        sample_reports.append({
            "sample_index":sample_index,
            "replayed_vertex_count":replayed.size(),
            "nonfinite_count":nonfinite_count,
            "bad_weight_sum_count":bad_weight_sum_count,
            "replay_sample_valid":valid,
            "centroid":[centroid.x,centroid.y,centroid.z],
            "aabb_min":[bounds[0].x,bounds[0].y,bounds[0].z],
            "aabb_max":[bounds[1].x,bounds[1].y,bounds[1].z]
        })

    var replay_ready := stable_replay_sample_count >= 3
    var report := {
        "schema":"grand-bruxelles-civ1-rightfoot-skinned-replay-v1",
        "diagnostic_only":true,
        "sample_indices":TARGET_SAMPLES,
        "fixed_vertex_count":REQUIRED_VERTEX_COUNT,
        "stable_replay_sample_count":stable_replay_sample_count,
        "skinned_replay_ready":replay_ready,
        "skinning_formula":"posed_bone_global * inverse_bind * mesh_to_skeleton_rest * source_vertex, weighted by stored positive Skin weights",
        "semantic_aliases":{"mixamorig_RightLeg":"RightLowerLeg","mixamorig_RightFoot":"RightFoot","mixamorig_RightToeBase":"RightToeBase"},
        "samples":sample_reports,
        "contact_phase_ready":false,
        "quantitative_foot_slide_candidate":false,
        "animation_correction_authorized":false,
        "runtime_authorized":false,
        "visual_approval_claimed":false,
        "player_view_claimed":false
    }
    if not _write_json(args[3], report):
        push_error("CIV1_SKINNED_REPLAY_FAIL:output"); quit(12); return
    if not replay_ready:
        push_error("CIV1_SKINNED_REPLAY_FAIL:insufficient-stable-samples"); quit(13); return
    print("CIV1_SKINNED_REPLAY_OK vertices=", REQUIRED_VERTEX_COUNT, " stable_samples=", stable_replay_sample_count)
    quit(0)

func _sample_indices_match(value: Variant) -> bool:
    if not value is Array or value.size() != TARGET_SAMPLES.size():
        return false
    for i in TARGET_SAMPLES.size():
        if int(value[i]) != int(TARGET_SAMPLES[i]):
            return false
    return true

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
    if not v is Array or v.size() != 3: return Vector3(INF,INF,INF)
    return Vector3(float(v[0]),float(v[1]),float(v[2]))

func _finite_v3(v: Vector3) -> bool:
    return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)

func _finite_transform(t: Transform3D) -> bool:
    return _finite_v3(t.basis.x) and _finite_v3(t.basis.y) and _finite_v3(t.basis.z) and _finite_v3(t.origin)

func _centroid(rows: Array) -> Vector3:
    if rows.is_empty(): return Vector3(INF,INF,INF)
    var c := Vector3.ZERO
    for row in rows: c += _v3(row.get("position", []))
    return c / float(rows.size())

func _bounds(rows: Array) -> Array:
    if rows.is_empty(): return [Vector3(INF,INF,INF),Vector3(INF,INF,INF)]
    var lo := _v3(rows[0].get("position", [])); var hi := lo
    for row in rows:
        var p := _v3(row.get("position", []))
        lo = Vector3(min(lo.x,p.x),min(lo.y,p.y),min(lo.z,p.z))
        hi = Vector3(max(hi.x,p.x),max(hi.y,p.y),max(hi.z,p.z))
    return [lo,hi]

func _read_json(path: String) -> Variant:
    var f := FileAccess.open(path, FileAccess.READ)
    if f == null: return null
    var value: Variant = JSON.parse_string(f.get_as_text()); f.close(); return value

func _write_json(path: String, data: Dictionary) -> bool:
    var f := FileAccess.open(path, FileAccess.WRITE)
    if f == null: return false
    f.store_string(JSON.stringify(data, "  ")); f.close(); return true
