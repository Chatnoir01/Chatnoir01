from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TOOL = ROOT / "tools" / "civ1_canonical_placement_contract.py"


def test_civ1_canonical_placement_contract_source() -> None:
    text = TOOL.read_text(encoding="utf-8")

    assert 'grand-bruxelles-civ1-canonical-placement-contract-v1' in text
    assert '"Main/Ground"' in text
    assert 'ground_top_y = ground_position[1] + ground_size[1] * 0.5' in text

    # Current live runtime copies spawn Y verbatim. Until a real authored/mounted
    # placement or grounding mechanism is proven, no Ground-contact promotion is allowed.
    assert '"spawn_y_is_copied_verbatim": exact_spawn_copy' in text
    assert '"pooled_spawn_y_is_copied_verbatim": pooled_spawn_copy' in text
    assert '"canonical_character_placement_available": canonical_available' in text
    assert '"ground_contact_classifiable": False' in text
    assert '"contact_proof_claimed": False' in text
    assert '"planted_interval_claimable": False' in text
    assert '"quantitative_foot_slide_candidate": False' in text
    assert '"animation_correction_authorized": False' in text
    assert '"runtime_change_authorized": False' in text
    assert '"visual_approval_claimed": False' in text
    assert '"player_view_claimed": False' in text

    # Do not silently convert the earlier geometry-derived/bilateral offset into
    # production truth and do not invent a gameplay epsilon/percentile threshold.
    forbidden = [
        "placement_y",
        "bilateral",
        "percentile",
        "quantile",
        "contact_threshold",
        "foot_slide_threshold",
        "camera_fov",
    ]
    lowered = text.lower()
    for token in forbidden:
        assert token not in lowered


if __name__ == "__main__":
    test_civ1_canonical_placement_contract_source()
    print("CIV1_CANONICAL_PLACEMENT_CONTRACT_REGRESSION_GREEN")
