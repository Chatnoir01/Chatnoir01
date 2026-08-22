#!/usr/bin/env python3
import json
import unittest
from pathlib import Path

from hold_resolver import classify_blocker
from universal_zone_profile import analyse_zone
from one_click_orchestrator import build_plan


class HoldResolverTests(unittest.TestCase):
    def test_height_conflict_stays_manual(self):
        row = classify_blocker('secondary height conflict for owner 1746678')
        self.assertEqual(row['code'], 'HEIGHT_CONFLICT')
        self.assertFalse(row['auto_resolvable'])

    def test_stale_source_is_actionable_not_authorized(self):
        row = classify_blocker('source revision is stale')
        self.assertEqual(row['code'], 'STALE_SOURCE')
        self.assertTrue(row['auto_resolvable'])
        self.assertFalse(row['runtime_authorized'])
        self.assertFalse(row['jouable_authorized'])

    def test_unknown_fails_closed(self):
        row = classify_blocker('mysterious future blocker')
        self.assertEqual(row['code'], 'UNKNOWN_HOLD')
        self.assertFalse(row['auto_resolvable'])


class ZoneProfileTests(unittest.TestCase):
    def test_jette_like_profile_is_data_ready_only(self):
        profile = {
            'source_root': 'data/urbis/jette',
            'validator_script': 'tools/validate.py',
            'runtime_script': 'game/jette.gd',
            'materialized_slugs': ['buildings', 'street_surfaces', 'street_axes'],
            'osm_environment': {'cache': 'raw.json', 'runtime': 'game.json'},
        }
        result = analyse_zone('jette', profile, {
            'coverage_complete': True,
            'source_contract_ready': True,
            'runtime_gates_passed': False,
        })
        self.assertEqual(result['lifecycle'], 'DATA_READY')
        self.assertFalse(result['jouable_authorized'])

    def test_partial_zone_can_progress_without_false_completion(self):
        profile = {
            'source_root': 'data/urbis/anneessens',
            'materialized_slugs': ['buildings', 'street_surfaces'],
        }
        result = analyse_zone('anneessens', profile, {
            'coverage_complete': False,
            'source_contract_ready': True,
        })
        self.assertEqual(result['lifecycle'], 'PARTIAL_DATA_READY')
        self.assertFalse(result['runtime_authorized'])

    def test_midi_legacy_runtime_wiring_blocks_runtime(self):
        profile = {
            'source_root': 'data/urbis/midi',
            'validator_script': 'tools/validate.py',
            'runtime_script': 'game/urbis_midi_builder.gd',
            'materialized_slugs': ['buildings', 'street_surfaces', 'street_axes'],
            'osm_environment': {'cache': 'raw.json', 'runtime': 'game.json'},
        }
        result = analyse_zone('midi', profile, {
            'coverage_complete': True,
            'source_contract_ready': True,
            'runtime_consumes_city_machine_outputs': False,
        })
        self.assertEqual(result['lifecycle'], 'DATA_READY')
        self.assertIn('RUNTIME_WIRING', [b['code'] for b in result['blockers']])
        self.assertFalse(result['runtime_authorized'])


class OrchestratorTests(unittest.TestCase):
    def test_plan_is_deterministic_and_never_promotes(self):
        registry = {
            'zone_profiles': {
                'jette': {'source_root': 'data/jette', 'materialized_slugs': ['buildings', 'street_surfaces']},
            }
        }
        catalog = {'zones': [
            {'id': 'bourse', 'quality': 'LABO'},
            {'id': 'jette', 'quality': 'LABO'},
            {'id': 'anneessens', 'quality': 'LABO'},
        ]}
        facts = {
            'jette': {'coverage_complete': True, 'source_contract_ready': True},
            'anneessens': {'coverage_complete': False, 'source_contract_ready': True},
        }
        first = build_plan(registry, catalog, facts)
        second = build_plan(registry, catalog, facts)
        self.assertEqual(first, second)
        self.assertEqual([z['zone_id'] for z in first['zones']], ['anneessens', 'bourse', 'jette'])
        self.assertFalse(first['automatic_jouable_promotion'])
        self.assertTrue(all(not z['jouable_authorized'] for z in first['zones']))

    def test_live_registry_and_catalog_are_safe(self):
        game_root = Path(__file__).resolve().parents[2]
        registry = json.loads((game_root / 'tools/city_machine/registry.json').read_text())
        catalog = json.loads((game_root / 'data/qa/playable_zone_catalog.json').read_text())
        plan = build_plan(registry, catalog)
        catalog_ids = {row['id'] for row in catalog['zones']}
        self.assertTrue(catalog_ids.issubset({row['zone_id'] for row in plan['zones']}))
        self.assertFalse(plan['automatic_main_mutation'])
        self.assertFalse(plan['automatic_jouable_promotion'])
        self.assertTrue(all(not row['runtime_authorized'] for row in plan['zones']))
        self.assertTrue(all(not row['jouable_authorized'] for row in plan['zones']))


if __name__ == '__main__':
    unittest.main()
