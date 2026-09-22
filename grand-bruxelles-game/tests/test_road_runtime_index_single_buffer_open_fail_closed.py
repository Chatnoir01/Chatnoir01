#!/usr/bin/env python3
"""Regression: authenticated source capture must fail closed on open/read errors."""
from pathlib import Path

SRC = Path(__file__).parents[1] / "game" / "scripts" / "automatic_road_direct_spawn.gd"


def _body(source: str, name: str) -> str:
    marker = f"func {name}("
    assert marker in source, f"missing {name}"
    tail = source.split(marker, 1)[1]
    next_func = tail.find("\nfunc ")
    return tail if next_func < 0 else tail[:next_func]


def test_authenticated_source_open_and_capture_fail_closed_before_hash() -> None:
    source = SRC.read_text(encoding="utf-8")
    body = _body(source, "_load_authenticated_source_document")

    # Authentication must be based on one successfully opened handle. A failed
    # open, zero-length source, or short capture must return before HashingContext
    # is started, so no missing/truncated source can become an authenticated doc.
    assert "FileAccess.open(" in body
    assert "FileAccess.READ" in body
    assert ".get_length()" in body
    assert ".get_buffer(" in body
    assert ".size()" in body
    assert "HashingContext.HASH_SHA256" in body

    open_pos = body.index("FileAccess.open(")
    length_pos = body.index(".get_length()")
    buffer_pos = body.index(".get_buffer(")
    size_pos = body.index(".size()")
    hash_pos = body.index("HashingContext.HASH_SHA256")
    assert open_pos < length_pos < buffer_pos < size_pos < hash_pos

    prefix = body[:hash_pos]
    assert "return {}" in prefix
    assert "== null" in prefix or "if not" in prefix
