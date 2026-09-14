#!/usr/bin/env python3
from __future__ import annotations
import json, tempfile
from pathlib import Path
from civ1_roster_source_readiness import blocking_entries, source_ready

def main():
    with tempfile.TemporaryDirectory() as td:
        root=Path(td)
        status=root/"grand-bruxelles-game/assets/characters/civilians/civ1/source_status.json"
        status.parent.mkdir(parents=True)
        blocked_status={"production_authorized":False,"activation_ready":False,"source_package_present":False,"blocker":"source_not_ready"}
        status.write_text(json.dumps(blocked_status),encoding="utf-8")
        registry={"schema":"grand-bruxelles-civ1-roster-registry-v1","entries":[{"asset_path":"grand-bruxelles-game/assets/characters/civilians/civ1/civ1.glb"}]}
        assert source_ready(root) is False
        assert blocking_entries(registry,root)==["grand-bruxelles-game/assets/characters/civilians/civ1/civ1.glb"]
        ready_status={"production_authorized":True,"activation_ready":True,"source_package_present":True}
        status.write_text(json.dumps(ready_status),encoding="utf-8")
        assert source_ready(root) is True
        assert blocking_entries(registry,root)==[]
    print("CIV1_ROSTER_SOURCE_READINESS_GREEN")
if __name__=="__main__": main()
