#!/usr/bin/env python3
from __future__ import annotations

import tempfile
from pathlib import Path

from civ1_roster_source_readiness import blocking_entries

SCHEMA = "grand-bruxelles-civ1-roster-registry-v1"


def registry(path: str) -> dict:
    return {"schema": SCHEMA, "entries": [{"asset_path": path}]}


def main() -> None:
    # No readiness status exists in this isolated repo root, so CIV-1 assets must
    # fail closed. The assertions below pin the namespace boundary itself.
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        civ1_assets = (
            "grand-bruxelles-game/assets/characters/civilians/civ1/civ1.glb",
            "GRAND-BRUXELLES-GAME/ASSETS/CHARACTERS/CIVILIANS/CIV1/LOD/CIV1_LOD1.GLB",
            "Grand-Bruxelles-Game/Assets/Characters/Civilians/Civ1/Animations/walk.glb",
        )
        for asset_path in civ1_assets:
            assert blocking_entries(registry(asset_path), root) == [asset_path], asset_path

        non_assets = (
            "GRAND-BRUXELLES-GAME/ASSETS/CHARACTERS/CIVILIANS/CIV1",
            "grand-bruxelles-game/assets/characters/civilians/civ10/civ10.glb",
            "grand-bruxelles-game/assets/characters/civilians/civ1-old/civ1.glb",
            "grand-bruxelles-game/assets/characters/civilians/civ1_backup/civ1.glb",
            "grand-bruxelles-game/assets/characters/civilians/civ/civ1.glb",
        )
        for asset_path in non_assets:
            assert blocking_entries(registry(asset_path), root) == [], asset_path

        # Non-canonical separator spelling must never become a second identity
        # that can bypass or alias the canonical POSIX roster namespace.
        invalid = registry(r"grand-bruxelles-game\assets\characters\civilians\civ1\civ1.glb")
        try:
            blocking_entries(invalid, root)
        except ValueError:
            pass
        else:
            raise AssertionError("backslash roster identity must be rejected")

    print("CIV1_ROSTER_NAMESPACE_BOUNDARY_GREEN")


if __name__ == "__main__":
    main()
