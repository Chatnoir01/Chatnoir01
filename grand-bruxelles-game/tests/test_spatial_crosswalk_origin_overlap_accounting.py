from __future__ import annotations

import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / "data/source_plans/brussels_spatial_crosswalk_origin_evidence.lock.json"
ROAD_SOURCE = ROOT / "data/osm/vertical_slice_01.game.json"
RUNTIME_INDEX = ROOT / "data/runtime/road_destination_runtime_index.json"
REGISTERED_CELL_INDEX = ROOT / "data/provenance/brussels_registered_cell_manifest_index.json"


def _segment_intersects_rect(
    p0: tuple[float, float],
    p1: tuple[float, float],
    rect: tuple[float, float, float, float],
) -> bool:
    x0, y0 = p0
    x1, y1 = p1
    xmin, ymin, xmax, ymax = rect
    dx = x1 - x0
    dy = y1 - y0
    p = (-dx, dx, -dy, dy)
    q = (x0 - xmin, xmax - x0, y0 - ymin, ymax - y0)
    u0 = 0.0
    u1 = 1.0
    for pi, qi in zip(p, q, strict=True):
        if pi == 0.0:
            if qi < 0.0:
                return False
            continue
        t = qi / pi
        if pi < 0.0:
            if t > u1:
                return False
            u0 = max(u0, t)
        else:
            if t < u0:
                return False
            u1 = min(u1, t)
    return True


def _road_intersects_any_cell(
    points: list[list[float]],
    origin_easting_m: float,
    origin_northing_m: float,
    cells: list[tuple[float, float, float, float]],
) -> bool:
    projected = [
        (origin_easting_m + float(x), origin_northing_m - float(z))
        for x, z in points
    ]
    for point in projected:
        if any(xmin <= point[0] <= xmax and ymin <= point[1] <= ymax for xmin, ymin, xmax, ymax in cells):
            return True
    return any(
        _segment_intersects_rect(p0, p1, cell)
        for p0, p1 in zip(projected, projected[1:])
        for cell in cells
    )


class OriginOverlapAccountingTests(unittest.TestCase):
    def test_locked_overlap_count_is_recomputed_from_repository_geometry(self) -> None:
        evidence = json.loads(EVIDENCE.read_text(encoding="utf-8"))
        source = json.loads(ROAD_SOURCE.read_text(encoding="utf-8"))
        runtime = json.loads(RUNTIME_INDEX.read_text(encoding="utf-8"))
        registered = json.loads(REGISTERED_CELL_INDEX.read_text(encoding="utf-8"))

        measured = evidence["measured_contract"]
        frame = measured["frame"]
        self.assertEqual(frame["crs"], "EPSG:31370")
        self.assertEqual(frame["formula"], "E=origin_easting_m+x;N=origin_northing_m-z")
        self.assertEqual(measured["cell_crs"], "EPSG:31370")

        documents = runtime["documents"]
        self.assertEqual(len(documents), 1)
        runtime_ids = documents[0]["road_ids"]
        self.assertEqual(len(runtime_ids), measured["road_count"])
        self.assertEqual(runtime_ids, sorted(set(runtime_ids)))

        cells = [tuple(entry["bbox"]) for entry in registered["entries"]]
        self.assertEqual(len(cells), measured["registered_cell_count"])
        self.assertTrue(all(entry["crs"] == "EPSG:31370" for entry in registered["entries"]))

        roads_by_id = {road["osm_id"]: road for road in source["roads"]}
        self.assertTrue(set(runtime_ids).issubset(roads_by_id))
        overlapping_ids = [
            road_id
            for road_id in runtime_ids
            if _road_intersects_any_cell(
                roads_by_id[road_id]["points"],
                frame["origin_easting_m"],
                frame["origin_northing_m"],
                cells,
            )
        ]

        self.assertEqual(len(overlapping_ids), measured["overlapping_road_count"])
        self.assertEqual(len(overlapping_ids), 64)
        self.assertEqual(overlapping_ids, sorted(overlapping_ids))


if __name__ == "__main__":
    unittest.main()
