#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
TOOL = HERE / "tools" / "analyze_civ1_player_distance_raster.py"
spec = importlib.util.spec_from_file_location("distance_analysis", TOOL)
assert spec and spec.loader
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


class FakeSole:
    def __init__(self, fail_8m: bool = False):
        self.fail_8m = fail_8m

    def bottom_silhouette(self, path: Path) -> dict:
        distance = int(path.name.split("-")[2][:-1])
        sample = int(path.name.rsplit("-", 1)[1].split(".")[0])
        if self.fail_8m and distance == 8 and sample == 116:
            raise ValueError("insufficient rendered silhouette pixels")
        scale = {2: 2.0, 4: 1.0, 8: 0.5}[distance]
        return {
            "bottom_y_px": 350,
            "bottom_min_x_px": 500,
            "bottom_max_x_px": 530,
            "bottom_centroid_x_px": 500.0 + (sample - 115) * scale,
            "bottom_pixel_count": 40,
        }


def _captures(root: Path) -> None:
    for distance in mod.DISTANCES:
        for sample in mod.SAMPLES:
            (root / f"civ1-distance-{distance}m-{sample}.png").write_bytes(b"fixture")


def _fake_multirow(_sole, path: Path) -> dict:
    distance = int(path.name.split("-")[2][:-1])
    sample = int(path.name.rsplit("-", 1)[1].split(".")[0])
    scale = {2: 1.9, 4: 0.95, 8: 0.48}[distance]
    return {
        "bottom_y_px": 350,
        "row_depth": 4,
        "pixel_count": 80,
        "centroid_x_px": 500.0 + (sample - 115) * scale,
        "centroid_y_px": 348.5,
    }


def _bad_multirow_direction(_sole, path: Path) -> dict:
    distance = int(path.name.split("-")[2][:-1])
    sample = int(path.name.rsplit("-", 1)[1].split(".")[0])
    scale = {2: -1.9, 4: 1.8, 8: 0.48}[distance]
    return {
        "bottom_y_px": 350,
        "row_depth": 4,
        "pixel_count": 80,
        "centroid_x_px": 500.0 + (sample - 115) * scale,
        "centroid_y_px": 348.5,
    }


def main() -> None:
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        _captures(root)
        original_load = mod._load_sole_module
        original_multirow = mod._multirow_silhouette
        try:
            mod._multirow_silhouette = _fake_multirow
            mod._load_sole_module = lambda: FakeSole(False)
            report = mod.analyze(root)
            assert report["schema"].endswith("v3")
            assert report["primary_unresolved_distances_m"] == []
            assert report["multirow_unresolved_distances_m"] == []
            assert report["raw_recovered_by_multirow_distances_m"] == []
            assert report["qualified_recovered_by_multirow_distances_m"] == []
            assert report["multirow_calibration"]["passed"] is True
            assert [d["primary"]["bottom_centroid_path_px"] for d in report["distance_measurements"]] == [6.0, 3.0, 1.5]
            assert [round(d["multirow"]["centroid_path_px"], 2) for d in report["distance_measurements"]] == [5.7, 2.85, 1.44]
            assert all(d["ab_direction_match"] is True for d in report["distance_measurements"])
            assert all(d["ab_agreement_claimed"] is False for d in report["distance_measurements"])
            for key in ("perceptual_2_8m_claimed", "planted_contact_claimed", "animation_correction_authorized", "runtime_authorized", "visual_approval_claimed", "player_view_claimed"):
                assert report[key] is False

            mod._load_sole_module = lambda: FakeSole(True)
            report = mod.analyze(root)
            assert report["primary_unresolved_distances_m"] == [8]
            assert report["multirow_unresolved_distances_m"] == []
            assert report["raw_recovered_by_multirow_distances_m"] == [8]
            assert report["qualified_recovered_by_multirow_distances_m"] == [8]
            assert report["multirow_calibration"]["passed"] is True
            eight = report["distance_measurements"][2]
            assert eight["primary"]["measurement_resolved"] is False
            assert eight["primary"]["bottom_centroid_path_px"] is None
            assert eight["multirow"]["measurement_resolved"] is True
            assert round(eight["multirow"]["centroid_path_px"], 2) == 1.44
            assert report["verdict"] == "AMELIORER_MULTIROW_CALIBRATED_RECOVERY_AVAILABLE_NO_PROMOTION"

            mod._multirow_silhouette = _bad_multirow_direction
            report = mod.analyze(root)
            assert report["raw_recovered_by_multirow_distances_m"] == [8]
            assert report["qualified_recovered_by_multirow_distances_m"] == []
            assert report["multirow_calibration"]["passed"] is False
            failures = {f["distance_m"]: f["reasons"] for f in report["multirow_calibration"]["failures"]}
            assert "signed_direction_mismatch_or_under_signal" in failures[2]
            assert "path_relative_difference_exceeds_tolerance" in failures[4]
            assert report["verdict"] == "AMELIORER_MULTIROW_FALLBACK_REJECTED_BY_CALIBRATION_NO_PROMOTION"

            def fail_multirow(_sole, path: Path) -> dict:
                if "-8m-116.png" in path.name:
                    raise ValueError("insufficient multirow silhouette pixels")
                return _fake_multirow(_sole, path)

            mod._multirow_silhouette = fail_multirow
            report = mod.analyze(root)
            assert report["primary_unresolved_distances_m"] == [8]
            assert report["multirow_unresolved_distances_m"] == [8]
            assert report["raw_recovered_by_multirow_distances_m"] == []
            assert report["qualified_recovered_by_multirow_distances_m"] == []
            assert report["distance_measurements"][2]["multirow"]["centroid_path_px"] is None
        finally:
            mod._load_sole_module = original_load
            mod._multirow_silhouette = original_multirow
    print("CIV1_PLAYER_DISTANCE_RASTER_ANALYZER_TEST_OK")


if __name__ == "__main__":
    main()
