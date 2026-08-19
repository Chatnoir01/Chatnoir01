from pathlib import Path

ASSET = Path(__file__).resolve().parents[1] / "game/scripts/brussels_street_tree_asset.gd"


def main() -> None:
    text = ASSET.read_text(encoding="utf-8")
    assert 'ASSET_FAMILY := "brussels_street_tree_v1"' in text
    assert "SILHOUETTE_REVISION := 2" in text
    assert "FOLIAGE_LOBE_COUNT := 8" in text
    assert "authored_presentation_not_source_measurement" in text
    assert 'set_meta("source_dimensions_measured", false)' in text
    assert 'set_meta("species_claimed", false)' in text
    assert "tree_variation_scale" in text
    assert "foliage_tone_variation" in text
    print("BRUSSELS_TREE_SILHOUETTE_REVISION_OK")


if __name__ == "__main__":
    main()
