from pathlib import Path

P = Path(__file__).parents[1] / "tools" / "godot_civ1_body_head_witness.gd"


def source() -> str:
    return P.read_text(encoding="utf-8")


def test_uses_source_documented_head_attachment_contract():
    s = source()
    assert 'const HEAD_BONE := "mixamorig_Head"' in s
    assert "BoneAttachment3D.new()" in s
    assert "attachment.bone_idx = head_bone_idx" in s
    assert "head_rig.global_transform = Transform3D.IDENTITY" in s
    assert "head_rig.add_child(head)" in s


def test_fails_closed_on_missing_body_skeleton_or_head_bone():
    s = source()
    assert 'push_error("body Skeleton3D missing")' in s
    assert 'push_error("mixamorig_Head missing")' in s
    assert "if head_bone_idx < 0:" in s


def test_requires_full_material_binding_and_real_1280x720_capture():
    s = source()
    assert "head_material_surfaces == head_total_surfaces" in s
    assert "root.size = Vector2i(1280, 720)" in s
    assert "image.save_png(frame_path) == OK" in s
    assert '"frame_width"' in s and '"frame_height"' in s


def test_witness_cannot_self_authorize_runtime_or_visual_acceptance():
    s = source()
    assert '"runtime_authorized": false' in s
    assert '"visual_approval_claimed": false' in s
    assert '"AMELIORER_BODY_HEAD_WITNESS"' in s
    assert '"JETER_BODY_HEAD_WITNESS"' in s
