#!/usr/bin/env python3
"""Loaded as the last MakeHuman plugin by the candidate-review workflow.

Review-only generator: one rigged, clothed adult civilian. The workflow copies this
file to MakeHuman's plugins/z_grand_bruxelles_candidate.py so it executes after
MHAPI, geometry libraries, skeleton library and exporters are registered.
"""
import os
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


def _run(app):
    try:
        api = app.mhapi
        human = gui3d.app.selectedHuman

        # Deterministic adult civilian proportions. This is a visual candidate, not a
        # demographic template; later roster profiles will deliberately vary these.
        human.setGender(0.0)
        human.setAgeYears(34)
        human.setWeight(0.48)
        human.setMuscle(0.42)
        human.setHeight(0.58)
        human.applyAllTargets()

        # The first witness accidentally exported the viewport/default skin, which made
        # the Godot result nearly white. Force a real CC0 system skin so the FBX exporter
        # emits the diffuse material used by the character.
        skin = _pick_exact(api.assets.getAvailableSystemSkins(), "young_caucasian_female.mhmat")
        human.material = material.fromFile(skin)

        # Prefer the simple full-body casual outfit over the alpha-heavy elegant skirt,
        # then add real shoes. These remain candidate-only until the visual gate passes.
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
        os.makedirs(os.path.dirname(OUTPUT_FBX), exist_ok=True)
        api.exports.exportAsFBX(OUTPUT_FBX, useExportsDir=False)
        if not os.path.isfile(OUTPUT_FBX) or os.path.getsize(OUTPUT_FBX) < 1024:
            raise RuntimeError("MakeHuman FBX export missing or implausibly small: %s" % OUTPUT_FBX)

        print(
            "GB_MAKEHUMAN_CANDIDATE_OK output=%s bytes=%d height_cm=%.2f skin=%s hair=%s clothes=%s shoes=%s"
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
