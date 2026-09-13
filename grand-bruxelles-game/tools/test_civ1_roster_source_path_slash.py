#!/usr/bin/env python3
from __future__ import annotations
import hashlib, struct, tempfile
from pathlib import Path
from civ1_roster_registration_truth import validate_entry


def minimal_glb():
    payload=b"{}  "
    total=20+len(payload)
    return struct.pack("<4sII",b"glTF",2,total)+struct.pack("<I4s",len(payload),b"JSON")+payload


def candidate(path,sha,source):
    return {"asset_path":path,"role":"civilian","sha256":sha,"source_url":source,"license":"CC0-1.0"}


def main():
    with tempfile.TemporaryDirectory() as td:
        root=Path(td)
        rel="grand-bruxelles-game/assets/characters/civilian_fixture.glb"
        asset=root/rel
        asset.parent.mkdir(parents=True)
        asset.write_bytes(minimal_glb())
        sha=hashlib.sha256(asset.read_bytes()).hexdigest()

        canonical=validate_entry(candidate(rel,sha,"https://example.invalid/source/civilian.glb"),root)
        assert canonical["roster_eligible"] is True

        for source in (
            "https://example.invalid//source/civilian.glb",
            "https://example.invalid/source//civilian.glb",
            "https://example.invalid/source/civilian.glb//",
        ):
            result=validate_entry(candidate(rel,sha,source),root)
            assert "source_url_not_canonical" in result["blocking_reasons"], (source,result)
            assert result["roster_eligible"] is False

    print("CIV1_ROSTER_SOURCE_PATH_SLASH_RED_GREEN")


if __name__=="__main__":
    main()
