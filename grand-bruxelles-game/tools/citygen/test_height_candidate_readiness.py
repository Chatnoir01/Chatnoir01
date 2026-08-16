#!/usr/bin/env python3
import importlib.util
import json
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("readiness", HERE / "height_candidate_readiness.py")
mod = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(mod)


def write(path: Path, value) -> None:
    path.write_text(json.dumps(value), encoding="utf-8")


with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    good = root / "good.json"
    pending = root / "pending.json"
    wrong_crs = root / "wrong_crs.json"
    malformed = root / "malformed.json"

    base = {
        "format": "grand-bruxelles-cell-elevation-value-evidence-v1",
        "crs": "EPSG:31370",
        "cell_id": "bxl-e141000-n167000-s500",
    }
    write(good, {**base, "height_source_pair_ready": True})
    write(pending, {**base, "height_source_pair_ready": False})
    write(wrong_crs, {**base, "crs": "EPSG:4326", "height_source_pair_ready": True})
    malformed.write_text("[]", encoding="utf-8")

    assert mod.is_height_candidate_ready(good) is True
    assert mod.is_height_candidate_ready(pending) is False
    assert mod.is_height_candidate_ready(wrong_crs) is False
    assert mod.is_height_candidate_ready(malformed) is False

print("HEIGHT_CANDIDATE_READINESS_OK fail_closed=true")
