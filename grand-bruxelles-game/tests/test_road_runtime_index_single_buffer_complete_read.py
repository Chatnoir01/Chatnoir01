#!/usr/bin/env python3
"""Regression: authenticated source capture must reject incomplete/empty reads before parsing."""
from pathlib import Path

SRC = Path(__file__).parents[1] / "game" / "scripts" / "automatic_road_direct_spawn.gd"


def _body(source: str, name: str) -> str:
    marker = f"func {name}("
    assert marker in source, f"missing {name}"
    tail = source.split(marker, 1)[1]
    next_func = tail.find("\nfunc ")
    return tail if next_func < 0 else tail[:next_func]


def test_authenticated_source_capture_requires_complete_nonempty_buffer() -> None:
    source = SRC.read_text(encoding="utf-8")
    body = _body(source, "_load_authenticated_source_document")

    # The helper must derive the expected byte count from the already-open file,
    # read exactly that many bytes once, and reject empty/short captures before
    # either hashing or JSON parsing. This prevents a truncated capture from
    # becoming an authenticated document and keeps hash+parse on one buffer.
    assert ".get_length()" in body
    assert ".get_buffer(" in body
    assert ".size()" in body
    assert "JSON.parse_string(" in body
    assert "HashingContext.HASH_SHA256" in body

    length_pos = body.index(".get_length()")
    buffer_pos = body.index(".get_buffer(")
    size_pos = body.index(".size()")
    hash_pos = body.index("HashingContext.HASH_SHA256")
    parse_pos = body.index("JSON.parse_string(")

    assert length_pos < buffer_pos < size_pos < hash_pos < parse_pos
