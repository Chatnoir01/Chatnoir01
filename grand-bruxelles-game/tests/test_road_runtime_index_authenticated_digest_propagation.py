#!/usr/bin/env python3
"""Regression: source bundles must propagate the digest of the exact authenticated bytes."""
from pathlib import Path

SRC = Path(__file__).parents[1] / "game" / "scripts" / "automatic_road_direct_spawn.gd"


def _body(source: str, name: str) -> str:
    marker = f"func {name}("
    assert marker in source, f"missing {name}"
    tail = source.split(marker, 1)[1]
    next_func = tail.find("\nfunc ")
    return tail if next_func < 0 else tail[:next_func]


def test_authenticated_loader_returns_verified_digest_with_document() -> None:
    source = SRC.read_text(encoding="utf-8")
    body = _body(source, "_load_authenticated_source_document")
    # The digest exported to callers must be the digest finalized from the same
    # captured bytes that are parsed, not the descriptor value or a later path read.
    assert "actual_sha" in body
    assert '"source_sha256"' in body
    assert '"document"' in body
    assert "expected_sha" in body
    assert "JSON.parse_string(" in body
    assert body.index("actual_sha") < body.index("JSON.parse_string(")


def test_source_bundle_propagates_authenticated_digest_without_rehash() -> None:
    source = SRC.read_text(encoding="utf-8")
    body = _body(source, "_source_bundle_by_id")
    assert "_load_authenticated_source_document(" in body
    assert '"source_sha256"' in body
    assert "FileAccess.get_sha256(" not in body
    assert "FileAccess.get_file_as_string(" not in body
    assert "_parse_document(" not in body
