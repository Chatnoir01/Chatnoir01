#!/usr/bin/env python3
from __future__ import annotations

import tempfile
from pathlib import Path

from civ1_roster_source_readiness import _git_blob_sha1, _source_manifest_integrity


def main() -> None:
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        source_path = "assets/characters/civilians/civ1/source/body.glb"
        source_file = root / "grand-bruxelles-game" / source_path
        source_file.parent.mkdir(parents=True)
        source_file.write_bytes(b"")
        status = {
            "source_paths": [source_path],
            "source_manifest": {
                source_path: {
                    "upstream_path": "godot_project/body.glb",
                    "license_scope_verified": True,
                    "license": "CC0-1.0",
                    "git_blob_sha1": _git_blob_sha1(b""),
                    "size_bytes": 0,
                }
            },
        }
        assert _source_manifest_integrity(status, root) is False, "empty payload must never qualify as a materialized CIV-1 source asset"

        payload = b"civ1-source-body"
        source_file.write_bytes(payload)
        status["source_manifest"][source_path]["git_blob_sha1"] = _git_blob_sha1(payload)
        status["source_manifest"][source_path]["size_bytes"] = len(payload)
        assert _source_manifest_integrity(status, root) is True, "non-empty hash/size-bound source control must remain accepted"

    print("CIV1_NONEMPTY_SOURCE_PAYLOAD_REGRESSION_GREEN")


if __name__ == "__main__":
    main()
