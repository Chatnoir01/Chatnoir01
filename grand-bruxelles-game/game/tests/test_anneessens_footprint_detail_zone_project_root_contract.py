from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
TEST_SCRIPT = ROOT / "tests" / "osm_city_builder_anneessens_footprint_detail_zone_test.gd"
SUBPROJECT_PATH = '"res://scripts/osm_city_builder.gd"'
ROOT_PROJECT_PATH = '"res://game/scripts/osm_city_builder.gd"'


def main() -> None:
    source = TEST_SCRIPT.read_text(encoding="utf-8")
    assert "preload(" not in source, (
        "Anneessens footprint detail-zone test must not parse-time preload a path that is valid "
        "for only one of the two Godot project roots"
    )
    assert source.count(SUBPROJECT_PATH) == 1, (
        "subproject execution must retain the canonical res://scripts builder path"
    )
    assert source.count(ROOT_PROJECT_PATH) == 1, (
        "root-project import must retain the canonical res://game/scripts builder path"
    )
    assert "ResourceLoader.exists(candidate, \"Script\")" in source, (
        "builder loading must fail closed through ResourceLoader before dynamic load"
    )
    assert (ROOT / "scripts" / "osm_city_builder.gd").is_file(), (
        "canonical subproject builder script is missing"
    )
    assert (ROOT.parent / "game" / "scripts" / "osm_city_builder.gd").is_file(), (
        "canonical root-project builder script is missing"
    )
    print("ANNEESSENS_FOOTPRINT_PROJECT_ROOT_CONTRACT_GREEN dual_root_import_safe=true")


if __name__ == "__main__":
    main()
