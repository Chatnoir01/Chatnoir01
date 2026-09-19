#!/usr/bin/env python3
from __future__ import annotations
import tempfile
from pathlib import Path
from civ1_roster_source_readiness import _load_strict_json, registry_consistent


SCHEMA = "grand-bruxelles-civ1-roster-registry-v1"


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

        for overflow in ("1e309", "-1e309"):
            path.write_text('{"schema":"grand-bruxelles-civ1-roster-registry-v1","entries":[],"metadata":' + overflow + '}', encoding="utf-8")
            try:
                _load_strict_json(path)
            except ValueError:
                pass
            else:
                raise AssertionError(f"readiness registry must reject decoded non-finite float {overflow}")

        assert not registry_consistent(None)
        assert not registry_consistent([])
        assert not registry_consistent({})
        assert not registry_consistent({"schema":"wrong","entries":[]})
        assert not registry_consistent({"schema":SCHEMA,"entries":{}})
        assert not registry_consistent({"schema":SCHEMA,"entries":[None]})
        assert not registry_consistent({"schema":SCHEMA,"entries":[{}]})
        assert not registry_consistent({"schema":SCHEMA,"entries":[{"asset_path":7}]})
        assert not registry_consistent({"schema":SCHEMA,"entries":[{"asset_path":""}]})
        assert not registry_consistent({"schema":SCHEMA,"entries":[{"asset_path":"grand-bruxelles-game\\assets\\characters\\civilians\\civ1\\civ1.glb"}]})
        assert not registry_consistent({"schema":SCHEMA,"entries":[{"asset_path":"/grand-bruxelles-game/assets/characters/civilians/civ1/civ1.glb"}]})
        assert not registry_consistent({"schema":SCHEMA,"entries":[{"asset_path":"C:/grand-bruxelles-game/assets/characters/civilians/civ1/civ1.glb"}]})
        assert not registry_consistent({"schema":SCHEMA,"entries":[{"asset_path":"grand-bruxelles-game/assets/characters/civilians/civ1/civ1:alias.glb"}]})
        assert not registry_consistent({"schema":SCHEMA,"entries":[{"asset_path":"grand-bruxelles-game/assets/characters/civilians/civ1/../civ1.glb"}]})
        assert not registry_consistent({"schema":SCHEMA,"entries":[{"asset_path":"grand-bruxelles-game/assets//characters/civilians/civ1/civ1.glb"}]})
        assert not registry_consistent({"schema":SCHEMA,"entries":[{"asset_path":"."}]})
        assert not registry_consistent({"schema":SCHEMA,"entries":[{"asset_path":"grand-bruxelles-game/assets/characters/civilians/civ1/"}]})
        assert not registry_consistent({"schema":SCHEMA,"entries":[{"asset_path":"grand-bruxelles-game/assets/characters/civilians/civ1/civ1.glb\u0000alias"}]})
        assert not registry_consistent({"schema":SCHEMA,"entries":[{"asset_path":" grand-bruxelles-game/assets/characters/civilians/civ1/civ1.glb"}]})
        assert not registry_consistent({"schema":SCHEMA,"entries":[{"asset_path":"grand-bruxelles-game/assets/characters/civilians/civ1/civ1.glb "}]})
        assert not registry_consistent({"schema":SCHEMA,"entries":[{"asset_path":"grand-bruxelles-game/assets/characters/civilians/civ1/civ1.glb\nshadow"}]})
        duplicate = {"schema":SCHEMA,"entries":[{"asset_path":"grand-bruxelles-game/assets/characters/civilians/civ1/civ1.glb"},{"asset_path":"grand-bruxelles-game/assets/characters/civilians/civ1/civ1.glb"}]}
        assert not registry_consistent(duplicate), "duplicate asset identity must fail closed"
        case_alias = {"schema":SCHEMA,"entries":[{"asset_path":"grand-bruxelles-game/assets/characters/civilians/civ1/Civilian.glb"},{"asset_path":"grand-bruxelles-game/assets/characters/civilians/civ1/civilian.glb"}]}
        assert not registry_consistent(case_alias), "Windows case-insensitive asset alias must fail closed"

        valid = {"schema":SCHEMA,"entries":[]}
        assert registry_consistent(valid)
        assert registry_consistent({"schema":SCHEMA,"entries":[{"asset_path":"grand-bruxelles-game/assets/characters/civilians/other.glb"}]})
        path.write_text('{"schema":"grand-bruxelles-civ1-roster-registry-v1","entries":[]}', encoding="utf-8")
        loaded = _load_strict_json(path)
        assert loaded["entries"] == []
    print("CIV1_ROSTER_READINESS_REGISTRY_JSON_GREEN")


if __name__ == "__main__":
    main()
