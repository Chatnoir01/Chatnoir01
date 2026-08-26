from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "game/tests/brussels_base_ground_surface_player_witness_test.gd"
WORKFLOW = ROOT.parent / ".github/workflows/grand-bruxelles-base-ground-surface-player-witness.yml"


def test_base_ground_witness_is_bound_to_live_main_and_exact_head():
    script = SCRIPT.read_text()
    workflow = WORKFLOW.read_text()

    # The witness must never certify against a historical hard-coded production base.
    assert "const PRODUCTION_BASE_SHA" not in script
    assert 'OS.get_environment("GB_LIVE_MAIN_SHA")' in script
    assert 'OS.get_environment("GB_EVIDENCE_HEAD_SHA")' in script
    assert '"live_main_sha"' in script
    assert '"candidate_head_sha"' in script

    # CI must derive provenance from the remote live main and exact PR head.
    assert "fetch-depth: 0" in workflow
    assert "git fetch --no-tags origin main" in workflow
    assert "git merge-base --is-ancestor \"$LIVE_MAIN_SHA\" HEAD" in workflow
    assert "GB_LIVE_MAIN_SHA=$LIVE_MAIN_SHA" in workflow
    assert "GB_EVIDENCE_HEAD_SHA=$HEAD_SHA" in workflow
    assert "report['live_main_sha'] == live" in workflow
    assert "report['candidate_head_sha'] == head" in workflow
    assert "report['production_base_sha']" not in workflow


if __name__ == "__main__":
    test_base_ground_witness_is_bound_to_live_main_and_exact_head()
    print("BASE_GROUND_WITNESS_LIVE_PROVENANCE_OK")
