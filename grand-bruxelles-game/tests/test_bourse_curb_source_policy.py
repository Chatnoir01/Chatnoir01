#!/usr/bin/env python3
import json
from pathlib import Path

P = Path(__file__).resolve().parents[1] / "data/urbis/bourse_curb_source_policy.game.json"
D = json.loads(P.read_text(encoding="utf-8"))
assert D["schema"] == "grand-bruxelles-bourse-curb-source-policy-v1"
assert D["decision"]["horizontal_curb_alignment_source_candidates"] is True
assert D["decision"]["physical_curb_height_supported"] is False
assert D["decision"]["dtm_1m_is_not_curb_height_proof"] is True
assert D["decision"]["vertical_extrusion_allowed"] is False
assert D["decision"]["curb_elevation_resolved"] is False
assert D["decision"]["runtime_approved"] is False
assert D["decision"]["realism_complete"] is False
codes = {c for source in D["source_evidence"] for c in source.get("topo_types", [])}
assert "CR63L" in codes
assert {"BR0101L", "BR0102L", "BR13L"} <= codes
print("BOURSE_CURB_SOURCE_POLICY_OK")
