#!/usr/bin/env python3
"""Regression: authenticated source capture must reject read errors before hashing/parsing."""
from pathlib import Path

SRC = Path(__file__).parents[1] / "game" / "scripts" / "authenticated_source_document.gd"


def test_read_error_is_rejected_before_authentication() -> None:
    source = SRC.read_text(encoding="utf-8")
    assert "file.get_error() != OK" in source
    assert "file.close()" in source
    read_pos = source.index("file.get_error() != OK")
    close_pos = source.index("file.close()")
    hash_pos = source.index("HashingContext.new()")
    parse_pos = source.index("JSON.parse_string(")
    assert read_pos < close_pos < hash_pos < parse_pos
