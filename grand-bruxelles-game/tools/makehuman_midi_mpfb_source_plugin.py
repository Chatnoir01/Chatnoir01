#!/usr/bin/env python3
"""Generate the exact V4-shaped review civilian as an MHM source for MPFB.

This does not authorize any runtime asset. It intentionally mirrors the V4 body,
skin, clothing and hair choices so the MPFB/Blender pilot changes the authoring /
material pipeline rather than silently changing character identity.
"""
import os
import sys
import traceback

import gui
import gui3d
import mh
import material

OUTPUT_MHM = os.environ.get("GB_MAKEHUMAN_MHM_OUTPUT", "/tmp/gb_mpfb_source/FemalePilot.mhm")


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

        os.makedirs(os.path.dirname(OUTPUT_MHM), exist_ok=True)
        # Human.save() is the model-writing operation used by MakeHuman's own
        # guisave.saveMHM(); skipping the thumbnail keeps this CI source deterministic.
        human.save(OUTPUT_MHM)
        if not os.path.isfile(OUTPUT_MHM) or os.path.getsize(OUTPUT_MHM) < 512:
            raise RuntimeError("MHM source missing or implausibly small: %s" % OUTPUT_MHM)

        print(
            "GB_MPFB_MHM_SOURCE_OK output=%s bytes=%d height_cm=%.2f "
            "skin=%s hair=%s top=%s trousers=%s shoes=%s rig=default "
            "production_authorized=false source_identity=v4_control"
            % (
                OUTPUT_MHM,
                os.path.getsize(OUTPUT_MHM),
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
        print("GB_MPFB_MHM_SOURCE_FAIL: %s" % exc)
        traceback.print_exc()
        sys.stdout.flush()
        os._exit(2)


def load(app):
    mh.callAsync(_run, app)


def unload(app):
    pass
