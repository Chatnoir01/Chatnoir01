#!/usr/bin/env python3
from __future__ import annotations
import hashlib, json, struct, tempfile
from pathlib import Path
from civ1_roster_registration_truth import validate_entry

def minimal_glb(payload=b"{}  "):
    total=20+len(payload)
    return struct.pack("<4sII",b"glTF",2,total)+struct.pack("<I4s",len(payload),b"JSON")+payload

def main():
    with tempfile.TemporaryDirectory() as td:
        root=Path(td)
        rel="grand-bruxelles-game/assets/characters/civilians/civ1/civ1.glb"
        asset=root/rel; asset.parent.mkdir(parents=True); asset.write_bytes(minimal_glb())
        status_path=asset.parent/"source_status.json"
        status_path.write_text(json.dumps({"production_authorized":False,"activation_ready":False,"source_package_present":False,"runtime_package_present":False,"blocker":"source_not_ready"}),encoding="utf-8")
        sha=hashlib.sha256(asset.read_bytes()).hexdigest()
        entry={"asset_path":rel,"role":"civilian","sha256":sha,"source_url":"https://assets.character-fixtures.com/source/civ1.glb","license":"CC0-1.0"}
        result=validate_entry(entry,root)
        assert "civ1_source_status_not_ready" in result["blocking_reasons"], result
        assert result["roster_eligible"] is False, result
    print("CIV1_ROSTER_SOURCE_READINESS_GREEN")
if __name__=="__main__": main()
