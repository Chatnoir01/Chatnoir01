import unittest
from pathlib import Path

from tools.qa.measure_corridor_rep_current_readiness import load, normalized_expected


class CorridorRepresentativeReadinessTests(unittest.TestCase):
    def setUp(self):
        root=Path(__file__).resolve().parents[1]
        self.contract=load(root/'data/qa/corrected_frame_corridor_representative_current_readiness.contract.json')
        self.reps=load(root/'data/qa/corrected_frame_corridor_representatives.contract.json')
        self.readiness=load(root/'data/provenance/brussels_road_destination_readiness_catalog.json')

    def test_locked_selection_and_expected_gap(self):
        ids=[int(x['expected_road_osm_id']) for x in self.reps['selection']['target_cells']]
        self.assertEqual(ids,[8176386,150205016,13767417,8512036])
        current={int(x['road_osm_id']):x for x in self.readiness['destinations']}
        self.assertNotIn(8176386,current)
        self.assertNotIn(150205016,current)
        self.assertEqual(current[13767417]['cell_id'],'bxl-e147500-n169500-s500')
        self.assertEqual(current[8512036]['cell_id'],'bxl-e147500-n170000-s500')
        targets={int(x['expected_road_osm_id']):x['cell_id'] for x in self.reps['selection']['target_cells']}
        self.assertNotEqual(current[13767417]['cell_id'],targets[13767417])
        self.assertNotEqual(current[8512036]['cell_id'],targets[8512036])
        self.assertEqual(self.contract['expected']['runtime_probe_eligible_count'],0)

    def test_expected_id_sets_are_normalized_for_deterministic_compare(self):
        expected=dict(self.contract['expected'])
        expected['expected_wrong_cell_road_osm_ids']=[13767417,8512036]
        expected['expected_absent_road_osm_ids']=[150205016,8176386]
        normalized=normalized_expected(expected)
        self.assertEqual(normalized['expected_wrong_cell_road_osm_ids'],[8512036,13767417])
        self.assertEqual(normalized['expected_absent_road_osm_ids'],[8176386,150205016])

    def test_all_authorizations_remain_closed(self):
        self.assertTrue(self.contract['authorization'])
        self.assertTrue(all(v is False for v in self.contract['authorization'].values()))
        self.assertFalse(self.contract['policy']['runtime_probe_authorized'])
        self.assertFalse(self.contract['policy']['replace_readiness_catalog_authorized'])
        self.assertFalse(self.contract['policy']['replace_crosswalk_authorized'])

    def test_current_catalog_is_registered_not_rendered(self):
        self.assertEqual(self.readiness['destination_count'],len(self.readiness['destinations']))
        for row in self.readiness['destinations']:
            self.assertEqual(row['readiness'],'REGISTERED_NOT_RENDERED')
            self.assertFalse(row['render_authorized'])
            self.assertFalse(row['collision_authorized'])
            self.assertFalse(row['runtime_mount_authorized'])
            self.assertFalse(row['safe_spawn_authorized'])
            self.assertFalse(row['jouable_authorized'])


if __name__=='__main__':
    unittest.main()
