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

        assert not registry_consistent(None), "null registry must fail closed"
        assert not registry_consistent([]), "array registry must fail closed"
        assert not registry_consistent({}), "missing schema/entries must fail closed"
        assert not registry_consistent({"schema":"wrong","entries":[]}), "wrong schema must fail closed"
        assert not registry_consistent({"schema":SCHEMA,"entries":{}}), "non-list entries must fail closed"
        assert not registry_consistent({"schema":SCHEMA,"entries":[None]}), "non-object entry must fail closed"
        assert not registry_consistent({"schema":SCHEMA,"entries":[{}]}), "entry without asset_path must fail closed"
        assert not registry_consistent({"schema":SCHEMA,"entries":[{"asset_path":7}]}), "non-string asset_path must fail closed"
        assert not registry_consistent({"schema":SCHEMA,"entries":[{"asset_path":""}]}), "empty asset_path must fail closed"
        assert not registry_consistent({"schema":SCHEMA,"entries":[{"asset_path":"grand-bruxelles-game\\assets\\characters\\civilians\\civ1\\civ1.glb"}]}), "backslash asset_path must fail closed"
        assert not registry_consistent({"schema":SCHEMA,"entries":[{"asset_path":"/grand-bruxelles-game/assets/characters/civilians/civ1/civ1.glb"}]}), "absolute asset_path must fail closed"
        assert not registry_consistent({"schema":SCHEMA,"entries":[{"asset_path":"C:/grand-bruxelles-game/assets/characters/civilians/civ1/civ1.glb"}]}), "Windows drive-like asset_path must fail closed"
        assert not registry_consistent({"schema":SCHEMA,"entries":[{"asset_path":"grand-bruxelles-game/assets/characters/civilians/civ1/civ1:alias.glb"}]}), "colon-bearing asset identity must fail closed for Windows portability"
        assert not registry_consistent({"schema":SCHEMA,"entries":[{"asset_path":"grand-bruxelles-game/assets/characters/civilians/civ1/../civ1.glb"}]}), "parent traversal asset_path must fail closed"
        assert not registry_consistent({"schema":SCHEMA,"entries":[{"asset_path":"grand-bruxelles-game/assets//characters/civilians/civ1/civ1.glb"}]}), "non-canonical asset_path must fail closed"
        assert not registry_consistent({"schema":SCHEMA,"entries":[{"asset_path":"."}]}), "dot identity must fail closed"
        assert not registry_consistent({"schema":SCHEMA,"entries":[{"asset_path":"grand-bruxelles-game/assets/characters/civilians/civ1/"}]}), "directory-like identity must fail closed"
        assert not registry_consistent({"schema":SCHEMA,"entries":[{"asset_path":"grand-bruxelles-game/assets/characters/civilians/civ1/civ1.glb\u0000alias"}]}), "NUL identity must fail closed"
        assert not registry_consistent({"schema":SCHEMA,"entries":[{"asset_path":" grand-bruxelles-game/assets/characters/civilians/civ1/civ1.glb"}]}), "leading whitespace identity must fail closed"
        assert not registry_consistent({"schema":SCHEMA,"entries":[{"asset_path":"grand-bruxelles-game/assets/characters/civilians/civ1/civ1.glb "}]}), "trailing whitespace identity must fail closed"
        assert not registry_consistent({"schema":SCHEMA,"entries":[{"asset_path":"grand-bruxelles-game/assets/characters/civilians/civ1/civ1.glb\nshadow"}]}), "control-character identity must fail closed"
        duplicate = {"schema":SCHEMA,"entries":[{"asset_path":"grand-bruxelles-game/assets/characters/civilians/civ1/civ1.glb"},{"asset_path":"grand-bruxelles-game/assets/characters/civilians/civ1/civ1.glb"}]}
        assert not registry_consistent(duplicate), "duplicate asset identity must fail closed"

        valid = {"schema":SCHEMA,"entries":[]}
        assert registry_consistent(valid)
        assert registry_consistent({"schema":SCHEMA,"entries":[{"asset_path":"grand-bruxelles-game/assets/characters/civilians/other.glb"}]})
        path.write_text('{"schema":"grand-bruxelles-civ1-roster-registry-v1","entries":[]}', encoding="utf-8")
        loaded = _load_strict_json(path)
        assert loaded["entries"] == []
    print("CIV1_ROSTER_READINESS_REGISTRY_JSON_GREEN")


if __name__ == "__main__":
    main()
