#!/usr/bin/env python3
from __future__ import annotations

from civ1_roster_source_readiness import _canonical_path_text


def main() -> None:
    good = (
        "assets/characters/civilians/civ1/source/body.glb",
        "vendor/console/body.glb",
    )
    for path in good:
        assert _canonical_path_text(path) == path, f"portable control unexpectedly rejected: {path!r}"

    bad = (
        "assets/characters/civilians/civ1/source/CONIN$",
        "assets/characters/civilians/civ1/source/conout$.glb",
        "vendor/CONIN$/body.glb",
        "vendor/conout$.cache/body.glb",
    )
    for path in bad:
        assert _canonical_path_text(path) is None, f"Win32 console device alias must fail closed: {path!r}"

    print("CIV1_READINESS_WINDOWS_CONSOLE_DEVICE_REGRESSION_GREEN")


if __name__ == "__main__":
    main()
