#!/usr/bin/env python3
"""Regression: authenticated source handles must close on every post-open failure."""
from pathlib import Path

SRC = Path(__file__).parents[1] / "game" / "scripts" / "authenticated_source_document.gd"


def test_empty_source_closes_handle_before_return() -> None:
    source = SRC.read_text(encoding="utf-8")
    empty_branch = source.split("if expected_length <= 0:", 1)[1].split("var bytes :=", 1)[0]
    assert "file.close()" in empty_branch
    assert empty_branch.index("file.close()") < empty_branch.index("return {}")


def test_read_status_is_captured_then_handle_closed_before_authentication() -> None:
    source = SRC.read_text(encoding="utf-8")
    read_pos = source.index("var bytes := file.get_buffer(expected_length)")
    error_pos = source.index("var read_error := file.get_error()")
    close_pos = source.index("file.close()", error_pos)
    reject_pos = source.index("if bytes.size() != expected_length or read_error != OK:")
    hash_pos = source.index("HashingContext.new()")
    assert read_pos < error_pos < close_pos < reject_pos < hash_pos
