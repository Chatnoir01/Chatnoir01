#!/usr/bin/env python3
from pathlib import Path

root = Path(__file__).resolve().parents[2]
text = (root.parent / ".github/workflows/grand-bruxelles-bourse-8512036-human-review.yml").read_text(encoding="utf-8")
assert "from strict_json_evidence import load_path_strict" in text
assert "receipt = load_path_strict(" in text
print("BOURSE_REVIEW_RECEIPT_PREFLIGHT_OK strict=true")
