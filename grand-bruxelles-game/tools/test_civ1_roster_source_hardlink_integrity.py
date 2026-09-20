#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import os
import tempfile
from pathlib import Path

import civ1_roster_source_readiness as readiness
from civ1_roster_source_hardlink_integrity import hardlink_violations


def blob_sha1(data: bytes) -> str:
    return hashlib.sha1(f"blob {len(data)}\0".encode("ascii") + data).hexdigest()


def write_fixture(root: Path, *, hardlink: bool) -> str:
    rel = "assets/characters/civilians/civ1/source/body.glb"
    source_dir = root / "grand-bruxelles-game/assets/characters/civilians/civ1/source"
    source_dir.mkdir(parents=True)
    payload = b"real-civ1-payload"
    target = source_dir / "body.glb"
    if hardlink:
        external = root / "external-body.glb"
        external.write_bytes(payload)
        os.link(external, target)
    else:
        target.write_bytes(payload)
    status = {
        "candidate_id": "CIV-1",
        "production_authorized": True,
        "activation_ready": True,
        "source_package_present": True,
        "blocker": None,
        "character_source": {"license_evidence": {"unresolved_components": []}},
        "source_paths": [rel],
        "source_manifest": {rel: {
            "upstream_path": "upstream/body.glb",
            "git_blob_sha1": blob_sha1(payload),
            "sha256": hashlib.sha256(payload).hexdigest(),
            "size_bytes": len(payload),
            "license_scope_verified": True,
            "license": "CC0-1.0"
        }}
    }
    status_path = root / "grand-bruxelles-game/assets/characters/civilians/civ1/source_status.json"
    status_path.write_text(json.dumps(status), encoding="utf-8")
    return rel


def main() -> int:
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        rel = write_fixture(root, hardlink=False)
        assert hardlink_violations(root) == [], "ordinary source payload must remain accepted"
        assert readiness.source_ready(root), "ordinary single-link payload must remain READY"
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        rel = write_fixture(root, hardlink=True)
        assert hardlink_violations(root) == [rel], "hardlinked source payload must fail the dedicated gate"
        assert not readiness.source_ready(root), "canonical readiness API must reject hardlinked source payload"
    print("CIV1_SOURCE_HARDLINK_INTEGRITY_REGRESSION_GREEN")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
