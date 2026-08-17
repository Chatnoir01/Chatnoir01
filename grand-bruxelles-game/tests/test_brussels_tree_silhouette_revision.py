from pathlib import Path

ASSET = Path(__file__).resolve().parents[1] / "game/scripts/brussels_street_tree_asset.gd"


def main() -> None:
    text = ASSET.read_text(encoding="utf-8")
    assert "SILHOUETTE_REVISION := 2" in text
    assert "FOLIAGE_LOBE_COUNT := 8" in text
    assert "authored_presentation_not_source_measurement" in text
    assert "source_dimensions_measured" in text
    assert "species_claimed" in text
    assert "tree_variation_scale" in text
    assert "foliage_tone_variation" in text
    print("BRUSSELS_TREE_SILHOUETTE_REVISION_OK")


if __name__ == "__main__":
    main()
