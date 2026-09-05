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
        name = path.name
        distance = int(name.split("-")[2][:-1])
        sample = int(name.rsplit("-", 1)[1].split(".")[0])
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


def main() -> None:
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        _captures(root)
        original = mod._load_sole_module
        try:
            mod._load_sole_module = lambda: FakeSole(False)
            report = mod.analyze(root)
            assert report["unresolved_distances_m"] == []
            assert [d["bottom_centroid_path_px"] for d in report["distance_measurements"]] == [6.0, 3.0, 1.5]
            for key in ("perceptual_2_8m_claimed", "planted_contact_claimed", "animation_correction_authorized", "runtime_authorized", "visual_approval_claimed", "player_view_claimed"):
                assert report[key] is False

            mod._load_sole_module = lambda: FakeSole(True)
            report = mod.analyze(root)
            assert report["unresolved_distances_m"] == [8]
            assert report["distance_measurements"][2]["measurement_resolved"] is False
            assert report["distance_measurements"][2]["bottom_centroid_path_px"] is None
            assert report["verdict"] == "AMELIORER_DISTANCE_RASTER_UNDER_RESOLVED"
        finally:
            mod._load_sole_module = original
    print("CIV1_PLAYER_DISTANCE_RASTER_ANALYZER_TEST_OK")


if __name__ == "__main__":
    main()
