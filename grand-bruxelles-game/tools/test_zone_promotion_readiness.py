#!/usr/bin/env python3
from __future__ import annotations

import copy
import json
import tempfile
import unittest
from pathlib import Path

from validate_zone_promotion_readiness import PromotionValidationError, validate_repository


REQUIRED_STAGES = [
    "source_verified",
    "runtime_validated",
    "player_ground_collision",
    "hero_anchor_visible",
    "full_frame_player_proof",
    "performance_exports_green",
    "human_visual_verdict",
]


class ZonePromotionReadinessTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.repo = Path(self.tmp.name)
        self.contract_path = self.repo / "grand-bruxelles-game/data/qa/zone_promotion_contract.json"
        self.catalog_path = self.repo / "grand-bruxelles-game/data/qa/playable_zone_catalog.json"
        self.proof_dir = self.repo / "grand-bruxelles-game/data/qa/zone_promotion"
        self.evidence_path = self.repo / "evidence/ok.txt"
        self.contract_path.parent.mkdir(parents=True)
        self.proof_dir.mkdir(parents=True)
        self.evidence_path.parent.mkdir(parents=True)
        self.evidence_path.write_text("proof", encoding="utf-8")
        self.contract = {
            "schema": "grand-bruxelles-zone-promotion-contract-v1",
            "catalog_path": "grand-bruxelles-game/data/qa/playable_zone_catalog.json",
            "proof_directory": "grand-bruxelles-game/data/qa/zone_promotion",
            "proof_schema": "grand-bruxelles-zone-promotion-proof-v1",
            "allowed_catalog_qualities": ["JOUABLE", "LABO", "LABO_BRUT"],
            "approved_jouable_decisions": ["KEEP_JOUABLE", "APPROVE_JOUABLE"],
            "required_stages": REQUIRED_STAGES,
            "policy": {
                "human_only_promotion": True,
                "jouable_requires_proof": True,
                "jouable_requires_human_pass": True,
                "city_machine_may_promote": False,
                "labo_data_ready_is_not_jouable": True,
                "labo_may_hold_approved_jouable_decision": False,
                "missing_or_broken_evidence_fails_closed": True,
                "proof_does_not_mean_realism_complete": True,
            },
        }
        self.catalog = {
            "schema": "grand-bruxelles-playable-zone-catalog-v2",
            "zones": [
                {"id": "midi", "quality": "JOUABLE"},
                {"id": "bourse", "quality": "LABO"},
            ],
        }
        base_stage = {"status": "PASS", "evidence": ["evidence/ok.txt"]}
        self.midi_proof = {
            "schema": "grand-bruxelles-zone-promotion-proof-v1",
            "zone_id": "midi",
            "catalog_quality": "JOUABLE",
            "decision": "KEEP_JOUABLE",
            "realism_complete": False,
            "stages": {stage: copy.deepcopy(base_stage) for stage in REQUIRED_STAGES},
        }
        self.midi_proof["stages"]["human_visual_verdict"].update(
            {"verdict": "PASS", "scope": "fixture human full-frame review", "realism_complete": False}
        )
        self._write_fixture()

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def _write_json(self, path: Path, payload: dict) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")

    def _write_fixture(self) -> None:
        self._write_json(self.contract_path, self.contract)
        self._write_json(self.catalog_path, self.catalog)
        self._write_json(self.proof_dir / "midi.json", self.midi_proof)

    def assert_validation_fails(self, contains: str) -> None:
        with self.assertRaises(PromotionValidationError) as ctx:
            validate_repository(self.repo, self.contract_path)
        self.assertIn(contains, str(ctx.exception))

    def test_valid_existing_jouable_and_labo_pass(self) -> None:
        result = validate_repository(self.repo, self.contract_path)
        self.assertEqual(result["jouable"], ["midi"])
        self.assertEqual(result["labo"], ["bourse"])
        self.assertEqual(result["approved"], ["midi"])

    def test_jouable_without_proof_fails(self) -> None:
        (self.proof_dir / "midi.json").unlink()
        self.assert_validation_fails("JOUABLE zone missing proof: midi")

    def test_promoting_labo_without_proof_fails(self) -> None:
        self.catalog["zones"][1]["quality"] = "JOUABLE"
        self._write_json(self.catalog_path, self.catalog)
        self.assert_validation_fails("JOUABLE zone missing proof: bourse")

    def test_broken_evidence_path_fails(self) -> None:
        self.midi_proof["stages"]["source_verified"]["evidence"] = ["evidence/missing.txt"]
        self._write_json(self.proof_dir / "midi.json", self.midi_proof)
        self.assert_validation_fails("broken evidence path")

    def test_labo_cannot_carry_approved_jouable_decision(self) -> None:
        bourse = copy.deepcopy(self.midi_proof)
        bourse.update({"zone_id": "bourse", "catalog_quality": "LABO", "decision": "APPROVE_JOUABLE"})
        self._write_json(self.proof_dir / "bourse.json", bourse)
        self.assert_validation_fails("LABO zone carries approved JOUABLE decision: bourse")

    def test_human_visual_pass_is_mandatory(self) -> None:
        self.midi_proof["stages"]["human_visual_verdict"]["verdict"] = "FAIL"
        self._write_json(self.proof_dir / "midi.json", self.midi_proof)
        self.assert_validation_fails("human visual PASS missing: midi")

    def test_unknown_zone_proof_fails(self) -> None:
        unknown = copy.deepcopy(self.midi_proof)
        unknown["zone_id"] = "invented_zone"
        self._write_json(self.proof_dir / "invented_zone.json", unknown)
        self.assert_validation_fails("proof targets unknown zone: invented_zone")

    def test_city_machine_promotion_permission_fails(self) -> None:
        self.contract["policy"]["city_machine_may_promote"] = True
        self._write_json(self.contract_path, self.contract)
        self.assert_validation_fails("City Machine must not be allowed to promote zones")


if __name__ == "__main__":
    unittest.main(verbosity=2)
