#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import struct
import tempfile
from pathlib import Path

from civ1_roster_registration_truth import validate_entry


def minimal_glb() -> bytes:
    json_chunk = b"{}  "
    total = 12 + 8 + len(json_chunk)
    return struct.pack("<4sII", b"glTF", 2, total) + struct.pack("<I4s", len(json_chunk), b"JSON") + json_chunk


def main() -> None:
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        rel = "grand-bruxelles-game/assets/characters/civilian_source_url_fixture.glb"
        asset = root / rel
        asset.parent.mkdir(parents=True)
        asset.write_bytes(minimal_glb())
        sha = hashlib.sha256(asset.read_bytes()).hexdigest()

        candidate = {
            "asset_path": rel,
            "role": "civilian",
            "sha256": sha,
            "source_url": "https://assets.example.org./civilian.glb",
            "license": "CC0-1.0",
        }
        result = validate_entry(candidate, root)
        assert "source_url_not_canonical" in result["blocking_reasons"], result
        assert result["roster_eligible"] is False, result

    print("CIV1_ROSTER_SOURCE_URL_CANONICALITY_GREEN")


if __name__ == "__main__":
    main()
