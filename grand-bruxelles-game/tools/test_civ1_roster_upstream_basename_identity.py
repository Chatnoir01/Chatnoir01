#!/usr/bin/env python3
from __future__ import annotations

import tempfile
from pathlib import Path

from civ1_roster_upstream_basename_identity import DuplicateJSONKeyError, InvalidUTF8StatusError, NonStandardJSONConstantError, load_status, mismatches


def main() -> None:
    source = "assets/characters/civilians/civ1/source/body.glb"
    good = {"source_manifest": {source: {"upstream_path": "godot_project/body.glb"}}}
    assert mismatches(good) == []
    assert mismatches({"source_manifest": {source: {"upstream_path": "godot_project/other.glb"}}})
    assert mismatches({"source_manifest": {source: {"upstream_path": "godot_project/BODY.glb"}}})
    assert mismatches({"source_manifest": {source: {}}})

    for escaped_source in (
        "assets/characters/civilians/civ2/source/body.glb",
        "assets/characters/player/body.glb",
        "tmp/body.glb",
    ):
        assert mismatches({"source_manifest": {escaped_source: {"upstream_path": "godot_project/body.glb"}}}), f"out-of-root source destination {escaped_source!r} must fail closed"

    case_collision = {"source_manifest": {
        "assets/characters/civilians/civ1/source/body.glb": {"upstream_path": "godot_project/body.glb"},
        "assets/characters/civilians/civ1/source/BODY.glb": {"upstream_path": "godot_project/BODY.glb"},
    }}
    assert mismatches(case_collision), "Windows case-insensitive filename aliases must fail closed"

    for noncanonical in (
        "/godot_project/body.glb", "//server/share/body.glb", "C:/godot_project/body.glb", "c:/godot_project/body.glb",
        "godot_project/../body.glb", "godot_project/./body.glb", "godot_project//body.glb",
        "godot_project\\body.glb", "godot_project\\nested/body.glb",
    ):
        assert mismatches({"source_manifest": {source: {"upstream_path": noncanonical}}}), f"non-canonical provenance path {noncanonical!r} must fail closed"

    for rooted_source in ("C:/assets/characters/civilians/civ1/source/body.glb", "//server/share/body.glb"):
        assert mismatches({"source_manifest": {rooted_source: {"upstream_path": "godot_project/body.glb"}}}), f"rooted source provenance {rooted_source!r} must fail closed"

    windows_source = "assets\\characters\\civilians\\civ1\\source\\body.glb"
    assert mismatches({"source_manifest": {windows_source: {"upstream_path": "godot_project/body.glb"}}}), "Windows separators in source provenance must fail closed"

    nfc_source = "assets/characters/civilians/civ1/source/caf\u00e9.glb"
    nfd_upstream = "godot_project/cafe\u0301.glb"
    assert mismatches({"source_manifest": {nfc_source: {"upstream_path": nfd_upstream}}})

    hidden = "body\u200b.glb"
    assert mismatches({"source_manifest": {f"assets/characters/civilians/civ1/source/{hidden}": {"upstream_path": f"godot_project/{hidden}"}}})

    for aliased_leaf in ("body.glb ", "body.glb."):
        assert mismatches({"source_manifest": {f"assets/characters/civilians/civ1/source/{aliased_leaf}": {"upstream_path": f"godot_project/{aliased_leaf}"}}})

    for normalized_expression in ("godot_project/body.glb/", "godot_project/body.glb/."):
        assert mismatches({"source_manifest": {source: {"upstream_path": normalized_expression}}})

    for reserved_leaf in ("CON.glb", "nul.obj", "COM1.glb", "lpt9.fbx", "COM\u00b9.glb", "lpt\u00b2.fbx", "COM\u00b3.obj", "CONIN$", "conout$.glb"):
        status = {"source_manifest": {f"assets/characters/civilians/civ1/source/{reserved_leaf}": {"upstream_path": f"godot_project/{reserved_leaf}"}}}
        assert mismatches(status), f"Windows device alias {reserved_leaf!r} must fail closed"

    for invalid_char in '<>:"\\|?*':
        invalid_leaf = f"body{invalid_char}alt.glb"
        status = {"source_manifest": {f"assets/characters/civilians/civ1/source/{invalid_leaf}": {"upstream_path": f"godot_project/{invalid_leaf}"}}}
        assert mismatches(status)

    # Win32's component limit is measured in UTF-16 code units, not UTF-8 bytes.
    # A Unicode name may exceed 255 UTF-8 bytes while remaining a valid Win32
    # component; conversely astral characters consume two UTF-16 units each.
    unicode_portable_leaf = "\U0001f642" * 100 + ".glb"
    unicode_portable_status = {"source_manifest": {f"assets/characters/civilians/civ1/source/{unicode_portable_leaf}": {"upstream_path": f"godot_project/{unicode_portable_leaf}"}}}
    assert len(unicode_portable_leaf.encode("utf-16-le")) // 2 == 204
    assert len(unicode_portable_leaf.encode("utf-8")) > 255
    assert mismatches(unicode_portable_status) == [], "portable Unicode component must not be rejected by UTF-8 byte length"

    overlong_leaf = "\U0001f642" * 126 + ".glb"
    overlong_status = {"source_manifest": {f"assets/characters/civilians/civ1/source/{overlong_leaf}": {"upstream_path": f"godot_project/{overlong_leaf}"}}}
    assert len(overlong_leaf.encode("utf-16-le")) // 2 == 256
    assert mismatches(overlong_status), "256 UTF-16-unit Win32 component must fail closed"

    duplicate = ('{"source_manifest": {' f'"{source}": {{"upstream_path": "godot_project/other.glb"}}, ' f'"{source}": {{"upstream_path": "godot_project/body.glb"}}' '}}')
    with tempfile.TemporaryDirectory() as tmp:
        status_path = Path(tmp) / "source_status.json"
        status_path.write_text(duplicate, encoding="utf-8")
        try:
            load_status(status_path)
        except DuplicateJSONKeyError:
            pass
        else:
            raise AssertionError("duplicate provenance JSON keys must fail closed")

        for constant in ("NaN", "Infinity", "-Infinity"):
            status_path.write_text('{"source_manifest": {' f'"{source}": {{"upstream_path": "godot_project/body.glb", "probe": {constant}}}' '}}', encoding="utf-8")
            try:
                load_status(status_path)
            except NonStandardJSONConstantError:
                pass
            else:
                raise AssertionError(f"non-standard JSON constant {constant} must fail closed")

        status_path.write_bytes(b'{"source_manifest":{"body.glb":{"upstream_path":"body' + b'\xff' + b'.glb"}}}')
        try:
            load_status(status_path)
        except InvalidUTF8StatusError as exc:
            assert "invalid UTF-8 at byte" in str(exc)
        else:
            raise AssertionError("malformed UTF-8 provenance bytes must fail closed")

    print("CIV1_UPSTREAM_BASENAME_IDENTITY_REGRESSION_GREEN")


if __name__ == "__main__":
    main()
