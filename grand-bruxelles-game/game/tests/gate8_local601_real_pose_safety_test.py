#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CONTRACT = ROOT / "data" / "qa" / "gate8_local601_real_pose_safety.json"


def fail(message: str) -> None:
    raise SystemExit(f"GATE8_LOCAL601_SAFETY_FAIL: {message}")


def main() -> int:
    data = json.loads(CONTRACT.read_text(encoding="utf-8"))
    if data.get("format") != "grand-bruxelles-gate8-local601-real-pose-safety-v1":
        fail("format drift")
    if data.get("production_base_sha") != "c7d2c4981b17992e71c91fa53a9f7a2ac5502535":
        fail("production base drift")
    if data.get("source_run_id") != 33282981044:
        fail("source run drift")
    if data.get("source_head_sha") != "8af666d0b151bfc012b28655e8e4a455897368ba":
        fail("source head drift")
    if data.get("artifact_id") != 9723546302:
        fail("artifact id drift")
    if data.get("artifact_digest") != "sha256:99da25f988c5c472fab825c669146f7d0ac5281110fdad1eda76c6771b6eb277":
        fail("artifact digest drift")
    if data.get("candidate_vertices") != [601]:
        fail("candidate scope drift")
    if data.get("verdict") != "REJECT_LOCAL601_REMATCH_FOR_PRODUCTION":
        fail("unsafe verdict drift")

    m = data.get("measurements")
    if not isinstance(m, dict):
        fail("measurements missing")
    critical_stored = m.get("critical_edge_mean_stored_abs_strain")
    critical_candidate = m.get("critical_edge_mean_candidate_abs_strain")
    control_stored = m.get("control_edge_mean_stored_abs_strain")
    control_candidate = m.get("control_edge_mean_candidate_abs_strain")
    delta_601 = m.get("vertex_601_stored_vs_candidate_delta_m")
    if not all(type(v) is float for v in (critical_stored, critical_candidate, control_stored, control_candidate, delta_601)):
        fail("measurement type drift")
    if not critical_candidate < critical_stored:
        fail("critical edges were not improved")
    if not control_candidate > control_stored * 40.0:
        fail("control-edge regression evidence weakened")
    if not delta_601 > 0.5:
        fail("vertex-601 displacement evidence weakened")
    edge = m.get("control_edge_378_601")
    if not isinstance(edge, dict):
        fail("control edge 378-601 missing")
    if edge.get("candidate_abs_strain") != 42.13487293102466 or edge.get("stored_abs_strain") != 0.7165112716322206:
        fail("control edge 378-601 measurement drift")
    if m.get("stored_inversion_count") != 0 or m.get("candidate_inversion_count") != 0:
        fail("inversion evidence drift")

    for rail in (
        "canonical_asset_mutation",
        "canonical_mhclo_mutation",
        "canonical_generator_mutation",
        "runtime_npc_mutation",
        "production_activation_allowed",
        "visual_approval_allowed",
    ):
        if data.get(rail) is not False:
            fail(f"rail opened: {rail}")
    if data.get("next_safe_axis") != "TEST_NEXT_SMALLEST_TOPOLOGY_CONSTRAINED_SUPPORT_STRATEGY":
        fail("next safe axis drift")

    print(
        "GATE8_LOCAL601_SAFETY_OK: verdict=REJECT_LOCAL601_REMATCH_FOR_PRODUCTION "
        f"critical_mean={critical_candidate:.12f} control_mean={control_candidate:.12f} "
        f"vertex601_delta_m={delta_601:.12f}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
