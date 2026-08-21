#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import tempfile
from pathlib import Path

MODULE = Path(__file__).with_name("persist_secondary_height_evidence.py")
REPO_ROOT = Path(__file__).resolve().parents[3]
FACTORY_WORKFLOW = REPO_ROOT / ".github/workflows/grand-bruxelles-secondary-height-factory.yml"
LEGACY_WITNESS_WORKFLOW = REPO_ROOT / ".github/workflows/grand-bruxelles-citygen-anderlecht-secondary-height.yml"
spec = importlib.util.spec_from_file_location("persist_secondary_height_evidence", MODULE)
assert spec and spec.loader
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def write_json(path: Path, payload: dict) -> None:
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def main() -> int:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        secondary = root / "secondary.json"
        validation = root / "validation.json"
        out = root / "out"
        write_json(secondary,{"schema":"grand-bruxelles-ixelles-semantic-dsm-comparison-v1","cell":"bxl-e141500-n167500-s500","source_crs":"EPSG:31370","runtime_approved":False,"counts":{"height_candidate_source_count":7,"automatic_height_candidates":7,"manual_frontier_candidates":0,"semantic_joined_records":5,"strong_validation_candidates":4,"missing_secondary_records":2,"conflicts":0},"policy":{"runtime_approval":False},"records":[]})
        write_json(validation,{"format":"grand-bruxelles-citygen-secondary-height-validation-v1","cell_id":"bxl-e141500-n167500-s500","crs":"EPSG:31370","height_candidate_source_kind":"autonomous_measured_height_candidates","candidate_count":7,"validated_candidate_count":4,"blocked_candidate_count":3,"runtime_approved_count":0,"runtime_promotion_allowed":False,"secondary_validation_complete":False,"next_action":"resolve_blocked_secondary_height_candidates_without_guessing","candidates":[]})
        result=module.persist(secondary,validation,out)
        assert result["cell_id"]=="bxl-e141500-n167500-s500"
        assert result["height_candidate_source_kind"]=="autonomous_measured_height_candidates"
        assert result["validated_candidate_count"]==4
        assert result["blocked_candidate_count"]==3
        assert result["runtime_promotion_allowed"] is False
        persisted=json.loads((out/"secondary_height_validation.json").read_text(encoding="utf-8"))
        assert persisted["runtime_approved_count"]==0
        assert (out/"secondary_height_evidence.json").is_file()
        bad=json.loads(validation.read_text(encoding="utf-8")); bad["runtime_promotion_allowed"]=True; write_json(validation,bad)
        try:
            module.persist(secondary,validation,root/"bad-out")
        except ValueError as exc:
            assert "runtime promotion" in str(exc).lower()
        else:
            raise AssertionError("unsafe runtime promotion must fail closed")

        legacy_secondary = root / "legacy-secondary.json"
        legacy_validation = root / "legacy-validation.json"
        write_json(legacy_secondary,{"schema":"grand-bruxelles-ixelles-semantic-dsm-comparison-v1","cell":"bxl-e141500-n167500-s500","source_crs":"EPSG:31370","runtime_approved":False,"counts":{"manual_frontier_candidates":1},"policy":{"runtime_approval":False},"records":[]})
        write_json(legacy_validation,{"format":"grand-bruxelles-citygen-secondary-height-validation-v1","cell_id":"bxl-e141500-n167500-s500","crs":"EPSG:31370","candidate_count":1,"validated_candidate_count":0,"blocked_candidate_count":1,"runtime_approved_count":0,"runtime_promotion_allowed":False,"candidates":[]})
        legacy_result=module.persist(legacy_secondary,legacy_validation,root/"legacy-out")
        assert legacy_result["height_candidate_source_kind"]=="legacy_manual_frontier_review"

    workflow=FACTORY_WORKFLOW.read_text(encoding="utf-8")
    assert "workflow_run:" in workflow
    assert "Grand Bruxelles Autonomous CityGen" in workflow
    assert "contents: write" in workflow
    assert "citygen-autonomous-state" in workflow
    assert "--height-candidates" in workflow
    assert "runtime_promotion_allowed':False" in workflow or "runtime_promotion_allowed\":False" in workflow
    assert "automatic_production_mutation':False" in workflow or "automatic_production_mutation\":False" in workflow
    assert "git push --force-with-lease origin citygen-autonomous-state" in workflow

    legacy=LEGACY_WITNESS_WORKFLOW.read_text(encoding="utf-8")
    assert "contents: read" in legacy
    assert "Select current durable Anderlecht witness" in legacy
    assert "ANDERLECHT_CITYGEN_WITNESS_SELECTED" in legacy
    assert "ANDERLECHT_CITYGEN_WITNESS_SKIPPED" in legacy
    assert "--height-candidates" in legacy
    assert "ANDERLECHT_WITNESS_CANDIDATE_COUNT" in legacy
    assert "bxl-e141500-n167500-s500" not in legacy
    assert "candidate_count']==7" not in legacy
    assert "manual_frontier_candidates']==7" not in legacy
    assert "git push" not in legacy
    assert "Persist validated secondary evidence off main" not in legacy

    print("PERSIST_SECONDARY_HEIGHT_EVIDENCE_TEST_OK source=automatic legacy_compatible=true workflow_run=true off_main=true dynamic_anderlecht_witness=true")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
