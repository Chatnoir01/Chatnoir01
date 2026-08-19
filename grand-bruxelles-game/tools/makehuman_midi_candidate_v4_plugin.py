#!/usr/bin/env python3
"""Review-only MakeHuman V4 civilian generator for the Midi fidelity gate.

V4 keeps the proven patched binary-FBX rig path and the natural CC0 skin from V3,
while restoring the face-clear ponytail and clean tucked casual top that rendered
without the dominant V3 hair occlusion / sweater skin-peek defects.
"""
import os
import sys
import traceback

import gui
import gui3d
import mh
import material

OUTPUT_FBX = os.environ.get("GB_MAKEHUMAN_OUTPUT", "/tmp/gb_makehuman_v4_female_pilot.fbx")


def _pick_exact(paths, basename):
    target = basename.lower()
    matches = [p for p in paths if os.path.basename(p).lower() == target]
    if not matches:
        raise RuntimeError("required MakeHuman asset missing: %s" % basename)
    return sorted(matches)[0]


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

        skin = _pick_exact(
            api.assets.getAvailableSystemSkins(),
            "onlytheghosts_young_eurasian_female.mhmat",
        )
        human.material = material.fromFile(skin)

        top = _pick_exact(
            api.assets.getAvailableSystemClothes(),
            "toigo_basic_tucked_t-shirt.mhclo",
        )
        trousers = _pick_exact(
            api.assets.getAvailableSystemClothes(),
            "cortu_cargo_pants.mhclo",
        )
        shoes = _pick_exact(api.assets.getAvailableSystemClothes(), "shoes04.mhclo")
        api.assets.unequipAllClothes()
        api.assets.equipClothes(top)
        api.assets.equipClothes(trousers)
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
        exporter.binary.setChecked(True)
        if not bool(exporter.binary.selected):
            raise RuntimeError("MakeHuman FBX exporter refused binary mode")

        os.makedirs(os.path.dirname(OUTPUT_FBX), exist_ok=True)
        api.exports.exportAsFBX(OUTPUT_FBX, useExportsDir=False)
        if not os.path.isfile(OUTPUT_FBX) or os.path.getsize(OUTPUT_FBX) < 1024:
            raise RuntimeError("MakeHuman FBX export missing or implausibly small: %s" % OUTPUT_FBX)

        print(
            "GB_MAKEHUMAN_V4_CANDIDATE_OK output=%s bytes=%d height_cm=%.2f "
            "skin=%s hair=%s top=%s trousers=%s shoes=%s fbx_binary=true "
            "art_variant=civilian_v4_natural_skin_face_clear_casual"
            % (
                OUTPUT_FBX,
                os.path.getsize(OUTPUT_FBX),
                human.getHeightCm(),
                os.path.basename(skin),
                os.path.basename(hair),
                os.path.basename(top),
                os.path.basename(trousers),
                os.path.basename(shoes),
            )
        )
        sys.stdout.flush()
        gui.QtWidgets.QApplication.instance().quit()
    except Exception as exc:
        print("GB_MAKEHUMAN_V4_CANDIDATE_FAIL: %s" % exc)
        traceback.print_exc()
        sys.stdout.flush()
        os._exit(2)


def load(app):
    mh.callAsync(_run, app)


def unload(app):
    pass
