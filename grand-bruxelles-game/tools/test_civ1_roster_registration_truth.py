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
        asset=root/rel
        asset.parent.mkdir(parents=True)
        asset.write_bytes(minimal_glb())
        sha=hashlib.sha256(asset.read_bytes()).hexdigest()
        good=validate_entry(candidate(rel,sha,"https://example.invalid/source"),root)
        assert good["roster_eligible"] is True
        for source in ("HTTPS://example.invalid/source","https://EXAMPLE.invalid/source","https://assets.example.invalid./source","https://intranet/source"):
            result=validate_entry(candidate(rel,sha,source),root)
            assert "source_url_not_canonical" in result["blocking_reasons"] or "source_url_single_label_host_forbidden" in result["blocking_reasons"]
            assert result["roster_eligible"] is False
        # HTTPS already implies TCP/443. An explicit default port is a second textual
        # representation of the same provenance endpoint and must not be roster-eligible.
        default_port=validate_entry(candidate(rel,sha,"https://example.invalid:443/source"),root)
        assert "source_url_not_canonical" in default_port["blocking_reasons"]
        assert default_port["roster_eligible"] is False
        # A non-default port can designate a distinct HTTPS origin and remains valid.
        nondefault_port=validate_entry(candidate(rel,sha,"https://example.invalid:8443/source"),root)
        assert nondefault_port["roster_eligible"] is True
        # Provenance must be a stable public locator, not an ephemeral/signed/query-param
        # representation that can expire, leak credentials, or multiply spellings.
        queried=validate_entry(candidate(rel,sha,"https://example.invalid/source?token=abc"),root)
        assert "source_url_query_forbidden" in queried["blocking_reasons"]
        assert queried["roster_eligible"] is False
        payload=build_payload({"schema":"grand-bruxelles-civ1-roster-registry-v1","entries":[]},root)
        assert payload["blocking_reasons"]==[]
        assert payload["registration_count"]==0 and payload["eligible_count"]==0
        assert payload["source_url_canonical_scheme_host_case_required"] is True
        assert payload["source_url_default_https_port_forbidden"] is True
        assert payload["source_url_query_forbidden"] is True
    print("CIV1_ROSTER_REGISTRATION_TRUTH_V19_GREEN")
if __name__=="__main__": main()
