from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RECEIPT = ROOT / "data/source_plans/brussels_spatial_crosswalk_origin_artifact_receipt.lock.json"
VALIDATOR = ROOT / "tools/city_machine/validate_spatial_crosswalk_origin_artifact_receipt.py"


def _run(mutator, tmp_path: Path) -> subprocess.CompletedProcess[str]:
    payload = json.loads(RECEIPT.read_text(encoding="utf-8"))
    mutator(payload)
    candidate = tmp_path / "receipt.json"
    candidate.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    return subprocess.run(
        [sys.executable, str(VALIDATOR), "--receipt", str(candidate)],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )


def test_rejects_workflow_head_repin(tmp_path: Path) -> None:
    result = _run(lambda p: p.__setitem__("workflow_run_head_sha", "0" * 40), tmp_path)
    assert result.returncode != 0, result.stdout + result.stderr


def test_rejects_archive_validation_rewrite(tmp_path: Path) -> None:
    def mutate(payload):
        payload["archive_download_validation"] = {
            "attempted": True,
            "result": "VERIFIED",
            "http_status": 200,
            "error_class": None,
            "archive_sha256": "0" * 64,
        }
    result = _run(mutate, tmp_path)
    assert result.returncode != 0, result.stdout + result.stderr


def test_rejects_shadow_authorization_key(tmp_path: Path) -> None:
    result = _run(lambda p: p["authorization"].__setitem__("shadow_runtime_authorized", True), tmp_path)
    assert result.returncode != 0, result.stdout + result.stderr


def test_rejects_scope_note_rewrite(tmp_path: Path) -> None:
    result = _run(lambda p: p.__setitem__("scope_note", "Artifact is runtime-authorized and verified."), tmp_path)
    assert result.returncode != 0, result.stdout + result.stderr
