#!/usr/bin/env python3
from __future__ import annotations
import tempfile
from pathlib import Path
from civ1_roster_source_readiness import _load_strict_json


def main() -> None:
    with tempfile.TemporaryDirectory() as td:
        path = Path(td) / "registry.json"
        path.write_text('{"schema":"grand-bruxelles-civ1-roster-registry-v1","entries":[],"entries":[{"asset_path":"grand-bruxelles-game/assets/characters/civilians/civ1/civ1.glb"}]}', encoding="utf-8")
        try:
            _load_strict_json(path)
        except ValueError:
            pass
        else:
            raise AssertionError("readiness registry must reject duplicate JSON keys")

        path.write_text('{"schema":"grand-bruxelles-civ1-roster-registry-v1","entries":[],"metadata":NaN}', encoding="utf-8")
        try:
            _load_strict_json(path)
        except ValueError:
            pass
        else:
            raise AssertionError("readiness registry must reject non-standard JSON constants")

        path.write_text('{"schema":"grand-bruxelles-civ1-roster-registry-v1","entries":[]}', encoding="utf-8")
        loaded = _load_strict_json(path)
        assert loaded["entries"] == []
    print("CIV1_ROSTER_READINESS_REGISTRY_JSON_GREEN")


if __name__ == "__main__":
    main()
