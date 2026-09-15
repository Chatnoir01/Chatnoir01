#!/usr/bin/env python3
from __future__ import annotations

import json
import tempfile
from pathlib import Path

from civ1_roster_source_readiness import source_ready


def main() -> None:
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        status = root / "grand-bruxelles-game/assets/characters/civilians/civ1/source_status.json"
        status.parent.mkdir(parents=True)

        source_path = "assets/characters/civilians/civ1/source/body.glb"
        source_file = root / "grand-bruxelles-game" / source_path
        source_file.parent.mkdir(parents=True)
        source_file.write_bytes(b"civ1-source-body")

        ready_status = {
            "candidate_id": "CIV-1",
            "production_authorized": True,
            "activation_ready": True,
            "source_package_present": True,
            "blocker": None,
            "character_source": {"license_evidence": {"unresolved_components": []}},
            "source_paths": [source_path],
            "source_manifest": {
                source_path: {
                    "license_scope_verified": True,
                    "git_blob_sha1": "3914b89458e542b73f0168b0bf80c8e356e78f9c",
                    "size_bytes": 16,
                }
            },
        }
        canonical = json.dumps(ready_status)
        status.write_text(canonical, encoding="utf-8")
        assert source_ready(root) is True, "control ready status must remain accepted"

        # RFC 8259 excludes NaN/Infinity, and finite-syntax overflow such as 1e309
        # decodes to +inf with Python's default float parser. Authorization records
        # must fail closed on both forms anywhere in the document.
        for token in ("NaN", "Infinity", "-Infinity", "1e309", "-1e309"):
            nonstandard = canonical[:-1] + f', "non_standard_numeric": {token}' + "}"
            status.write_text(nonstandard, encoding="utf-8")
            assert source_ready(root) is False, (
                f"CIV-1 readiness must reject non-finite decoded JSON number {token}"
            )

    print("CIV1_ROSTER_SOURCE_READINESS_NONSTANDARD_JSON_GREEN")


if __name__ == "__main__":
    main()
