import bpy, importlib.util, json, math, sys
from pathlib import Path
from mathutils import Matrix


def arg(name, default=None):
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    return args[args.index(name) + 1] if name in args else default


def load_normalizer(path):
    spec = importlib.util.spec_from_file_location("steve_normalizer", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def basis_metrics(matrix):
    b = matrix.to_3x3()
    cols = [b.col[i].copy() for i in range(3)]
    scales = [float(c.length) for c in cols]
    unit = [c.normalized() if c.length > 1e-12 else c for c in cols]
    shear = max(abs(float(unit[0].dot(unit[1]))), abs(float(unit[0].dot(unit[2]))), abs(float(unit[1].dot(unit[2]))))
    positive = [s for s in scales if s > 1e-12]
    anisotropy = max(positive) / min(positive) if positive else float("inf")
    return {
        "scale": scales,
        "scale_anisotropy": float(anisotropy),
        "orthogonality_error": float(shear),
        "determinant": float(b.determinant()),
    }


def rigidized(matrix):
    out = matrix.to_quaternion().to_matrix().to_4x4()
    out.translation = matrix.translation.copy()
    return out


def regression_metrics():
    ident = Matrix.Identity(4)
    assert basis_metrics(ident)["orthogonality_error"] <= 1e-12
    shear = Matrix(((1.0, 0.25, 0.0, 0.0), (0.0, 1.0, 0.0, 0.0), (0.0, 0.0, 1.0, 0.0), (0.0, 0.0, 0.0, 1.0)))
    assert basis_metrics(shear)["orthogonality_error"] > 0.20


def setup_source(norm):
    norm.ensure_object_mode()
    arms = [o for o in bpy.data.objects if o.type == "ARMATURE"]
    assert len(arms) == 1, len(arms)
    src = arms[0]
    walks = [a for a in bpy.data.actions if a.name.lower() == "walk"]
    assert len(walks) == 1, [a.name for a in bpy.data.actions]
    if src.animation_data is None:
        src.animation_data_create()
    src.animation_data.action = walks[0]
    for track in src.animation_data.nla_tracks:
        track.mute = True
    return src, walks[0]


def sample_frame(norm, src, frame):
    bpy.context.scene.frame_set(frame)
    bpy.context.view_layer.update()
    return {role: src.pose.bones[norm.ROLE_MAP[role]].matrix.copy() for role in norm.ROLE_ORDER}


def assign_all(norm, dst, desired, override_role=None, override_matrix=None):
    for role in norm.ROLE_ORDER:
        matrix = override_matrix if role == override_role and override_matrix is not None else desired[role]
        norm.assign_pose_matrix(dst, role, matrix)
    bpy.context.view_layer.update()


def pose_error(norm, dst, role, desired):
    name = norm.ROLE_MAP[role]
    actual = dst.pose.bones[name].matrix.copy()
    return {
        "position_error_m": float((actual.translation - desired.translation).length),
        "rotation_error_deg": float(norm.rdeg(actual, desired)),
        "actual_metrics": basis_metrics(actual),
    }


def parent_metrics(obj, bone_name):
    bone = obj.data.bones[bone_name]
    if bone.parent is None:
        return {"bone": "", "pose": basis_metrics(Matrix.Identity(4))}
    return {"bone": bone.parent.name, "pose": basis_metrics(obj.pose.bones[bone.parent.name].matrix)}


def apply_inherit_scale_policy(norm, src, dst, inherit_scale_none):
    signature = {}
    for role in norm.ROLE_ORDER:
        name = norm.ROLE_MAP[role]
        source_mode = str(src.data.bones[name].inherit_scale)
        dst.data.bones[name].inherit_scale = "NONE" if inherit_scale_none else source_mode
        signature[role] = {
            "bone": name,
            "source": source_mode,
            "proxy": str(dst.data.bones[name].inherit_scale),
        }
    bpy.context.view_layer.update()
    return signature


def trial(norm, src, frame, role, desired, rigid=False, inherit_scale_none=False):
    dst = norm.make_proxy(src)
    signature = apply_inherit_scale_policy(norm, src, dst, inherit_scale_none)
    if inherit_scale_none:
        assert all(v["proxy"] == "NONE" for v in signature.values())
    else:
        assert all(v["proxy"] == v["source"] for v in signature.values())
    override = rigidized(desired[role]) if rigid else None
    assign_all(norm, dst, desired, role if rigid else None, override)
    result = pose_error(norm, dst, role, rigidized(desired[role]) if rigid else desired[role])
    result["inherit_scale_none"] = inherit_scale_none
    result["inherit_scale_policy"] = "NONE" if inherit_scale_none else "SOURCE_PRESERVED"
    result["inherit_scale_signature"] = signature
    result["rigid_desired"] = rigid
    result["proxy_parent"] = parent_metrics(dst, norm.ROLE_MAP[role])
    return result


def main():
    regression_metrics()
    norm = load_normalizer(arg("--normalizer"))
    report_path = Path(arg("--report", "/tmp/steve-affine-diagnostic.json"))
    src, walk = setup_source(norm)
    fs = int(math.floor(walk.frame_range[0]))
    fe = max(fs + 1, int(math.ceil(walk.frame_range[1])))
    worst = None
    worst_desired = None
    for frame in range(fs, fe + 1):
        desired = sample_frame(norm, src, frame)
        dst = norm.make_proxy(src)
        # Reproduce the current proxy policy for the original-failure scan.
        apply_inherit_scale_policy(norm, src, dst, True)
        assign_all(norm, dst, desired)
        for role in norm.ROLE_ORDER:
            err = pose_error(norm, dst, role, desired[role])
            if worst is None or err["rotation_error_deg"] > worst["rotation_error_deg"]:
                worst = {
                    "frame": frame,
                    "role": role,
                    "bone": norm.ROLE_MAP[role],
                    "position_error_m": err["position_error_m"],
                    "rotation_error_deg": err["rotation_error_deg"],
                    "desired_metrics": basis_metrics(desired[role]),
                    "actual_metrics": err["actual_metrics"],
                    "source_parent": parent_metrics(src, norm.ROLE_MAP[role]),
                    "proxy_parent": parent_metrics(dst, norm.ROLE_MAP[role]),
                }
                worst_desired = desired
    assert worst is not None
    frame = int(worst["frame"])
    role = str(worst["role"])
    sample_frame(norm, src, frame)
    rigid_preserved = trial(norm, src, frame, role, worst_desired, rigid=True, inherit_scale_none=False)
    rigid_no_inherit = trial(norm, src, frame, role, worst_desired, rigid=True, inherit_scale_none=True)
    assert rigid_preserved["inherit_scale_policy"] == "SOURCE_PRESERVED"
    assert rigid_no_inherit["inherit_scale_policy"] == "NONE"
    if worst["rotation_error_deg"] <= 0.10:
        state = "NO_POSE_REPRESENTABILITY_FAILURE_REPRODUCED"
    elif rigid_preserved["rotation_error_deg"] <= 0.10:
        state = "DESIRED_AFFINE_COMPONENTS_CAUSE_ROTATION_MISMATCH"
    elif rigid_no_inherit["rotation_error_deg"] <= 0.10:
        state = "PARENT_SCALE_INHERITANCE_CAUSES_ROTATION_MISMATCH"
    else:
        state = "POSE_CHANNEL_REPRESENTABILITY_UNRESOLVED"
    report = {
        "format": "grand-bruxelles-steve-reviewed-proxy-affine-diagnostic-v2",
        "blender_version": bpy.app.version_string,
        "walk_frame_start": fs,
        "walk_frame_end": fe,
        "reviewed_role_count": len(norm.ROLE_ORDER),
        "diagnostic_policy_isolation_verified": True,
        "worst_original_assignment": worst,
        "rigid_desired_preserved_inheritance": rigid_preserved,
        "rigid_desired_no_scale_inheritance": rigid_no_inherit,
        "mechanical_state": state,
        "retarget_applied": False,
        "runtime_authorized": False,
    }
    report_path.write_text(json.dumps(report, indent=2, sort_keys=True))
    print("GATE8_STEVE_AFFINE_DIAGNOSTIC_OK state=%s worst_role=%s worst_rot_deg=%.6f rigid_preserved_rot_deg=%.6f no_scale_rot_deg=%.6f policy_isolation=true" % (state, role, worst["rotation_error_deg"], rigid_preserved["rotation_error_deg"], rigid_no_inherit["rotation_error_deg"]))


if __name__ == "__main__":
    main()
