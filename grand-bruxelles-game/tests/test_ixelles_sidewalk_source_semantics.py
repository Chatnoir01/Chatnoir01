import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE_CONTRACT = ROOT / "data/provenance/brussels_mobility_sidewalk_source.json"
RUNTIME = ROOT / "game/scripts/ixelles_midi_sidewalk_runtime.gd"
PROJECT = ROOT / "project.godot"


def test_ixelles_sidewalk_runtime_does_not_reintroduce_sw_only_semantics() -> None:
    contract = json.loads(SOURCE_CONTRACT.read_text(encoding="utf-8"))
    source = contract["source"]
    extract = contract["required_corridor_extract"]
    policy = contract["policy"]

    assert source["layer"] == "bm_urbis:urbadm_ssw"
    assert source["sidewalk_semantics_basis"] == "official_dataset_and_layer_identity"
    assert source["corridor_requires_ssft_sw"] is False
    assert extract["ssft_filter_required"] is False
    assert policy["runtime_geometry_authorized"] is False

    runtime_text = RUNTIME.read_text(encoding="utf-8")
    project_text = PROJECT.read_text(encoding="utf-8")

    # Keep the already-shipped Ixelles LABO material presentation, but make its
    # legacy source identity explicit and distinct from the current corridor
    # urbadm_ssw contract. It must never reinterpret legacy type=SW as a local
    # ssft filter for the current official layer.
    assert 'LEGACY_SOURCE_CONTRACT := "Paradigm UrbIS WFS cell.game street_surfaces.type"' in runtime_text
    assert 'CURRENT_OFFICIAL_LAYER := "bm_urbis:urbadm_ssw"' in runtime_text
    assert 'LEGACY_SURFACE_TYPE := "SW"' in runtime_text
    assert "ssft=SW" not in runtime_text and 'ssft == "SW"' not in runtime_text
    assert 'set_meta("uses_current_official_ssft_filter", false)' in runtime_text
    assert 'set_meta("material_identity_source_backed", false)' in runtime_text

    # The global autoload may remain only if it is event-driven/dormant outside
    # the Ixelles slice. The old 240-frame poll + error path is forbidden.
    assert "IxellesMidiSidewalkRuntime" in project_text
    assert "node_added.connect" in runtime_text
    assert "range(240)" not in runtime_text
    assert "official SW surface missing" not in runtime_text
    assert "push_error" not in runtime_text
