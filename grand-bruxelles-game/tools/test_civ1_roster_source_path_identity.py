#!/usr/bin/env python3
from __future__ import annotations

import tempfile
import unicodedata
from pathlib import Path

from civ1_roster_source_readiness import _source_file


def main() -> None:
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        canonical = "assets/characters/civilians/civ1/source/café.glb"
        assert _source_file(root, canonical) is not None

        ambiguous = (
            " assets/characters/civilians/civ1/source/body.glb",
            "assets/characters/civilians/civ1/source/body.glb ",
            "assets/characters/civilians/civ1/source/body\n.glb",
            "assets/characters/civilians/civ1/source/body\u200b.glb",
            unicodedata.normalize("NFD", canonical),
            "assets/characters/civilians/civ1/source/body.glb/",
            "assets/characters/civilians/civ1/source/body.glb/.",
            "assets/characters/civilians/civ1/source/body\u00a0variant.glb",
            "assets/characters/civilians/civ1/source/body\u2028variant.glb",
            "assets/characters/civilians/civ1/source/body\u2029variant.glb",
            "assets/characters/civilians/civ1/source/body./variant.glb",
            "assets/characters/civilians/civ1/source/CON.glb",
            "assets/characters/civilians/civ1/source/body?.glb",
            "assets/characters/civilians/civ1/source/body*.glb",
            "assets/characters/civilians/civ1/source/body|variant.glb",
            "assets/characters/civilians/civ1/source/body<variant>.glb",
            'assets/characters/civilians/civ1/source/body"variant.glb',
        )
        for source_path in ambiguous:
            assert _source_file(root, source_path) is None, (
                f"ambiguous source identity must fail closed: {source_path!r}"
            )

    print("CIV1_ROSTER_SOURCE_PATH_IDENTITY_GREEN")


if __name__ == "__main__":
    main()
