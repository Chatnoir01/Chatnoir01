#!/usr/bin/env python3
"""Run synthetic JSON-contract regressions against the catalog core.

These fixtures intentionally model catalog/source JSON semantics without a complete
production provenance manifest. The canonical lock-bound entrypoint is exercised by
the real-slice catalog regression; synthetic contract cases must not invent source
provenance merely to reach the mature catalog validator.
"""
from __future__ import annotations

import importlib.util
import tempfile
from pathlib import Path

CASES_PATH = Path(__file__).resolve().with_name("_road_destination_catalog_json_contract_cases.py")
spec = importlib.util.spec_from_file_location("road_destination_catalog_json_contract_cases", CASES_PATH)
assert spec and spec.loader
cases = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cases)

CORE_PATH = Path(__file__).resolve().parents[1] / "_road_destination_catalog_core.py"
core_spec = importlib.util.spec_from_file_location("road_destination_catalog_json_contract_core", CORE_PATH)
assert core_spec and core_spec.loader
core = importlib.util.module_from_spec(core_spec)
core_spec.loader.exec_module(core)

# The cases are deliberately synthetic. Keep them on the mature deterministic core
# so source-lock/provenance validation remains reserved for canonical real-source
# tests instead of being weakened or counterfeited in fixtures.
cases.module = core


def _run_duplicate_source_key_probe() -> None:
    """Canonical source JSON semantics must reject duplicate object keys."""
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp) / "data" / "osm"
        root.mkdir(parents=True, exist_ok=True)
        source = root / "duplicate-key.game.json"
        source.write_text(
            '{"format":"grand-bruxelles-osm-v1","format":"grand-bruxelles-osm-v1",'
            '"roads":[{"osm_id":42,"name":"Rue Test","class":"tertiary",'
            '"width":7.0,"drivable":true,"points":[[0.0,0.0],[10.0,0.0]]}],'
            '"buildings":[]}',
            encoding="utf-8",
        )
        try:
            core.build_catalog(root)
        except SystemExit as exc:
            assert "duplicate JSON object key" in str(exc), str(exc)
        else:
            raise AssertionError("expected duplicate source JSON object key to fail closed")


if __name__ == "__main__":
    result = cases.main()
    _run_duplicate_source_key_probe()
    raise SystemExit(result)
