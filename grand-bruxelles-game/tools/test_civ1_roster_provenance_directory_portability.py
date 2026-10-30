#!/usr/bin/env python3
from __future__ import annotations

from civ1_roster_upstream_basename_identity import mismatches

SOURCE = "assets/characters/civilians/civ1/source/body.glb"


def status(upstream: str):
    return {"source_manifest": {SOURCE: {"upstream_path": upstream}}}


def main() -> None:
    assert mismatches(status("godot_project/body.glb")) == []
    for bad in (
        "CON/body.glb",
        "godot_project/AUX/body.glb",
        "godot_project/folder./body.glb",
        "godot_project/folder /body.glb",
        "godot_project/bad?dir/body.glb",
        "godot_project/cafe\u0301/body.glb",
        "godot_project/" + ("a" * 256) + "/body.glb",
        "godot_project/" + ("😀" * 128) + "/body.glb",
    ):
        assert mismatches(status(bad)), f"nonportable directory segment {bad!r} must fail closed"

    # Win32's component limit is 255 UTF-16 code units, not 255 UTF-8 bytes.
    # A 100-emoji NFC directory is 200 UTF-16 units (portable) despite being
    # 400 UTF-8 bytes; the old byte-count gate incorrectly rejected it.
    assert mismatches(status("godot_project/" + ("😀" * 100) + "/body.glb")) == [], (
        "portable non-BMP component within the Win32 UTF-16 limit must remain valid"
    )

    bad_source = "assets/characters/civilians/CON/source/body.glb"
    assert mismatches({"source_manifest": {bad_source: {"upstream_path": "godot_project/body.glb"}}})

    directory_aliases = {
        "source_manifest": {
            "assets/characters/civilians/civ1/source/body.glb": {"upstream_path": "Vendor/Body/body.glb"},
            "assets/characters/civilians/CIV1/source/body.glb": {"upstream_path": "vendor/Body/body.glb"},
        }
    }
    assert mismatches(directory_aliases), "directory case aliases must fail closed"

    distinct = {
        "source_manifest": {
            "assets/characters/civilians/civ1/source/body.glb": {"upstream_path": "vendor/body/body.glb"},
            "assets/characters/civilians/civ1/source/coat.glb": {"upstream_path": "vendor/coat/coat.glb"},
        }
    }
    assert mismatches(distinct) == [], "distinct portable CIV-1 paths must remain valid"
    print("CIV1_PROVENANCE_DIRECTORY_PORTABILITY_REGRESSION_GREEN")


if __name__ == "__main__":
    main()
