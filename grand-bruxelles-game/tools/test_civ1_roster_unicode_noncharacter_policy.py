#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import struct
import tempfile
from pathlib import Path
from urllib.parse import quote

from civ1_roster_registration_truth import (
    _percent_encoded_component_has_noncharacter,
    build_payload,
    validate_entry,
)


def minimal_glb(payload: bytes = b"{}  ") -> bytes:
    total = 20 + len(payload)
    return struct.pack("<4sII", b"glTF", 2, total) + struct.pack("<I4s", len(payload), b"JSON") + payload


def escaped_codepoint(codepoint: int) -> str:
    return quote(chr(codepoint), safe="")


def lowercase_percent_hex(value: str) -> str:
    return value.lower()


def mixedcase_percent_hex(value: str) -> str:
    out: list[str] = []
    hex_index = 0
    for char in value:
        if char == "%":
            out.append(char)
            continue
        out.append(char.upper() if hex_index % 2 == 0 else char.lower())
        hex_index += 1
    return "".join(out)


def assert_source_rejected(entry: dict[str, str], root: Path, codepoint: int | str, placement: str) -> None:
    result = validate_entry(entry, root)
    label = hex(codepoint) if isinstance(codepoint, int) else codepoint
    assert "source_url_not_canonical" in result["blocking_reasons"], (label, placement, result)
    assert result["roster_eligible"] is False, (label, placement, result)


def assert_source_canonical(entry: dict[str, str], root: Path, codepoint: int, placement: str) -> None:
    result = validate_entry(entry, root)
    assert "source_url_not_canonical" not in result["blocking_reasons"], (hex(codepoint), placement, result)


def main() -> None:
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        rel = "grand-bruxelles-game/assets/characters/civilian_fixture.glb"
        asset = root / rel
        asset.parent.mkdir(parents=True)
        asset.write_bytes(minimal_glb())
        sha = hashlib.sha256(asset.read_bytes()).hexdigest()

        forbidden = tuple(range(0xFDD0, 0xFDF0)) + tuple(
            codepoint for plane in range(17)
            for codepoint in ((plane << 16) | 0xFFFE, (plane << 16) | 0xFFFF)
        )
        assert len(forbidden) == 66
        assert len(set(forbidden)) == 66
        for codepoint in forbidden:
            escaped = escaped_codepoint(codepoint)
            entry = {"asset_path": rel, "role": "civilian", "sha256": sha,
                     "source_url": f"https://assets.character-fixtures.com/source/civilian{escaped}alias.glb",
                     "license": "CC0-1.0"}
            assert_source_rejected(entry, root, codepoint, "path_interior")

        boundary_cases = (0xFDD0, 0xFDEF, 0xFFFE, 0xFFFF, 0x10FFFE, 0x10FFFF)
        for codepoint in boundary_cases:
            escaped = escaped_codepoint(codepoint)
            escaped_lower = lowercase_percent_hex(escaped)
            escaped_mixed = mixedcase_percent_hex(escaped)
            assert escaped_mixed != escaped, (hex(codepoint), escaped_mixed)
            assert escaped_mixed != escaped_lower, (hex(codepoint), escaped_mixed)
            assert _percent_encoded_component_has_noncharacter(escaped), hex(codepoint)
            assert _percent_encoded_component_has_noncharacter(escaped_lower), hex(codepoint)
            assert _percent_encoded_component_has_noncharacter(escaped_mixed), hex(codepoint)
            for placement, url in (
                ("segment_start", f"https://assets.character-fixtures.com/source/{escaped}civilian.glb"),
                ("segment_end", f"https://assets.character-fixtures.com/source/civilian{escaped}"),
                ("whole_segment", f"https://assets.character-fixtures.com/source/{escaped}"),
                ("query", f"https://assets.character-fixtures.com/source/civilian.glb?variant={escaped}"),
                ("fragment", f"https://assets.character-fixtures.com/source/civilian.glb#{escaped}"),
                ("path_lowercase_hex", f"https://assets.character-fixtures.com/source/civilian{escaped_lower}alias.glb"),
                ("query_lowercase_hex", f"https://assets.character-fixtures.com/source/civilian.glb?variant={escaped_lower}"),
                ("fragment_lowercase_hex", f"https://assets.character-fixtures.com/source/civilian.glb#{escaped_lower}"),
                ("path_mixedcase_hex", f"https://assets.character-fixtures.com/source/civilian{escaped_mixed}alias.glb"),
                ("query_mixedcase_hex", f"https://assets.character-fixtures.com/source/civilian.glb?variant={escaped_mixed}"),
                ("fragment_mixedcase_hex", f"https://assets.character-fixtures.com/source/civilian.glb#{escaped_mixed}"),
            ):
                entry = {"asset_path": rel, "role": "civilian", "sha256": sha, "source_url": url, "license": "CC0-1.0"}
                assert_source_rejected(entry, root, codepoint, placement)

        positive_controls = (0xFDCF, 0xFDF0, 0xFFFD) + tuple((plane << 16) | 0xFFFD for plane in range(1, 17))
        for codepoint in positive_controls:
            escaped = escaped_codepoint(codepoint)
            escaped_lower = lowercase_percent_hex(escaped)
            escaped_mixed = mixedcase_percent_hex(escaped)
            assert escaped_mixed != escaped, (hex(codepoint), escaped_mixed)
            assert escaped_mixed != escaped_lower, (hex(codepoint), escaped_mixed)
            assert not _percent_encoded_component_has_noncharacter(escaped), hex(codepoint)
            assert not _percent_encoded_component_has_noncharacter(escaped_lower), hex(codepoint)
            assert not _percent_encoded_component_has_noncharacter(escaped_mixed), hex(codepoint)
            for placement, url in (
                ("interior", f"https://assets.character-fixtures.com/source/civilian{escaped}alias.glb"),
                ("segment_start", f"https://assets.character-fixtures.com/source/{escaped}civilian.glb"),
                ("segment_end", f"https://assets.character-fixtures.com/source/civilian{escaped}"),
                ("whole_segment", f"https://assets.character-fixtures.com/source/{escaped}"),
                ("query", f"https://assets.character-fixtures.com/source/civilian.glb?variant={escaped}"),
                ("fragment", f"https://assets.character-fixtures.com/source/civilian.glb#{escaped}"),
            ):
                entry = {"asset_path": rel, "role": "civilian", "sha256": sha, "source_url": url, "license": "CC0-1.0"}
                assert_source_canonical(entry, root, codepoint, placement)

        # The noncharacter detector intentionally returns false for malformed UTF-8.
        # Canonical source validation currently owns malformed-percent rejection on
        # the path contract; do not silently broaden query/fragment policy here.
        malformed_utf8 = (
            "%C0%AF", "%ED%A0%80", "%F4%90%80%80", "%E2%82", "%F0%9F%92",
        )
        for escaped in malformed_utf8:
            assert not _percent_encoded_component_has_noncharacter(escaped), escaped
            entry = {"asset_path": rel, "role": "civilian", "sha256": sha,
                     "source_url": f"https://assets.character-fixtures.com/source/civilian{escaped}alias.glb",
                     "license": "CC0-1.0"}
            assert_source_rejected(entry, root, escaped, "malformed_path")

        payload = build_payload({"schema": "grand-bruxelles-civ1-roster-registry-v1", "entries": []}, root)
        assert payload["source_url_unicode_noncharacter_forbidden"] is True, payload

    print("CIV1_ROSTER_UNICODE_NONCHARACTER_POLICY_GREEN")


if __name__ == "__main__":
    main()
