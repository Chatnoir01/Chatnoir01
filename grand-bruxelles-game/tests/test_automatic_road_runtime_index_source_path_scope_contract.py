from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RUNTIME = ROOT / "game" / "scripts" / "automatic_road_direct_spawn.gd"


def _source_path_helper() -> str:
    text = RUNTIME.read_text(encoding="utf-8")
    start = text.index("func _canonical_runtime_source_path(raw_path: Variant) -> String:")
    end = text.index("\nfunc _canonical_sha256", start)
    return text[start:end]


def test_runtime_index_source_paths_are_confined_to_canonical_osm_game_documents() -> None:
    body = _source_path_helper()

    osm_root_guard = 'if not source_path.begins_with("data/osm/"):'
    game_json_guard = 'if not source_path.ends_with(".game.json"):'

    assert osm_root_guard in body, (
        "runtime-index source paths must be confined to the canonical data/osm source root"
    )
    assert game_json_guard in body, (
        "runtime-index source paths must be confined to canonical .game.json source documents"
    )
    assert body.count(osm_root_guard) == 1, "OSM source-root confinement must have one canonical guard"
    assert body.count(game_json_guard) == 1, "source-document suffix confinement must have one canonical guard"

    raw_backslash_guard = 'if raw_source_path.contains("\\\\"):'
    raw_res_guard = 'if raw_source_path.begins_with("res://"):'
    nfc_guard = 'if raw_source_path != raw_source_path.unicode_normalize(String.UNICODE_NORMALIZATION_NFC):'
    segment_loop = 'for segment: String in segments:'
    segment_rejection = 'if segment.is_empty() or segment == "." or segment == ".." or segment.contains(":"):'
    control_loop = 'for codepoint: int in source_path.to_utf32_buffer():'
    control_rejection = (
        'if codepoint < 32 or codepoint == 127 or (codepoint >= 128 and codepoint <= 159) '
        'or codepoint == 8203 or codepoint == 8288 or codepoint == 65279 '
        'or codepoint == 8232 or codepoint == 8233 or (codepoint >= 8234 and codepoint <= 8238) '
        'or (codepoint >= 8294 and codepoint <= 8297) or (codepoint >= 917504 and codepoint <= 917631):'
    )
    final_return = 'return "res://" + "/".join(segments)'
    for marker in (
        raw_backslash_guard,
        raw_res_guard,
        nfc_guard,
        segment_loop,
        segment_rejection,
        control_loop,
        control_rejection,
        osm_root_guard,
        game_json_guard,
        final_return,
    ):
        assert marker in body, f"missing canonical source-path normalization marker: {marker}"
        assert body.count(marker) == 1, f"source-path normalization marker must be unique: {marker}"

    assert (
        body.index(raw_backslash_guard)
        < body.index(raw_res_guard)
        < body.index(nfc_guard)
        < body.index(segment_loop)
        < body.index(segment_rejection)
        < body.index(control_loop)
        < body.index(control_rejection)
        < body.index(osm_root_guard)
        < body.index(game_json_guard)
        < body.index(final_return)
    ), (
        "source scope must reject alternate backslash/raw res:// spellings and non-NFC paths before traversal/control checks, "
        "then enforce the canonical OSM .game.json scope"
    )

    assert 'source_path = source_path.trim_prefix("res://")' not in body, (
        "runtime-index source descriptors must have one canonical raw spelling; res:// is an internal normalized form only"
    )


def test_runtime_index_source_paths_reject_invisible_format_spoofing() -> None:
    body = _source_path_helper()
    for codepoint, label in ((8203, "ZERO WIDTH SPACE"), (8288, "WORD JOINER"), (65279, "ZERO WIDTH NO-BREAK SPACE/BOM")):
        assert f"codepoint == {codepoint}" in body, f"missing fail-closed rejection for {label} U+{codepoint:04X}"


def test_runtime_index_source_paths_reject_bidi_reordering_controls() -> None:
    body = _source_path_helper()
    assert "(codepoint >= 8234 and codepoint <= 8238)" in body, (
        "runtime-index source paths must reject U+202A..U+202E bidi embedding/override controls"
    )
    assert "(codepoint >= 8294 and codepoint <= 8297)" in body, (
        "runtime-index source paths must reject U+2066..U+2069 bidi isolate controls"
    )


def test_runtime_index_source_paths_reject_unicode_tag_controls() -> None:
    body = _source_path_helper()
    assert "(codepoint >= 917504 and codepoint <= 917631)" in body, (
        "runtime-index source paths must reject U+E0000..U+E007F Unicode TAG controls"
    )


def test_runtime_index_source_paths_reject_control_and_line_separator_classes() -> None:
    body = _source_path_helper()
    for marker, label in (
        ("codepoint < 32", "C0 controls"),
        ("codepoint == 127", "DEL"),
        ("(codepoint >= 128 and codepoint <= 159)", "C1 controls"),
        ("codepoint == 8232", "LINE SEPARATOR U+2028"),
        ("codepoint == 8233", "PARAGRAPH SEPARATOR U+2029"),
    ):
        assert marker in body, f"missing fail-closed rejection for {label}"


def test_runtime_index_source_paths_reject_slash_confusables() -> None:
    body = _source_path_helper()
    # These NFC-stable characters are visually slash-like but are not path separators.
    # A descriptor such as data/osm/foo∕bar.game.json can otherwise pass the ASCII
    # root/suffix checks while rendering deceptively like a nested canonical path.
    for codepoint, label in (
        (8260, "FRACTION SLASH U+2044"),
        (8725, "DIVISION SLASH U+2215"),
        (65295, "FULLWIDTH SOLIDUS U+FF0F"),
    ):
        assert f"codepoint == {codepoint}" in body, f"missing fail-closed rejection for {label}"


def test_runtime_index_source_paths_reject_reverse_solidus_confusables() -> None:
    body = _source_path_helper()
    # Keep the source-path grammar ASCII-exact. These NFC-stable reverse-solidus
    # lookalikes can make a flat filename look like a Windows-style nested path
    # in review/log surfaces while remaining different bytes to the loader.
    for codepoint, label in (
        (10741, "REVERSE SOLIDUS OPERATOR U+29F5"),
        (65340, "FULLWIDTH REVERSE SOLIDUS U+FF3C"),
    ):
        assert f"codepoint == {codepoint}" in body, f"missing fail-closed rejection for {label}"
