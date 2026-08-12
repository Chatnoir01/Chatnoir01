from __future__ import annotations

import json
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "data" / "urbis" / "bourse_frontage" / "manifest.json"
OSM = ROOT / "data" / "osm" / "vertical_slice_01.game.json"
EXPECTED_IDS = [
    "https://databrussels.be/id/building/1638842",
    "https://databrussels.be/id/building/1643317",
]
EXPECTED_PACKAGE_SHA = "cf8449d1a62b0e47aafe6d715ff6a2739f5c48f6d75995f7f418305a5d6cf3d2"
PHOTO_CAMERA_XZ = (20.0, -664.58)


def _bbox(points: list[list[float]]) -> tuple[float, float, float, float]:
    xs = [float(point[0]) for point in points]
    zs = [float(point[1]) for point in points]
    return min(xs), min(zs), max(xs), max(zs)


def _geometry_xz_bbox(data: dict) -> tuple[float, float, float, float]:
    points: list[list[float]] = []
    for face in data["faces"]:
        for triangle in face.get("triangles", []):
            for point in triangle:
                points.append([float(point[0]), float(point[2])])
    return _bbox(points)


def _intersects(a: tuple[float, float, float, float], b: tuple[float, float, float, float]) -> bool:
    return not (a[2] < b[0] or b[2] < a[0] or a[3] < b[1] or b[3] < a[1])


def _ground_vertices(data: dict) -> set[tuple[float, float]]:
    vertices: set[tuple[float, float]] = set()
    for face in data["faces"]:
        if face.get("type") != "GROUNDSURFACE":
            continue
        for triangle in face.get("triangles", []):
            for point in triangle:
                vertices.add((round(float(point[0]), 4), round(float(point[2]), 4)))
    return vertices


class BourseFrontageRuntimeCandidate(unittest.TestCase):
    def setUp(self) -> None:
        self.manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
        self.osm = json.loads(OSM.read_text(encoding="utf-8"))
        self.contexts: list[tuple[dict, dict]] = []
        for entry in self.manifest["contexts"]:
            relative = entry["geometry_path"].removeprefix("res://")
            data = json.loads((ROOT / relative).read_text(encoding="utf-8"))
            self.contexts.append((entry, data))

    def test_provenance_and_runtime_refusal_are_locked(self) -> None:
        self.assertEqual(self.manifest["schema"], "grand-bruxelles-bourse-frontage-runtime-v1")
        self.assertEqual(self.manifest["source"]["crs"], "EPSG:31370")
        self.assertEqual(self.manifest["source"]["license"], "CC0-1.0")
        self.assertEqual(self.manifest["source"]["package_sha256"], EXPECTED_PACKAGE_SHA)
        self.assertFalse(self.manifest["runtime_approved"])
        self.assertFalse(self.manifest["realism_complete"])
        self.assertEqual([entry["building_id"] for entry, _ in self.contexts], EXPECTED_IDS)
        self.assertEqual(sum(entry["expected_faces"] for entry, _ in self.contexts), 34)
        self.assertEqual(sum(entry["expected_triangles"] for entry, _ in self.contexts), 108)
        self.assertEqual(sum(entry["render_triangles"] for entry, _ in self.contexts), 90)
        for entry, data in self.contexts:
            self.assertEqual(data["schema"], "grand-bruxelles-urbis-context-mesh-v1")
            self.assertEqual(data["source"]["building_2d_id"], entry["building_id"])
            self.assertEqual(data["source"]["package_sha256"], EXPECTED_PACKAGE_SHA)
            self.assertEqual(data["source"]["license"], "CC0-1.0")
            self.assertFalse(data["runtime_approved"])
            self.assertEqual(data["evidence"]["face_count"], entry["expected_faces"])
            self.assertEqual(data["evidence"]["triangle_count"], entry["expected_triangles"])

    def test_pair_is_contiguous_and_on_photo_camera_axis(self) -> None:
        shared = _ground_vertices(self.contexts[0][1]) & _ground_vertices(self.contexts[1][1])
        self.assertGreaterEqual(len(shared), 3, shared)
        for _, data in self.contexts:
            xmin, zmin, xmax, zmax = _geometry_xz_bbox(data)
            self.assertGreater(xmin, PHOTO_CAMERA_XZ[0])
            self.assertLess(xmin - PHOTO_CAMERA_XZ[0], 50.0)
            self.assertLess(zmin, PHOTO_CAMERA_XZ[1] + 15.0)
            self.assertGreater(zmax, PHOTO_CAMERA_XZ[1] - 15.0)

    def test_compact_osm_slice_has_no_volume_to_replace(self) -> None:
        context_boxes = [_geometry_xz_bbox(data) for _, data in self.contexts]
        overlaps: list[int] = []
        for building in self.osm["buildings"]:
            footprint = building.get("footprint", [])
            if len(footprint) < 3:
                continue
            building_box = _bbox(footprint)
            if any(_intersects(building_box, context_box) for context_box in context_boxes):
                overlaps.append(int(building["osm_id"]))
        self.assertEqual(overlaps, [], f"explicit OSM replacement mapping required before render: {overlaps}")
        for entry, _ in self.contexts:
            self.assertEqual(entry["replaces_osm_ids"], [])


if __name__ == "__main__":
    unittest.main()
