#!/usr/bin/env python3
"""Regression: authenticated JSON must be a lossless UTF-8 view of hashed bytes."""
from pathlib import Path

SRC = Path(__file__).parents[1] / "game" / "scripts" / "authenticated_source_document.gd"


def test_utf8_roundtrip_is_checked_after_digest_before_parse() -> None:
    source = SRC.read_text(encoding="utf-8")
    digest_pos = source.index("actual_sha != canonical_expected_sha")
    decode_pos = source.index("bytes.get_string_from_utf8()")
    roundtrip_pos = source.index("json_text.to_utf8_buffer() != bytes")
    parse_pos = source.index("JSON.parse_string(json_text)")
    assert digest_pos < decode_pos < roundtrip_pos < parse_pos
