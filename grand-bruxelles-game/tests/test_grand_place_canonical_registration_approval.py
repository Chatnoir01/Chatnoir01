#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import tempfile
from pathlib import Path

SCRIPT = Path(__file__).parents[1] / "tools/qa/review_grand_place_canonical_registration_approval.py"
spec = importlib.util.spec_from_file_location("approval", SCRIPT)
if spec is None or spec.loader is None:
    raise RuntimeError("grand-place canonical registration approval tool missing")
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


def write_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def fixture(root: Path) -> None:
    write_json(root / mod.CANDIDATE_REVIEW_PATH, {
        "schema": "grand-bruxelles-grand-place-canonical-manifest-candidate-review-v1",
        "status": "CANDIDATE_LOCKED_UNREGISTERED",
        "semantic_sha256": mod.CANDIDATE_REVIEW_SHA,
        "target": {
            "cell_id": mod.CELL_ID,
            "crs": mod.CRS,
            "bbox": mod.BBOX,
            "canonical_manifest_path": mod.CANONICAL_PATH.as_posix(),
            "canonical_manifest_present": False,
        },
        "candidate_manifest": {
            "sha256": mod.CANDIDATE_SHA,
            "format": "grand-bruxelles-cell-maturity-v1",
            "maturity_state": "data_ready",
            "all_maturity_gates_false": True,
        },
        "registered_cell_index": {
            "registered_cell_count": 1,
            "target_registered": False,
        },
        "authorization": {key: False for key in mod.CANDIDATE_RAILS},
    })
    write_json(root / mod.REGISTRATION_REVIEW_PATH, {
        "schema": "grand-bruxelles-grand-place-cell-registration-review-v1",
        "status": "READY_FOR_CANONICAL_MANIFEST_REVIEW",
        "semantic_sha256": mod.REGISTRATION_REVIEW_SHA,
        "target": {
            "cell_id": mod.CELL_ID,
            "crs": mod.CRS,
            "bbox": mod.BBOX,
            "canonical_manifest_present": False,
            "authoritative_source_manifest_present": True,
        },
        "authoritative_source_evidence": {
            "manifest_sha256": mod.SOURCE_MANIFEST_SHA,
            "source_digest": mod.SOURCE_DIGEST,
        },
        **{key: False for key in mod.REGISTRATION_RAILS},
    })
    write_json(root / mod.SOURCE_LOCK_PATH, {
        "schema": "grand-bruxelles-urbis-source-cell-lock-v2",
        "status": "LOCKED_EXACT_SOURCE_ONLY_PERSISTED",
        "source": {"authority": "Paradigm / Brussels-Capital Region", "license": "CC0-1.0"},
        "locked": {
            "manifest_source_digest": mod.SOURCE_DIGEST,
            "source_semantic_sha256": mod.SOURCE_SEMANTIC_SHA,
        },
        "authorization": {
            "source_acquisition": True,
            "source_registration": False,
            "canonical_registration": False,
            "road_to_cell_mapping": False,
            "runtime_mount": False,
            "rendered_geometry": False,
            "collision": False,
            "safe_spawn": False,
            "jouable_promotion": False,
        },
    })
    write_json(root / mod.REGISTERED_INDEX_PATH, {
        "schema": "grand-bruxelles-registered-cell-manifest-index-v1",
        "semantic_sha256": mod.REGISTERED_INDEX_SHA,
        "destination_readiness": "REGISTERED_CELL_INDEX_EVIDENCE_ONLY",
        "registered_cell_count": 1,
        "entries": [{"cell_id": "bxl-e149000-n169000-s500"}],
        **{key: False for key in mod.INDEX_RAILS},
    })


def expect_error(fn, text: str) -> None:
    try:
        fn()
    except RuntimeError as exc:
        assert text in str(exc), (text, exc)
    else:
        raise AssertionError(f"expected RuntimeError containing {text!r}")


def main() -> int:
    base = "78c169227fe70f2265a83c3ad30601b03bf9ee16"
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        fixture(root)
        result = mod.review(root, base)
        assert result["status"] == "APPROVED_EVIDENCE_ONLY_CANONICAL_REGISTRATION"
        assert result["authorization"]["canonical_manifest_write"] is True
        assert result["authorization"]["registered_index_mutation"] is True
        assert result["authorization"]["evidence_only_registration"] is True
        for key in mod.CLOSED_APPROVAL_RAILS:
            assert result["authorization"][key] is False, key
        assert not (root / mod.CANONICAL_PATH).exists()

    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        fixture(root)
        payload = json.loads((root / mod.CANDIDATE_REVIEW_PATH).read_text())
        payload["authorization"]["runtime_mount"] = True
        write_json(root / mod.CANDIDATE_REVIEW_PATH, payload)
        expect_error(lambda: mod.review(root, base), "candidate rail opened")

    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        fixture(root)
        payload = json.loads((root / mod.REGISTERED_INDEX_PATH).read_text())
        payload["runtime_mount_authorized"] = True
        write_json(root / mod.REGISTERED_INDEX_PATH, payload)
        expect_error(lambda: mod.review(root, base), "registered-cell index rail opened")

    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        fixture(root)
        payload = json.loads((root / mod.REGISTERED_INDEX_PATH).read_text())
        payload["entries"].append({"cell_id": mod.CELL_ID})
        payload["registered_cell_count"] = 2
        write_json(root / mod.REGISTERED_INDEX_PATH, payload)
        expect_error(lambda: mod.review(root, base), "target cell already registered")

    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        fixture(root)
        canonical = root / mod.CANONICAL_PATH
        canonical.parent.mkdir(parents=True, exist_ok=True)
        canonical.write_text("{}\n", encoding="utf-8")
        expect_error(lambda: mod.review(root, base), "canonical manifest already exists")

    print("GRAND_PLACE_CANONICAL_REGISTRATION_APPROVAL_TESTS_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
