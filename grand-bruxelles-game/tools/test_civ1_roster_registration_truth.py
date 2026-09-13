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
        good=validate_entry(candidate(rel,sha,"https://example.invalid/source/~civilian.glb"),root)
        assert good["roster_eligible"] is True
        for source in ("HTTPS://example.invalid/source","https://EXAMPLE.invalid/source","https://assets.example.invalid./source","https://intranet/source"):
            result=validate_entry(candidate(rel,sha,source),root)
            assert "source_url_not_canonical" in result["blocking_reasons"] or "source_url_single_label_host_forbidden" in result["blocking_reasons"]
            assert result["roster_eligible"] is False
        unicode_host=validate_entry(candidate(rel,sha,"https://exämple.invalid/source"),root)
        assert "source_url_non_ascii_host_forbidden" in unicode_host["blocking_reasons"]
        assert unicode_host["roster_eligible"] is False
        for source in ("https://%65xample.invalid/source","https://bad_host.example/source","https://bad-.example/source","https://example..invalid/source"):
            invalid_dns=validate_entry(candidate(rel,sha,source),root)
            assert "source_url_dns_host_invalid" in invalid_dns["blocking_reasons"]
            assert invalid_dns["roster_eligible"] is False
        assert validate_entry(candidate(rel,sha,"https://xn--exmple-cua.invalid/source"),root)["roster_eligible"] is True
        for source in ("https://127.1/source","https://127.0.1/source","https://0177.0.0.1/source","https://0x7f.0.0.1/source","https://2130706433/source"):
            legacy_ip=validate_entry(candidate(rel,sha,source),root)
            assert "source_url_ip_literal_not_canonical" in legacy_ip["blocking_reasons"]
            assert legacy_ip["roster_eligible"] is False
        canonical_loopback=validate_entry(candidate(rel,sha,"https://127.0.0.1/source"),root)
        assert "source_url_non_global_ip_forbidden" in canonical_loopback["blocking_reasons"]
        assert canonical_loopback["roster_eligible"] is False
        canonical_ipv6=validate_entry(candidate(rel,sha,"https://[2606:4700:4700::1111]/source"),root)
        assert canonical_ipv6["roster_eligible"] is True
        expanded_ipv6=validate_entry(candidate(rel,sha,"https://[2606:4700:4700:0000:0000:0000:0000:1111]/source"),root)
        assert "source_url_ip_literal_not_canonical" in expanded_ipv6["blocking_reasons"]
        assert expanded_ipv6["roster_eligible"] is False
        default_port=validate_entry(candidate(rel,sha,"https://example.invalid:443/source"),root)
        assert "source_url_not_canonical" in default_port["blocking_reasons"]
        assert default_port["roster_eligible"] is False
        leading_zero_port=validate_entry(candidate(rel,sha,"https://example.invalid:08443/source"),root)
        assert "source_url_not_canonical" in leading_zero_port["blocking_reasons"]
        assert leading_zero_port["roster_eligible"] is False
        nondefault_port=validate_entry(candidate(rel,sha,"https://example.invalid:8443/source"),root)
        assert nondefault_port["roster_eligible"] is True
        queried=validate_entry(candidate(rel,sha,"https://example.invalid/source?view=detail"),root)
        assert "source_url_query_forbidden" in queried["blocking_reasons"]
        assert queried["roster_eligible"] is False
        for source in ("https://example.invalid/source/%7Ecivilian.glb","https://example.invalid/source/%2fcivilian.glb"):
            encoded=validate_entry(candidate(rel,sha,source),root)
            assert "source_url_not_canonical" in encoded["blocking_reasons"]
            assert encoded["roster_eligible"] is False
        for source in ("https://example.invalid/source/%2Fcivilian.glb","https://example.invalid/source/%5Ccivilian.glb"):
            separator=validate_entry(candidate(rel,sha,source),root)
            assert "source_url_not_canonical" in separator["blocking_reasons"]
            assert separator["roster_eligible"] is False
        for source in ("https://example.invalid/source/./civilian.glb","https://example.invalid/source/../civilian.glb"):
            dotted=validate_entry(candidate(rel,sha,source),root)
            assert "source_url_not_canonical" in dotted["blocking_reasons"]
            assert dotted["roster_eligible"] is False
        for source in ("https://example.invalid//source/civilian.glb","https://example.invalid/source//civilian.glb","https://example.invalid/source/civilian.glb//"):
            duplicate_separator=validate_entry(candidate(rel,sha,source),root)
            assert "source_url_not_canonical" in duplicate_separator["blocking_reasons"]
            assert duplicate_separator["roster_eligible"] is False
        raw_unicode_path=validate_entry(candidate(rel,sha,"https://example.invalid/source/café.glb"),root)
        assert "source_url_non_ascii_path_forbidden" in raw_unicode_path["blocking_reasons"]
        assert raw_unicode_path["roster_eligible"] is False
        utf8_encoded_path=validate_entry(candidate(rel,sha,"https://example.invalid/source/caf%C3%A9.glb"),root)
        assert utf8_encoded_path["roster_eligible"] is True
        for source in ("https://example.invalid/source/%3Fcivilian.glb","https://example.invalid/source/%23civilian.glb","https://example.invalid/source/%25civilian.glb","https://example.invalid/source/%FFcivilian.glb","https://example.invalid/source/%C0%AFcivilian.glb","https://example.invalid/source/cafe%CC%81.glb"):
            ambiguous_octets=validate_entry(candidate(rel,sha,source),root)
            assert "source_url_not_canonical" in ambiguous_octets["blocking_reasons"]
            assert ambiguous_octets["roster_eligible"] is False
        for source in ("https://example.invalid/source/civilian%E2%80%8B.glb","https://example.invalid/source/civilian%E2%80%AE.glb","https://example.invalid/source/civilian%EF%BB%BF.glb"):
            invisible_control=validate_entry(candidate(rel,sha,source),root)
            assert "source_url_not_canonical" in invisible_control["blocking_reasons"]
            assert invisible_control["roster_eligible"] is False
        root_without_slash=validate_entry(candidate(rel,sha,"https://example.invalid"),root)
        assert "source_url_not_canonical" in root_without_slash["blocking_reasons"]
        assert root_without_slash["roster_eligible"] is False
        root_with_slash=validate_entry(candidate(rel,sha,"https://example.invalid/"),root)
        assert root_with_slash["roster_eligible"] is True
        payload=build_payload({"schema":"grand-bruxelles-civ1-roster-registry-v1","entries":[]},root)
        assert payload["schema"]=="grand-bruxelles-civ1-roster-registration-truth-v32"
        assert payload["blocking_reasons"]==[]
        assert payload["registration_count"]==0 and payload["eligible_count"]==0
        assert payload["source_url_canonical_percent_encoding_required"] is True
        assert payload["source_url_percent_encoding_utf8_non_ascii_only_required"] is True
        assert payload["source_url_unicode_nfc_required"] is True
        assert payload["source_url_unicode_control_characters_forbidden"] is True
        assert payload["source_url_encoded_path_separators_forbidden"] is True
        assert payload["source_url_dot_segments_forbidden"] is True
        assert payload["source_url_duplicate_path_separators_forbidden"] is True
        assert payload["source_url_ascii_host_required"] is True
        assert payload["source_url_ascii_path_required"] is True
        assert payload["source_url_canonical_dns_host_required"] is True
        assert payload["source_url_explicit_root_path_required"] is True
        assert payload["source_url_canonical_port_spelling_required"] is True
        assert payload["source_url_canonical_ip_literal_required"] is True
        assert payload["source_url_canonical_ipv6_spelling_required"] is True
    print("CIV1_ROSTER_REGISTRATION_TRUTH_V32_GREEN")
if __name__=="__main__": main()
