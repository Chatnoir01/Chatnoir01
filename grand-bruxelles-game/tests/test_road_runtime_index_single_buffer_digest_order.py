#!/usr/bin/env python3
"""Regression: authenticated source digest must be finalized and matched before JSON parse."""
from pathlib import Path

SRC = Path(__file__).parents[1] / "game" / "scripts" / "automatic_road_direct_spawn.gd"


def _body(source: str, name: str) -> str:
    marker = f"func {name}("
    assert marker in source, f"missing {name}"
    tail = source.split(marker, 1)[1]
    next_func = tail.find("\nfunc ")
    return tail if next_func < 0 else tail[:next_func]


def test_authenticated_source_digest_is_verified_before_parse() -> None:
    source = SRC.read_text(encoding="utf-8")
    body = _body(source, "_load_authenticated_source_document")

    # Authentication is meaningful only if the exact captured bytes are fed to
    # HashingContext, the finalized digest is compared with the canonical
    # expected SHA, and JSON parsing happens strictly after that comparison.
    assert "HashingContext.new()" in body
    assert ".start(HashingContext.HASH_SHA256)" in body
    assert ".update(" in body
    assert ".finish()" in body
    assert "hex_encode()" in body
    assert "expected_sha" in body
    assert "JSON.parse_string(" in body

    start_pos = body.index(".start(HashingContext.HASH_SHA256)")
    update_pos = body.index(".update(")
    finish_pos = body.index(".finish()")
    compare_pos = body.index("expected_sha", finish_pos)
    parse_pos = body.index("JSON.parse_string(")

    assert start_pos < update_pos < finish_pos < compare_pos < parse_pos
