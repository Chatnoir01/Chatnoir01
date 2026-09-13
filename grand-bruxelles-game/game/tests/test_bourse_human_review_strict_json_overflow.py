#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

from strict_json_evidence import StrictJsonError, loads_strict

TEST_PATH = Path(__file__).with_name("test_bourse_8512036_human_review_receipt.py")


def main() -> int:
    source = TEST_PATH.read_text(encoding="utf-8")
    assert "from strict_json_evidence import load_path_strict" in source
    assert "receipt = load_path_strict(RECEIPT)" in source
    assert "metadata = load_path_strict(Path(metadata_path))" in source

    rejected = []
    for token in ("1e309", "-1e309"):
        try:
            loads_strict('{"value":' + token + "}")
        except StrictJsonError:
            rejected.append(token)
    assert rejected == ["1e309", "-1e309"], rejected
    print(
        "BOURSE_HUMAN_REVIEW_STRICT_JSON_OVERFLOW_OK "
        "receipt_bound=true artifact_metadata_bound=true finite_syntax_overflow_rejected=true"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
