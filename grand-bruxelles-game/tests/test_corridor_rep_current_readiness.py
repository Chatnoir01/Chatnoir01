import copy
import unittest
from pathlib import Path

from tools.qa.measure_corridor_rep_current_readiness import indexed_readiness, load, measure, normalized_expected, validate_measurement_base


class CorridorRepresentativeReadinessTests(unittest.TestCase):
    def setUp(self):
        root=Path(__file__).resolve().parents[1]
        self.contract=load(root/'data/qa/corrected_frame_corridor_representative_current_readiness.contract.json')
        self.reps=load(root/'data/qa/corrected_frame_corridor_representatives.contract.json')
        self.readiness=load(root/'data/provenance/brussels_road_destination_readiness_catalog.json')

    def test_locked_selection_and_historical_expectation_are_preserved(self):
        ids=[int(x['expected_road_osm_id']) for x in self.reps['selection']['target_cells']]
        self.assertEqual(ids,[8176386,150205016,13767417,8512036])
        expected=normalized_expected(self.contract['expected'])
        self.assertEqual(expected['expected_absent_road_osm_ids'],[8176386,150205016])
        self.assertEqual(expected['expected_wrong_cell_road_osm_ids'],[8512036,13767417])
        self.assertEqual(expected['present_in_target_cell_count'],0)
        self.assertEqual(expected['runtime_probe_eligible_count'],0)

    def test_corrected_pair_current_catalog_has_all_representatives_in_target_cells(self):
        current=indexed_readiness(self.readiness,self.contract['source']['road_source_sha256'])
        targets={int(x['expected_road_osm_id']):x['cell_id'] for x in self.reps['selection']['target_cells']}
        for rid,cell_id in targets.items():
            self.assertIn(rid,current)
            self.assertEqual(current[rid]['cell_id'],cell_id)
            self.assertEqual(current[rid]['readiness'],'REGISTERED_NOT_RENDERED')
        out=measure(self.contract,self.reps,self.readiness,'c0b75e84d7498c616996216b3f976d8195a6dadd','corrected-pair-current')
        self.assertEqual(out['status'],'REGISTERED_TARGET_CELLS_HOLD_RENDER_COLLISION')
        self.assertEqual(out['accounting']['present_in_target_cell_count'],4)
        self.assertEqual(out['accounting']['runtime_probe_eligible_count'],0)
        self.assertTrue(all(v is False for v in out['authorization'].values()))

    def test_historical_mode_still_fails_closed_on_current_corrected_pair(self):
        with self.assertRaises(AssertionError):
            measure(self.contract,self.reps,self.readiness,self.contract['production_base_sha'],'historical')

    def test_expected_id_sets_are_normalized_for_deterministic_compare(self):
        expected=dict(self.contract['expected'])
        expected['expected_wrong_cell_road_osm_ids']=[13767417,8512036]
        expected['expected_absent_road_osm_ids']=[150205016,8176386]
        normalized=normalized_expected(expected)
        self.assertEqual(normalized['expected_wrong_cell_road_osm_ids'],[8512036,13767417])
        self.assertEqual(normalized['expected_absent_road_osm_ids'],[8176386,150205016])

    def test_readiness_catalog_rejects_duplicate_road_ids(self):
        duplicate=copy.deepcopy(self.readiness)
        duplicate['destinations'].append(copy.deepcopy(duplicate['destinations'][0]))
        duplicate['destination_count']=len(duplicate['destinations'])
        with self.assertRaisesRegex(AssertionError,'duplicate road_osm_id'):
            indexed_readiness(duplicate,self.contract['source']['road_source_sha256'])

    def test_readiness_catalog_is_bound_to_locked_source(self):
        drift=copy.deepcopy(self.readiness)
        drift['destinations'][0]['source_sha256']='0'*64
        with self.assertRaises(AssertionError):
            indexed_readiness(drift,self.contract['source']['road_source_sha256'])

    def test_runtime_flags_must_remain_closed(self):
        drift=copy.deepcopy(self.readiness)
        drift['destinations'][0]['render_authorized']=True
        with self.assertRaises(AssertionError):
            indexed_readiness(drift,self.contract['source']['road_source_sha256'])

    def test_all_authorizations_remain_closed(self):
        self.assertTrue(self.contract['authorization'])
        self.assertTrue(all(v is False for v in self.contract['authorization'].values()))
        self.assertFalse(self.contract['policy']['runtime_probe_authorized'])
        self.assertFalse(self.contract['policy']['replace_readiness_catalog_authorized'])
        self.assertFalse(self.contract['policy']['replace_crosswalk_authorized'])
        self.assertTrue(self.contract['policy']['historical_locked_evidence_must_replay_from_evidence_base'])
        self.assertTrue(self.contract['policy']['current_corrected_pair_measurement_is_separate_from_historical_lock'])

    def test_locked_forensic_bytes_are_bound_to_historical_base(self):
        self.assertEqual(self.contract['status'],'LOCKED_EVIDENCE_ONLY')
        locked=self.contract['locked_evidence']
        self.assertEqual(len(locked['production_base_sha']),40)
        self.assertEqual(len(locked['measurement_sha256']),64)
        self.assertEqual(len(locked['semantic_sha256']),64)
        self.assertTrue(self.contract['policy']['locked_measurement_sha_is_forensic_to_locked_base'])
        self.assertTrue(self.contract['policy']['semantic_lock_survives_clean_live_main_rebuild'])
        self.assertEqual(locked['semantic_sha256'],'f15a6dc04cff1103d1e5024e9c2d4fbc7655ec4778e0bcb80420bc1501e93eda')

    def test_historical_locked_base_can_measure_clean_live_main(self):
        live_main='c0b75e84d7498c616996216b3f976d8195a6dadd'
        evidence=validate_measurement_base(self.contract,live_main)
        self.assertEqual(evidence,self.contract['production_base_sha'])
        self.assertNotEqual(live_main,evidence)

    def test_live_main_replay_rejects_without_semantic_policy(self):
        drift=copy.deepcopy(self.contract)
        drift['policy']['semantic_lock_survives_clean_live_main_rebuild']=False
        with self.assertRaises(AssertionError):
            validate_measurement_base(drift,'c0b75e84d7498c616996216b3f976d8195a6dadd')

    def test_live_main_replay_rejects_locked_base_drift(self):
        drift=copy.deepcopy(self.contract)
        drift['locked_evidence']['production_base_sha']='0'*40
        with self.assertRaises(AssertionError):
            validate_measurement_base(drift,'c0b75e84d7498c616996216b3f976d8195a6dadd')

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
