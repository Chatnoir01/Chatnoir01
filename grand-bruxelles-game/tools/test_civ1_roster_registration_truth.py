#!/usr/bin/env python3
from __future__ import annotations
import hashlib, struct, tempfile
from pathlib import Path
from civ1_roster_registration_truth import build_payload, validate_entry

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
        asset=root/rel; asset.parent.mkdir(parents=True); asset.write_bytes(minimal_glb())
        sha=hashlib.sha256(asset.read_bytes()).hexdigest()
        good=validate_entry(candidate(rel,sha,"https://xn--exmple-cua.invalid/source/civilian.glb"),root)
        assert good["roster_eligible"] is True, good
        for source in (
            "https://xn--abc.invalid/source/civilian.glb",
            "https://xn--a.invalid/source/civilian.glb",
            "https://xn--0.invalid/source/civilian.glb",
            "https://xn--invalid-.invalid/source/civilian.glb",
        ):
            bad=validate_entry(candidate(rel,sha,source),root)
            assert "source_url_idna_label_invalid" in bad["blocking_reasons"], (source,bad)
            assert bad["roster_eligible"] is False
        for source,reason in (
            ("https://example.invalid/source/civilian.glb?","source_url_query_forbidden"),
            ("https://example.invalid/source/civilian.glb#","source_url_fragment_forbidden"),
            ("https://example.invalid/source/civilian.glb?x=1","source_url_query_forbidden"),
            ("https://example.invalid/source/civilian.glb#frag","source_url_fragment_forbidden"),
            ("https://example.invalid/source/civilian.glb?#","source_url_query_forbidden"),
        ):
            bad=validate_entry(candidate(rel,sha,source),root)
            assert reason in bad["blocking_reasons"], (source,bad)
            assert bad["roster_eligible"] is False
        payload=build_payload({"schema":"grand-bruxelles-civ1-roster-registry-v1","entries":[]},root)
        assert payload["schema"]=="grand-bruxelles-civ1-roster-registration-truth-v36"
        assert payload["blocking_reasons"]==[]
        assert payload["registration_count"]==0 and payload["eligible_count"]==0
        assert payload["source_url_idna_alabel_roundtrip_required"] is True
        assert payload["source_url_query_forbidden"] is True
        assert payload["source_url_fragment_forbidden"] is True
        assert payload["source_url_empty_delimiters_forbidden"] is True
        assert payload["unique_source_provenance_required"] is True
        assert payload["roster_authorized"] is False
        assert payload["runtime_authorized"] is False
        assert payload["visual_approval_claimed"] is False
    print("CIV1_ROSTER_REGISTRATION_TRUTH_V36_GREEN")
if __name__=="__main__": main()
