#!/usr/bin/env python3
"""Regression: authenticated source parsing must use the exact bytes that were hashed."""
from pathlib import Path

SRC = Path(__file__).parents[1] / "game" / "scripts" / "automatic_road_direct_spawn.gd"


def _body(source: str, name: str) -> str:
    marker = f"func {name}("
    assert marker in source, f"missing {name}"
    tail = source.split(marker, 1)[1]
    next_func = tail.find("\nfunc ")
    return tail if next_func < 0 else tail[:next_func]


def test_authenticated_source_document_hashes_and_parses_one_buffer() -> None:
    source = SRC.read_text(encoding="utf-8")
    body = _body(source, "_load_authenticated_source_document")
    assert "FileAccess.open(" in body
    assert ".get_buffer(" in body
    assert "HashingContext.HASH_SHA256" in body
    assert "JSON.parse_string(" in body
    assert "FileAccess.get_sha256(" not in body
    assert "FileAccess.get_file_as_string(" not in body


def test_source_bundle_consumes_authenticated_document_only() -> None:
    source = SRC.read_text(encoding="utf-8")
    body = _body(source, "_source_bundle_by_id")
    assert "_load_authenticated_source_document(" in body
    assert "FileAccess.get_sha256(" not in body
    assert "FileAccess.get_file_as_string(" not in body
