#!/usr/bin/env python3
"""Validate Laeken/Jette realism-reference provenance and measured-state claims."""

from __future__ import annotations

import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REF = ROOT / "data" / "reference" / "laeken_jette"
SRC = ROOT / "data" / "sources" / "laeken_jette"


def load(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def close(a: float, b: float, tol: float = 0.02) -> bool:
    return math.isfinite(a) and abs(a - b) <= tol


def explicitly_rejects_surveyed_camera_claim(note: str) -> bool:
    """Accept equivalent wording while preserving the provenance safety rule."""
    text = " ".join(note.lower().split())
    if "surveyed camera position" not in text:
        return False
    rejection_phrases = (
        "not a surveyed camera position",
        "not be used as a surveyed camera position",
        "must not be used as a surveyed camera position",
        "cannot be used as a surveyed camera position",
    )
    return any(phrase in text for phrase in rejection_phrases)


def validate_pending_camera_constraints(view: dict) -> None:
    """Pending benchmark cameras must be constrained by evidence, never intuition."""
    constraints = view.get("camera_selection_constraints")
    assert isinstance(constraints, dict), (
        f"{view.get('id')}: pending camera needs explicit camera_selection_constraints"
    )
    for key in ("authoritative_inputs", "must_resolve", "must_not_infer", "remaining_unknowns"):
        values = constraints.get(key)
        assert isinstance(values, list) and values, f"{view.get('id')}: missing {key} camera constraints"
        assert all(isinstance(value, str) and value.strip() for value in values), (
            f"{view.get('id')}: {key} must contain non-empty text entries"
        )
    joined_inputs = " ".join(constraints["authoritative_inputs"]).lower()
    assert any(authority in joined_inputs for authority in ("urbis", "dtm", "dsm", "official")), (
        f"{view.get('id')}: camera selection must depend on authoritative geometry/elevation data"
    )
    forbidden = " ".join(constraints["must_not_infer"]).lower()
    assert "photographer" in forbidden or "gps" in forbidden, (
        f"{view.get('id')}: pending camera must forbid unsupported photographer-position inference"
    )
    unknowns = " ".join(constraints["remaining_unknowns"]).lower()
    assert "exact" in unknowns, f"{view.get('id')}: remaining camera uncertainty must stay explicit"
    assert "camera_game_xz" not in view, (
        f"{view.get('id')}: camera coordinates must not be committed while status is camera_pending"
    )
    assert "target_game_xyz" not in view, (
        f"{view.get('id')}: target coordinates must not be committed while status is camera_pending"
    )


def validate_heysel_candidate_audit(audit: dict) -> None:
    assert audit.get("view_id") == "heysel_stadium_context_v1"
    assert audit.get("status") == "candidate_observation_levels_resolved_exact_pose_pending"
    reference = audit.get("reference_file", {})
    assert reference.get("published_camera_coordinates") is None
    assert reference.get("published_focal_length") is None
    assert reference.get("current_pixels") == [494, 370]
    assert reference.get("earlier_pixels") == [640, 480]
    assert "crop" in str(reference.get("current_file_edit_note", "")).lower()
    official = audit.get("official_atomium_observation_context", {})
    assert official.get("source_url", "").startswith("https://atomium.be/")
    upper = official.get("upper_sphere_panorama", {})
    lateral = official.get("lateral_sphere_viewpoint", {})
    assert close(float(upper.get("altitude_m", -1.0)), 92.0, 0.001)
    assert int(upper.get("view_degrees", 0)) == 360
    assert close(float(lateral.get("altitude_m", -1.0)), 36.0, 0.001)
    assert int(lateral.get("view_degrees", 0)) == 150
    candidates = audit.get("candidate_assessment", [])
    assert isinstance(candidates, list) and len(candidates) == 2
    assert {item.get("id") for item in candidates} == {"upper_panorama_92m", "lateral_viewpoint_36m"}
    assert all(item.get("status") == "plausible_not_proven" for item in candidates)
    unknowns = " ".join(audit.get("hard_unknowns", [])).lower()
    for token in ("exact", "focal", "crop", "yaw"):
        assert token in unknowns, f"Heysel candidate audit must preserve uncertainty about {token}"
    gate = audit.get("next_evidence_gate", [])
    assert isinstance(gate, list) and len(gate) >= 4
    assert any("urbis" in str(item).lower() for item in gate), "Heysel next gate must depend on UrbIS target geometry"


def validate_evidence_bounded_fov(view: dict) -> None:
    """Narrow hero FOVs are legal only when explicit source evidence bounds them."""
    fov = float(view.get("fov_degrees", 0.0))
    assert 20.0 <= fov <= 75.0, f"{view.get('id')}: implausible benchmark FOV"
    if fov >= 35.0:
        return
    witness = view.get("reference_visible_witness_evidence")
    assert isinstance(witness, dict), f"{view.get('id')}: narrow FOV requires explicit witness evidence"
    assert witness.get("path") == "atomium_ground_reference_witness.json"
    maximum = float(witness.get("maximum_fov_consistent_with_visible_witness_deg", 0.0))
    assert 20.0 <= fov <= maximum, (
        f"{view.get('id')}: narrow FOV {fov} exceeds evidence bound {maximum}"
    )
    policy = str(witness.get("selection_policy", "")).lower()
    assert "not" in policy and "historical" in policy and "focal" in policy, (
        f"{view.get('id')}: evidence-bounded FOV must reject historical-lens claims"
    )
    status = str(view.get("fov_status", "")).lower()
    assert "bounded" in status and "not_lens_recovery" in status, (
        f"{view.get('id')}: narrow FOV status must preserve evidence/uncertainty semantics"
    )


def main() -> int:
    realism = load(REF / "realism_pass1.json")
    jette = load(REF / "jette_photo_references.json")
    photo_match = load(REF / "photo_match_views.json")
    findings = load(REF / "photo_match_findings.json")
    heysel_audit = load(REF / "heysel_camera_candidate_audit.json")
    heights = load(SRC / "building_height_integration_validation.json")

    assert realism["schema"] >= 2
    assert photo_match["schema"] >= 3
    measured = realism["measured_height_validation"]
    assert measured["status"] == "passed"
    assert measured["source_feature_count"] == heights["source_feature_count"]
    assert measured["derived_height_count"] == heights["source_derived_height_count"]
    assert measured["fallback_count"] == heights["source_quality_counts"]["insufficient"]
    coverage = 100.0 * measured["derived_height_count"] / measured["source_feature_count"]
    assert close(measured["derived_coverage_percent"], coverage)
    assert "DSM-DTM" in realism["current_visual_rules"]["building_heights"]
    assert "temporary pending" not in realism["current_visual_rules"]["building_heights"].lower()

    refs = {item["id"]: item for item in jette["references"]}
    miroir = refs["miroir_commons_2011"]
    assert miroir["license"] == "CC BY-SA 3.0"
    assert miroir["source_location_semantics"] == "depicted_place_not_camera_position"
    assert miroir["embedded_asset"] is False
    assert len(miroir["source_wgs84_depicted_place"]) == 2
    assert len(miroir["source_epsg31370_depicted_place"]) == 2
    assert len(miroir["source_game_xz_depicted_place"]) == 2
    note = miroir["source_coordinate_note"].lower()
    assert "not photographer" in note
    assert explicitly_rejects_surveyed_camera_claim(note), (
        "depicted-place coordinate note must explicitly reject use as a surveyed camera position"
    )

    origin = jette["project_origin"]
    e, n = miroir["source_epsg31370_depicted_place"]
    x, z = miroir["source_game_xz_depicted_place"]
    assert close(x, e - origin["epsg31370_e"])
    assert close(z, -(n - origin["epsg31370_n"]))

    validate_heysel_candidate_audit(heysel_audit)

    gate = photo_match.get("quality_gate", {})
    minimum_views = int(gate.get("minimum_reference_views", 0))
    views = photo_match["views"]
    assert minimum_views >= 3, "photo-match gate must require at least three reference views"
    assert len(views) >= minimum_views, (
        f"photo-match registry has {len(views)} views but gate requires {minimum_views}"
    )
    ids = [view.get("id") for view in views]
    assert len(ids) == len(set(ids)), "photo-match benchmark IDs must be unique"
    urls = []
    for view in views:
        status = view.get("status", "")
        reference = view.get("reference", {})
        assert reference.get("url"), f"{view.get('id')}: missing reference URL"
        assert reference.get("license"), f"{view.get('id')}: missing reference license"
        assert reference.get("usage"), f"{view.get('id')}: missing reference usage policy"
        assert len(view.get("comparison_checks", [])) >= 5, (
            f"{view.get('id')}: photo-match benchmark needs at least five visual checks"
        )
        assert view.get("resolution") == [1280, 720], (
            f"{view.get('id')}: benchmark capture resolution must stay deterministic"
        )
        validate_evidence_bounded_fov(view)
        if "provisional" in status or "pending" in status:
            uncertainty = " ".join(
                [
                    str(view.get("camera_claim", "")),
                    str(reference.get("usage", "")),
                ]
            ).lower()
            assert "provisional" in uncertainty or "survey" in uncertainty or "no photographer" in uncertainty, (
                f"{view.get('id')}: uncertain benchmark must explicitly state camera uncertainty"
            )
        if "camera_pending" in status:
            validate_pending_camera_constraints(view)
        urls.append(reference["url"])
    assert len(set(urls)) >= 3, "three-view gate must use three independently registered reference pages"

    finding_items = findings.get("findings", [])
    assert findings.get("status") == "open", "photo-match findings registry must remain open while blockers exist"
    assert finding_items, "photo-match findings registry must contain actionable discrepancies"
    finding_ids = [item.get("id") for item in finding_items]
    assert len(finding_ids) == len(set(finding_ids)), "photo-match finding IDs must be unique"
    valid_view_ids = set(ids) | {"zone_wide"}
    open_high = 0
    covered_views = set()
    for item in finding_items:
        assert item.get("view_id") in valid_view_ids, f"{item.get('id')}: unknown benchmark view"
        assert item.get("status") in {"open", "closed"}, f"{item.get('id')}: invalid status"
        assert item.get("severity") in {"low", "medium", "high"}, f"{item.get('id')}: invalid severity"
        assert item.get("category"), f"{item.get('id')}: missing category"
        assert item.get("evidence"), f"{item.get('id')}: missing evidence"
        assert item.get("action"), f"{item.get('id')}: missing action"
        if item.get("view_id") != "zone_wide":
            covered_views.add(item["view_id"])
        if item.get("status") == "open" and item.get("severity") == "high":
            open_high += 1
    assert set(ids).issubset(covered_views), "every benchmark view must have at least one tracked discrepancy until validated"
    assert open_high > 0, "realism gate must not report completion while high-severity discrepancies remain"

    policy = jette["reference_policy"]
    assert "never infer" in policy["camera_claim_rule"].lower()
    assert policy["geometry_authority"][0] == "UrbIS WFS"

    print(
        "LAEKEN_JETTE_REFERENCE_REGISTRY_OK: "
        f"height_coverage={coverage:.2f}% refs={len(refs)} benchmarks={len(views)} "
        f"findings={len(finding_items)} open_high={open_high} heysel_candidates=2"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
