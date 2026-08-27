#!/usr/bin/env python3
import argparse
import hashlib
from pathlib import Path

EXPECTED_GIT_BLOB_SHA1 = "9bdbd5868ef72ba57e3a22659817e400b85e7363"
OLD_EXPORT = '''        bpy.ops.export_scene.gltf(filepath=str(out),export_format="GLB",use_selection=True,export_animations=True,export_draco_mesh_compression_enable=False); assert out.is_file() and out.stat().st_size>0'''
NEW_EXPORT = '''        # Export only the mechanically verified reviewed proxy walk. Blender's
        # glTF Actions mode exports active actions or actions associated through
        # NLA. The previous active-action-only hardening still reimported with
        # zero walk-like actions, so bind the single baked action explicitly to
        # one NLA track and export NLA strips. This avoids action discovery on
        # Steve's original 55-bone controller rig while making the intended
        # animation association explicit for Blender's glTF collector.
        scene.frame_start=fs; scene.frame_end=fe
        if dst.animation_data is None: dst.animation_data_create()
        for nla_track in list(dst.animation_data.nla_tracks):
            dst.animation_data.nla_tracks.remove(nla_track)
        if src.animation_data is not None:
            src.animation_data.action=None
            for nla_track in list(src.animation_data.nla_tracks):
                src.animation_data.nla_tracks.remove(nla_track)
        removed_actions=[]
        for action in list(bpy.data.actions):
            if action != baked:
                removed_actions.append(action.name)
                bpy.data.actions.remove(action)
        baked.name="walk"
        assert len(bpy.data.actions)==1 and bpy.data.actions[0]==baked,[a.name for a in bpy.data.actions]
        nla_track=dst.animation_data.nla_tracks.new(); nla_track.name="walk"
        nla_strip=nla_track.strips.new("walk",fs,baked); nla_strip.action_frame_start=fs; nla_strip.action_frame_end=fe
        dst.animation_data.action=None
        assert len(dst.animation_data.nla_tracks)==1
        assert dst.animation_data.nla_tracks[0].name=="walk"
        assert len(dst.animation_data.nla_tracks[0].strips)==1
        assert dst.animation_data.nla_tracks[0].strips[0].action==baked
        report["export_animation_policy"]={"active_action":"","nla_track":"walk","nla_strips":True,"force_sampling":True,"frame_range":True,"frame_step":1,"frame_start":fs,"frame_end":fe}
        report["export_action_count"]=len(bpy.data.actions)
        report["export_nla_track_count"]=len(dst.animation_data.nla_tracks)
        report["removed_nonproxy_actions"]=sorted(removed_actions)
        write_report()
        bpy.ops.export_scene.gltf(filepath=str(out),export_format="GLB",use_selection=True,export_animations=True,export_nla_strips=True,export_force_sampling=True,export_frame_range=True,export_frame_step=1,export_draco_mesh_compression_enable=False); assert out.is_file() and out.stat().st_size>0'''


def git_blob_sha1(data: bytes) -> str:
    header = f"blob {len(data)}\0".encode("ascii")
    return hashlib.sha1(header + data).hexdigest()


def harden(source: str) -> str:
    count = source.count(OLD_EXPORT)
    if count != 1:
        raise AssertionError(f"expected exactly one legacy export call, got {count}")
    hardened = source.replace(OLD_EXPORT, NEW_EXPORT)
    for token in (
        "export_nla_strips=True",
        "export_force_sampling=True",
        "export_frame_range=True",
        "export_frame_step=1",
        'baked.name="walk"',
        'nla_track=dst.animation_data.nla_tracks.new()',
        'nla_strip=nla_track.strips.new("walk",fs,baked)',
        "dst.animation_data.action=None",
        "if action != baked:",
        "bpy.data.actions.remove(action)",
        "len(bpy.data.actions)==1",
        'report["export_nla_track_count"]',
    ):
        if token not in hardened:
            raise AssertionError(token)
    if OLD_EXPORT in hardened:
        raise AssertionError("legacy export call survived")
    return hardened


def regressions() -> None:
    fixture = "prefix\n" + OLD_EXPORT + "\nsuffix\n"
    output = harden(fixture)
    assert output.count("bpy.ops.export_scene.gltf") == 1
    assert "export_force_sampling=True" in output
    assert "export_nla_strips=True" in output
    assert 'nla_track=dst.animation_data.nla_tracks.new()' in output
    assert 'nla_strip=nla_track.strips.new("walk",fs,baked)' in output
    assert "dst.animation_data.action=None" in output
    assert "if action != baked:" in output
    assert "bpy.data.actions.remove(action)" in output
    try:
        harden("no exporter here")
    except AssertionError:
        pass
    else:
        raise AssertionError("missing legacy exporter must fail closed")
    print("GATE8_STEVE_NORMALIZER_EXPORT_HARDENING_REGRESSIONS_OK tests=2 nla_binding=true")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--skip-blob-check", action="store_true")
    args = parser.parse_args()
    regressions()
    data = args.input.read_bytes()
    blob = git_blob_sha1(data)
    if not args.skip_blob_check:
        assert blob == EXPECTED_GIT_BLOB_SHA1, (blob, EXPECTED_GIT_BLOB_SHA1)
    args.output.write_text(harden(data.decode("utf-8")), encoding="utf-8")
    print(
        "GATE8_STEVE_NORMALIZER_EXPORT_HARDENING_OK "
        f"input_git_blob={blob} nla_track=walk force_sampling=true frame_range=true nla_strips=true action_isolation=true"
    )


if __name__ == "__main__":
    main()
