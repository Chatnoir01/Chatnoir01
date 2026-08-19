#!/usr/bin/env python3
"""Loaded as the last MakeHuman plugin by the candidate-review workflow.

Review-only generator: one rigged, clothed adult civilian. The workflow copies this
file to MakeHuman's plugins/z_grand_bruxelles_candidate.py so it executes after
MHAPI, geometry libraries, skeleton library and exporters are registered.
"""
import os
import re
import sys
import traceback

import gui
import gui3d
import mh
import material

OUTPUT_FBX = os.environ.get("GB_MAKEHUMAN_OUTPUT", "/tmp/gb_makehuman_female_pilot.fbx")


def _pick_exact(paths, basename):
    target = basename.lower()
    matches = [p for p in paths if os.path.basename(p).lower() == target]
    if not matches:
        raise RuntimeError("required MakeHuman system asset missing: %s" % basename)
    return sorted(matches)[0]


def _repair_ascii_texture_connection_channels(filepath):
    """Repair the pinned MakeHuman ASCII FBX writer's Python-3 byte-channel output.

    Run #23 proved ASCII FBX fixed the earlier normal-index corruption: Godot/ufbx
    imported the candidate with zero `Clamped index` warnings. The same run also
    exposed the next independent defect: seven material surfaces imported, but zero
    textures were attached.

    Upstream `fbx_material.writeLinks()` passes channel names such as
    ``b"DiffuseColor"`` into `fbx_utils.opLink()`. The ASCII `opLink()` formats that
    value with ``%s``. Under Python 3 the FBX therefore receives the literal property
    name ``b'DiffuseColor'`` instead of ``DiffuseColor``. ufbx/Godot can still create
    the material objects but cannot attach those textures to the intended properties.

    Repair only OP connection property names in the generated review FBX. Geometry,
    vertex/normal indices, UVs, rig, material identities and texture paths are left
    byte-for-byte untouched outside those connection lines.
    """
    with open(filepath, "r", encoding="utf-8") as handle:
        text = handle.read()

    pattern = re.compile("(?m)(C:\\s*\"OP\",[^\\n]+,\\s*)\"b'([^']+)'\"")
    repaired_text, repaired_count = pattern.subn(
        lambda match: match.group(1) + '"' + match.group(2) + '"', text
    )
    if repaired_count <= 0:
        raise RuntimeError("MakeHuman ASCII FBX contained no Python-3 byte channel tokens to repair")

    bad_links = [
        line.strip()
        for line in repaired_text.splitlines()
        if 'C: "OP"' in line and '"b\'' in line
    ]
    if bad_links:
        raise RuntimeError("MakeHuman ASCII FBX still contains byte-valued texture channels: %s" % bad_links[:4])

    diffuse_links = sum(
        1
        for line in repaired_text.splitlines()
        if 'C: "OP"' in line and '"DiffuseColor"' in line
    )
    if diffuse_links < 4:
        raise RuntimeError(
            "MakeHuman ASCII FBX repaired too few diffuse texture links: %d" % diffuse_links
        )

    with open(filepath, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(repaired_text)

    return repaired_count, diffuse_links


def _run(app):
    try:
        api = app.mhapi
        human = gui3d.app.selectedHuman

        human.setGender(0.0)
        human.setAgeYears(34)
        human.setWeight(0.48)
        human.setMuscle(0.42)
        human.setHeight(0.58)
        human.applyAllTargets()

        skin = _pick_exact(api.assets.getAvailableSystemSkins(), "young_caucasian_female.mhmat")
        human.material = material.fromFile(skin)

        casual = _pick_exact(api.assets.getAvailableSystemClothes(), "female_casualsuit01.mhclo")
        shoes = _pick_exact(api.assets.getAvailableSystemClothes(), "shoes01.mhclo")
        api.assets.unequipAllClothes()
        api.assets.equipClothes(casual)
        api.assets.equipClothes(shoes)

        hair = _pick_exact(api.assets.getAvailableSystemHair(), "ponytail01.mhclo")
        api.assets.equipHair(hair)
        eyebrows = _pick_exact(api.assets.getAvailableSystemEyebrows(), "eyebrow004.mhclo")
        api.assets.equipEyebrows(eyebrows)
        eyelashes = _pick_exact(api.assets.getAvailableSystemEyelashes(), "eyelashes01.mhclo")
        api.assets.equipEyelashes(eyelashes)

        skeleton_task = api.ui.getTaskView("Pose/Animate", "Skeleton")
        if skeleton_task is None:
            raise RuntimeError("MakeHuman skeleton task is unavailable")
        rig_path = mh.getSysDataPath("rigs/default.mhskel")
        if not os.path.isfile(rig_path):
            raise RuntimeError("MakeHuman default rig missing: %s" % rig_path)
        skeleton_task.chooseSkeleton(rig_path)
        if human.getSkeleton() is None:
            raise RuntimeError("MakeHuman default rig was not assigned")

        exporter = api.exports.getFBXExporter()
        if exporter is None:
            raise RuntimeError("MakeHuman FBX exporter is unavailable")

        if not hasattr(exporter, "binary"):
            raise RuntimeError("MakeHuman FBX exporter Binary FBX control is unavailable")
        exporter.binary.setChecked(False)
        if bool(exporter.binary.selected):
            raise RuntimeError("MakeHuman FBX exporter refused ASCII mode")

        os.makedirs(os.path.dirname(OUTPUT_FBX), exist_ok=True)
        api.exports.exportAsFBX(OUTPUT_FBX, useExportsDir=False)
        if not os.path.isfile(OUTPUT_FBX) or os.path.getsize(OUTPUT_FBX) < 1024:
            raise RuntimeError("MakeHuman FBX export missing or implausibly small: %s" % OUTPUT_FBX)

        repaired_channels, diffuse_links = _repair_ascii_texture_connection_channels(OUTPUT_FBX)
        print(
            "GB_MAKEHUMAN_ASCII_TEXTURE_LINKS_OK repaired=%d diffuse_links=%d"
            % (repaired_channels, diffuse_links)
        )
        print(
            "GB_MAKEHUMAN_CANDIDATE_OK output=%s bytes=%d height_cm=%.2f skin=%s hair=%s clothes=%s shoes=%s fbx_binary=false"
            % (
                OUTPUT_FBX,
                os.path.getsize(OUTPUT_FBX),
                human.getHeightCm(),
                os.path.basename(skin),
                os.path.basename(hair),
                os.path.basename(casual),
                os.path.basename(shoes),
            )
        )
        sys.stdout.flush()
        gui.QtWidgets.QApplication.instance().quit()
    except Exception as exc:
        print("GB_MAKEHUMAN_CANDIDATE_FAIL: %s" % exc)
        traceback.print_exc()
        sys.stdout.flush()
        os._exit(2)


def load(app):
    mh.callAsync(_run, app)


def unload(app):
    pass
