#!/usr/bin/env python3
import hashlib, json, unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
CONTRACT=ROOT/'data/qa/corrected_frame_road_cell_crosswalk_candidate.contract.json'
IMPACT_CONTRACT=ROOT/'data/qa/osm_road_frame_correction_impact.contract.json'

class CorrectedFrameRoadCellCrosswalkCandidateContractTest(unittest.TestCase):
    def test_contract_locks_corridor_rows_and_closed_rails(self):
        d=json.loads(CONTRACT.read_text(encoding='utf-8'))
        self.assertEqual(d['schema'],'grand-bruxelles-corrected-frame-road-cell-crosswalk-candidate-contract-v1')
        self.assertEqual(d['status'],'CANDIDATE_EVIDENCE_ONLY')
        self.assertEqual(d['source']['road_source_sha256'],'899bc73ee0eea3623d7cc45455a542c1704039ef0239c13c33b3c74b4a241398')
        self.assertEqual(d['source']['impact_stable_semantic_sha256'],'2941ea86fd0e2ad524f6f788349aa9745e16809c3343a3fa063eb4b23494ac62')
        self.assertEqual(d['expected_accounting']['candidate_unique_mapped_road_count'],96)
        self.assertEqual(d['expected_accounting']['candidate_multicell_road_count'],2)
        self.assertEqual(d['expected_accounting']['candidate_no_registered_overlap_count'],42)
        reps=d['corridor_representatives']
        self.assertEqual(reps['midi_fonsny'],{'road_osm_id':408211693,'cell_id':'bxl-e147500-n169500-s500'})
        self.assertEqual(reps['anneessens_lemonnier'],{'road_osm_id':359177328,'cell_id':'bxl-e148000-n170000-s500'})
        self.assertEqual(reps['bourse_orts'],{'road_osm_id':411724192,'cell_id':'bxl-e148500-n170500-s500'})
        self.assertEqual(reps['grand_place_amigo'],{'road_osm_id':13842686,'cell_id':'bxl-e148500-n170500-s500'})
        self.assertEqual(d['multicell_holds'],[
            {'road_osm_id':256158619,'hit_cells':['bxl-e147500-n169500-s500','bxl-e147500-n170000-s500']},
            {'road_osm_id':397461693,'hit_cells':['bxl-e147500-n170000-s500','bxl-e148000-n170000-s500']},
        ])
        self.assertTrue(d['promotion_policy']['unique_mapping_only'])
        self.assertFalse(d['promotion_policy']['multicell_mapping_authorized'])
        self.assertFalse(d['promotion_policy']['replace_current_crosswalk_authorized'])
        self.assertTrue(all(v is False for v in d['authorization'].values()))
        basis=dict(d); basis.pop('semantic_sha256',None); basis.pop('production_base_sha',None)
        got=hashlib.sha256(json.dumps(basis,sort_keys=True,separators=(',',':'),ensure_ascii=False).encode()).hexdigest()
        self.assertEqual(got,d['semantic_sha256'])
        self.assertEqual(got,'7d8a943297a16cc855e67128b979f3e538193706087df419c9709b1751b53dc1')

    def test_locked_impact_keeps_historical_base_separate_from_candidate_base(self):
        candidate=json.loads(CONTRACT.read_text(encoding='utf-8'))
        impact=json.loads(IMPACT_CONTRACT.read_text(encoding='utf-8'))
        self.assertEqual(impact['status'],'LOCKED_IMPACT_MEASUREMENT_EVIDENCE_ONLY')
        self.assertEqual(impact['production_base_sha'],'2785106ee36ca1752ff033a754d2b0ef48a93a1b')
        self.assertNotEqual(candidate['production_base_sha'],impact['production_base_sha'])
        self.assertEqual(impact['semantic_identity_policy']['exclude_continuity_fields'],['production_base_sha'])
        self.assertEqual(
            impact['locked_evidence']['stable_semantic_sha256'],
            candidate['source']['impact_stable_semantic_sha256'],
        )
        self.assertEqual(impact['locked_evidence']['accounting'],candidate['expected_accounting'] | {
            'current_mapped_road_count':56,
            'retained_mapping_count':0,
            'changed_mapping_count':45,
            'newly_mappable_count':51,
            'no_longer_mappable_count':11,
        })

if __name__=='__main__': unittest.main()
