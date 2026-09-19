from pathlib import Path

ROOT = Path(__file__).parents[1]
RESOLVER = ROOT / "game" / "scripts" / "automatic_road_direct_spawn.gd"


def _function_body(name: str, next_name: str) -> str:
    source = RESOLVER.read_text(encoding="utf-8")
    start = source.index(f"func {name}")
    end = source.index(f"\n\nfunc {next_name}", start)
    return source[start:end]


def test_lookup_reauthenticates_live_source_bytes_before_parse_or_return() -> None:
    """Keep the lookup-time SHA check as a second defense after loader pre-auth."""
    body = _function_body("_source_bundle_by_id(osm_id: int) -> Dictionary:", "_exact_source_point_2d")

    expected = body.index('var expected_sha := str(_source_sha_by_path.get(path, ""))')
    actual = body.index("var actual_sha := FileAccess.get_sha256(path).to_lower()")
    mismatch = body.index("actual_sha != expected_sha")
    parse = body.index("var document := _parse_document(path)")
    success = body.index('"lookup_mode": "deterministic_runtime_index"')

    assert expected < actual < mismatch < parse < success
    assert '"source_sha256": actual_sha' in body
    assert '"source_sha256": expected_sha' not in body
    assert body.count("FileAccess.get_sha256(path).to_lower()") == 1
