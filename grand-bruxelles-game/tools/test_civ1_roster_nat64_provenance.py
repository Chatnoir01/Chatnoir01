#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import struct
import tempfile
from pathlib import Path

from civ1_roster_registration_truth import validate_entry


def minimal_glb(payload: bytes = b"{}  ") -> bytes:
    total = 20 + len(payload)
    return (
        struct.pack("<4sII", b"glTF", 2, total)
        + struct.pack("<I4s", len(payload), b"JSON")
        + payload
    )


def candidate(path: str, sha256: str, source_url: str) -> dict[str, str]:
    return {
        "asset_path": path,
        "role": "civilian",
        "sha256": sha256,
        "source_url": source_url,
        "license": "CC0-1.0",
    }


def main() -> int:
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        rel = "grand-bruxelles-game/assets/characters/civilian_nat64_fixture.glb"
        asset = root / rel
        asset.parent.mkdir(parents=True)
        asset.write_bytes(minimal_glb())
        sha256 = hashlib.sha256(asset.read_bytes()).hexdigest()

        nat64_sources = (
            "https://[64:ff9b::808:808]/source/civilian.glb",
            "https://[64:ff9b::7f00:1]/source/civilian.glb",
            "https://[64:ff9b:1::808:808]/source/civilian.glb",
        )
        for source in nat64_sources:
            result = validate_entry(candidate(rel, sha256, source), root)
            assert "source_url_ipv6_nat64_forbidden" in result["blocking_reasons"], (source, result)
            assert result["roster_eligible"] is False, (source, result)

        public_source = "https://[2606:4700:4700::1111]/source/civilian.glb"
        public = validate_entry(candidate(rel, sha256, public_source), root)
        assert "source_url_ipv6_nat64_forbidden" not in public["blocking_reasons"], public
        assert public["roster_eligible"] is True, public

    print("CIV1_ROSTER_NAT64_PROVENANCE_GREEN")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
