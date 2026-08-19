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

OUTPUT_FBX = os.environ.get("GB_MAKEHUMAN_OUTPUT", "/tmp/gb_makehuman_female_pilot.fbx")


def _pick_exact(paths, basename):
    target = basename.lower()
    matches = [p for p in paths if os.path.basename(p).lower() == target]
    if not matches:
        raise RuntimeError("required MakeHuman system asset missing: %s" % basename)
    return sorted(matches)[0]


def _pick_first(paths, label):
    paths = sorted(paths)
    if not paths:
        raise RuntimeError("no MakeHuman system %s assets available" % label)
    return paths[0]


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
        human.setHeight(0.52)
        human.applyAllTargets()

        clothes = _pick_exact(api.assets.getAvailableSystemClothes(), "female_elegantsuit01.mhclo")
        api.assets.unequipAllClothes()
        api.assets.equipClothes(clothes)

        hair = _pick_first(api.assets.getAvailableSystemHair(), "hair")
        api.assets.equipHair(hair)

        eyebrows = _pick_first(api.assets.getAvailableSystemEyebrows(), "eyebrow")
        api.assets.equipEyebrows(eyebrows)

        eyelashes = _pick_first(api.assets.getAvailableSystemEyelashes(), "eyelash")
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

        print("GB_MAKEHUMAN_CANDIDATE_OK output=%s bytes=%d height_cm=%.2f hair=%s clothes=%s" % (
            OUTPUT_FBX,
            os.path.getsize(OUTPUT_FBX),
            human.getHeightCm(),
            os.path.basename(hair),
            os.path.basename(clothes),
        ))
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
