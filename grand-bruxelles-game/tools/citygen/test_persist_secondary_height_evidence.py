#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import tempfile
from pathlib import Path

MODULE = Path(__file__).with_name("persist_secondary_height_evidence.py")
REPO_ROOT = Path(__file__).resolve().parents[3]
SECONDARY_WORKFLOW = REPO_ROOT / ".github/workflows/grand-bruxelles-citygen-anderlecht-secondary-height.yml"
PERSISTENCE_WORKFLOW = REPO_ROOT / ".github/workflows/grand-bruxelles-citygen-secondary-persistence.yml"
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
        write_json(secondary,{"schema":"grand-bruxelles-ixelles-semantic-dsm-comparison-v1","cell":"bxl-e141500-n167500-s500","source_crs":"EPSG:31370","runtime_approved":False,"counts":{"manual_frontier_candidates":7,"semantic_joined_records":5,"strong_validation_candidates":4,"missing_secondary_records":2,"conflicts":0},"policy":{"runtime_approval":False},"records":[]})
        write_json(validation,{"format":"grand-bruxelles-citygen-secondary-height-validation-v1","cell_id":"bxl-e141500-n167500-s500","crs":"EPSG:31370","candidate_count":7,"validated_candidate_count":4,"blocked_candidate_count":3,"runtime_approved_count":0,"runtime_promotion_allowed":False,"secondary_validation_complete":False,"next_action":"resolve_blocked_secondary_height_candidates_without_guessing","candidates":[]})
        result=module.persist(secondary,validation,out)
        assert result["cell_id"]=="bxl-e141500-n167500-s500"
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

    secondary_workflow=SECONDARY_WORKFLOW.read_text(encoding="utf-8")
    persistence_workflow=PERSISTENCE_WORKFLOW.read_text(encoding="utf-8")
    assert "contents: write" in secondary_workflow
    assert "Persist validated secondary evidence off main" in secondary_workflow
    assert "persist_secondary_height_evidence.py" in secondary_workflow
    assert "git switch -C citygen-autonomous-state" in secondary_workflow
    assert "github.event_name != 'pull_request'" in secondary_workflow
    assert "workflow_run:" not in persistence_workflow
    print("PERSIST_SECONDARY_HEIGHT_EVIDENCE_TEST_OK")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
