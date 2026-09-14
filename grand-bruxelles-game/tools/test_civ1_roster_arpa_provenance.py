#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import struct
import tempfile
from pathlib import Path

from civ1_roster_registration_truth import validate_entry


def minimal_glb(payload: bytes = b"{}  ") -> bytes:
    total = 20 + len(payload)
    return struct.pack("<4sII", b"glTF", 2, total) + struct.pack("<I4s", len(payload), b"JSON") + payload


def candidate(path: str, sha256: str, source_url: str) -> dict[str, str]:
    return {
        "asset_path": path,
        "role": "civilian",
        "sha256": sha256,
        "source_url": source_url,
        "license": "CC0-1.0",
    }


def main() -> None:
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        rel = "grand-bruxelles-game/assets/characters/civilian_arpa_fixture.glb"
        asset = root / rel
        asset.parent.mkdir(parents=True)
        asset.write_bytes(minimal_glb())
        sha256 = hashlib.sha256(asset.read_bytes()).hexdigest()

        # The ARPA namespace is DNS infrastructure, not an ordinary immutable
        # public asset-provenance origin. Reverse-DNS subtrees are especially
        # unsuitable as canonical HTTPS source identities.
        forbidden = (
            "https://in-addr.arpa/source/civilian.glb",
            "https://8.8.8.8.in-addr.arpa/source/civilian.glb",
            "https://ip6.arpa/source/civilian.glb",
            "https://b.a.9.f.4.6.0.0.ip6.arpa/source/civilian.glb",
            "https://assets.arpa/source/civilian.glb",
        )
        for source in forbidden:
            result = validate_entry(candidate(rel, sha256, source), root)
            assert "source_url_dns_infrastructure_namespace_forbidden" in result["blocking_reasons"], (source, result)
            assert result["roster_eligible"] is False, (source, result)

        public = validate_entry(
            candidate(rel, sha256, "https://assets.character-fixtures.com/source/civilian.glb"),
            root,
        )
        assert "source_url_dns_infrastructure_namespace_forbidden" not in public["blocking_reasons"], public
        assert public["roster_eligible"] is True, public

    print("CIV1_ROSTER_ARPA_PROVENANCE_GREEN")


if __name__ == "__main__":
    main()
