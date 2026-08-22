#!/usr/bin/env python3

import importlib.util
import json
import struct
import tempfile
import unittest
import zipfile
from pathlib import Path

MODULE_PATH = Path(__file__).resolve().parents[1] / "tools" / "gate8_retarget_source_probe.py"
spec = importlib.util.spec_from_file_location("gate8_retarget_source_probe", MODULE_PATH)
probe = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(probe)


def make_glb(animation_names: list[str]) -> bytes:
    document = {
        "asset": {"version": "2.0"},
        "animations": [{"name": name, "channels": [], "samplers": []} for name in animation_names],
    }
    raw_json = json.dumps(document, separators=(",", ":")).encode("utf-8")
    padded_json = raw_json + b" " * ((4 - len(raw_json) % 4) % 4)
    total_length = 12 + 8 + len(padded_json)
    return (
        struct.pack("<4sII", b"glTF", 2, total_length)
        + struct.pack("<II", len(padded_json), 0x4E4F534A)
        + padded_json
    )


class Gate8RetargetSourceProbeTests(unittest.TestCase):
    def test_exact_locomotion_tokens_exclude_action_and_transition_names(self):
        self.assertEqual(probe.classify_entry("Animations/Civil_Idle.glb"), ["idle"])
        self.assertEqual(probe.classify_entry("Animations/Civil_Walk.glb"), ["walk"])
        self.assertEqual(probe.classify_entry("Animations/Civil_Run.glb"), ["run"])
        self.assertEqual(probe.classify_entry("Animations/Attack_Run.glb"), [])
        self.assertEqual(probe.classify_entry("Animations/Idle_To_Walk.glb"), [])
        self.assertEqual(probe.classify_entry("Animations/Walk_To_Idle.glb"), [])
        self.assertEqual(probe.classify_entry("Animations/Walk_Backward.glb"), [])
        self.assertEqual(probe.classify_entry("Animations/Run_Start.glb"), [])
        self.assertEqual(probe.classify_entry("Animations/Runway_Look.glb"), [])
        self.assertEqual(probe.classify_entry("Animations/Backpack_Walk.glb"), ["walk"])

    def test_internal_glb_catalog_is_parsed_and_classified_exactly(self):
        names = ["Civil_Idle", "Civil_Walk", "Civil_Run", "Attack_Run", "Idle_To_Walk", "Runway_Look"]
        payload = make_glb(names)
        self.assertEqual(probe.internal_animation_names(payload), names)
        self.assertEqual(probe.classify_entry("Civil_Idle"), ["idle"])
        self.assertEqual(probe.classify_entry("Attack_Run"), [])
        self.assertEqual(probe.classify_entry("Runway_Look"), [])

    def test_characterization_reads_godot_glb_internal_catalog_but_stays_fail_closed(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            archive_path = Path(temp_dir) / "source.zip"
            with zipfile.ZipFile(archive_path, "w", zipfile.ZIP_DEFLATED) as archive:
                archive.writestr(
                    probe.GODOT_STANDARD_GLB,
                    make_glb(["Civil_Idle", "Civil_Walk", "Civil_Run", "Attack_Run"]),
                )
                archive.writestr("Animation Library[Standard]/Unity/AnimationLibrary_Unity_Standard.fbx", b"fbx")
                archive.writestr("Animation Library[Standard]/Unreal Engine/AL_Standard.fbx", b"fbx")
                archive.writestr("LICENSE.txt", b"CC0")

            result = probe.characterize(archive_path)
            self.assertFalse(result["complete_filename_token_surface"])
            self.assertTrue(result["complete_internal_token_surface"])
            self.assertTrue(result["exact_single_idle_walk_run_trio"])
            self.assertEqual(result["internal_animation_count"], 4)
            self.assertEqual(result["internal_token_hits"]["idle"], ["Civil_Idle"])
            self.assertEqual(result["internal_token_hits"]["walk"], ["Civil_Walk"])
            self.assertEqual(result["internal_token_hits"]["run"], ["Civil_Run"])
            self.assertFalse(result["production_authorized"])
            self.assertFalse(result["retarget_authorized"])
            self.assertFalse(result["adoption_ready"])
            self.assertTrue(result["manual_player_view_required"])
            self.assertTrue(result["godot_4_7_1_retarget_required"])
            self.assertTrue(result["foot_slide_measurement_required"])
            self.assertEqual(result["candidate_variant"], 1)
            self.assertEqual(len(result["package_sha256"]), 64)

    def test_duplicate_or_unnamed_internal_animations_are_rejected(self):
        with self.assertRaisesRegex(ValueError, "not unique"):
            probe.internal_animation_names(make_glb(["Civil_Idle", "Civil_Idle"]))

        document = {"asset": {"version": "2.0"}, "animations": [{"channels": [], "samplers": []}]}
        raw_json = json.dumps(document, separators=(",", ":")).encode("utf-8")
        padded_json = raw_json + b" " * ((4 - len(raw_json) % 4) % 4)
        payload = (
            struct.pack("<4sII", b"glTF", 2, 12 + 8 + len(padded_json))
            + struct.pack("<II", len(padded_json), 0x4E4F534A)
            + padded_json
        )
        with self.assertRaisesRegex(ValueError, "no stable non-empty name"):
            probe.internal_animation_names(payload)

    def test_empty_archive_is_rejected(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            archive_path = Path(temp_dir) / "empty.zip"
            with zipfile.ZipFile(archive_path, "w"):
                pass
            with self.assertRaisesRegex(ValueError, "empty source archive"):
                probe.characterize(archive_path)


if __name__ == "__main__":
    unittest.main()