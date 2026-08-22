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

    project_text = PROJECT.read_text(encoding="utf-8")
    assert "IxellesMidiSidewalkRuntime" not in project_text, (
        "runtime geometry is not authorized; obsolete Ixelles sidewalk autoload must stay retired"
    )

    if RUNTIME.exists():
        runtime_text = RUNTIME.read_text(encoding="utf-8")
        assert "StreetSurfaces_SW" not in runtime_text, "obsolete local SW-only node lookup remains"
        assert "official SW surface missing" not in runtime_text, "obsolete SW-only runtime failure remains"
        assert "ssft=SW" not in runtime_text and "ssft == \"SW\"" not in runtime_text
