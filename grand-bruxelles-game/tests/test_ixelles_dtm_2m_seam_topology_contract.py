import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONTRACT = ROOT / "data/terrain/ixelles/ixelles_dtm_2m_seam_topology_contract.json"
CANDIDATE = ROOT / "data/terrain/ixelles/ixelles_dtm_2m_candidate_evidence.json"


class IxellesDtm2mSeamTopologyContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.contract = json.loads(CONTRACT.read_text(encoding="utf-8"))
        cls.candidate = json.loads(CANDIDATE.read_text(encoding="utf-8"))

    def test_source_and_cell_scope_remain_exact(self):
        data = self.contract
        self.assertEqual(data["source_crs"], "EPSG:31370")
        self.assertFalse(data["runtime_approved"])
        self.assertFalse(data["promote_runtime"])
        self.assertEqual(data["source_evidence"]["specialist_lod_blob"], "aa9741161103137841f5e0b789474071773d82d7")
        self.assertEqual(len(data["cells"]), 5)
        self.assertEqual(
            {c["cell_id"] for c in data["cells"]},
            {c["cell_id"] for c in self.candidate["cells"]},
        )
        self.assertEqual(
            {tuple(c["bbox_epsg31370"]) for c in data["cells"]},
            {tuple(c["bbox_epsg31370"]) for c in self.candidate["cells"]},
        )

    def test_runtime_mesh_uses_inclusive_global_two_metre_lattice(self):
        p = self.contract["topology_policy"]
        self.assertEqual(p["global_lattice_origin_epsg31370"], [0, 0])
        self.assertEqual(p["cell_size_m"], 500)
        self.assertEqual(p["spacing_m"], 2)
        self.assertEqual(p["boundary_sampling"], "inclusive_both_ends")
        expected_axis = p["cell_size_m"] // p["spacing_m"] + 1
        self.assertEqual(p["vertices_per_axis"], expected_axis)
        self.assertEqual(p["vertices_per_cell_mesh"], expected_axis * expected_axis)
        self.assertEqual(p["quads_per_cell_mesh"], (expected_axis - 1) ** 2)
        self.assertEqual(p["triangles_per_cell_mesh"], 2 * (expected_axis - 1) ** 2)
        self.assertEqual(p["selection_benchmark_vertices_per_cell"], 62500)
        self.assertNotEqual(p["vertices_per_cell_mesh"], p["selection_benchmark_vertices_per_cell"])
        for cell in self.contract["cells"]:
            west, south, east, north = cell["bbox_epsg31370"]
            self.assertEqual(east - west, 500)
            self.assertEqual(north - south, 500)
            for coordinate in (west, south, east, north):
                self.assertEqual(coordinate % p["spacing_m"], 0)

    def test_shared_edges_are_exact_adjacencies_and_require_1255_comparisons(self):
        cells = {c["cell_id"]: c["bbox_epsg31370"] for c in self.contract["cells"]}
        p = self.contract["topology_policy"]
        edges = self.contract["shared_edges"]
        self.assertEqual(len(edges), 5)
        for edge in edges:
            a = cells[edge["a"]]
            b = cells[edge["b"]]
            start, end = edge["range"]
            self.assertEqual(end - start, 500)
            self.assertEqual((end - start) // p["spacing_m"] + 1, p["shared_edge_samples"])
            if edge["axis"] == "north_south":
                self.assertEqual(a[3], b[1])
                self.assertEqual(a[3], edge["fixed_coordinate"])
                self.assertEqual([a[0], a[2]], edge["range"])
                self.assertEqual([b[0], b[2]], edge["range"])
            elif edge["axis"] == "east_west":
                self.assertEqual(a[2], b[0])
                self.assertEqual(a[2], edge["fixed_coordinate"])
                self.assertEqual([a[1], a[3]], edge["range"])
                self.assertEqual([b[1], b[3]], edge["range"])
            else:
                self.fail(f"unsupported edge axis: {edge['axis']}")
        self.assertEqual(
            self.contract["aggregate"]["shared_edge_sample_comparisons_required"],
            len(edges) * p["shared_edge_samples"],
        )

    def test_height_seam_measurement_is_explicitly_still_blocked(self):
        p = self.contract["topology_policy"]
        self.assertEqual(p["required_measured_max_height_delta_m"], 0.0)
        self.assertEqual(p["height_delta_measurement_status"], "not_yet_measured_runtime_generation_required")
        self.assertEqual(self.contract["status"], "topology_contract_locked_height_seams_not_yet_measured")
        self.assertIn("1,255", self.contract["required_next_gate"])
        self.assertIn("nonzero height delta blocks runtime approval", self.contract["required_next_gate"])


if __name__ == "__main__":
    unittest.main()
