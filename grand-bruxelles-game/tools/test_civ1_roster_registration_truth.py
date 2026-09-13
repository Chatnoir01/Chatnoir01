#!/usr/bin/env python3
from __future__ import annotations

import hashlib, json, struct, subprocess, sys, tempfile
from pathlib import Path
from urllib.parse import urlsplit
from civ1_roster_registration_truth import PLAYER_ASSET, build_payload, validate_entry

def entry(path, sha, role="civilian", source_url="https://example.invalid/source"):
    return {"asset_path": path, "role": role, "sha256": sha, "source_url": source_url, "license": "CC0-1.0"}

def minimal_glb():
    j=b"{}  "; total=12+8+len(j)
    return struct.pack("<4sII",b"glTF",2,total)+struct.pack("<I4s",len(j),b"JSON")+j

def main():
    with tempfile.TemporaryDirectory() as td:
        root=Path(td); rel="grand-bruxelles-game/assets/characters/civilian_fixture.glb"; asset=root/rel; asset.parent.mkdir(parents=True); asset.write_bytes(minimal_glb()); sha=hashlib.sha256(asset.read_bytes()).hexdigest()
        good=validate_entry(entry(rel,sha),root); assert good["valid"] is True and good["roster_eligible"] is True
        assert "sha256_not_canonical" in validate_entry(entry(rel,sha.upper()),root)["blocking_reasons"]
        spaced=entry(rel,sha); spaced["license"]=" CC0-1.0 "; assert "license_not_canonical" in validate_entry(spaced,root)["blocking_reasons"]
        over=entry(rel,sha); over["runtime_authorized"]=True; assert "unexpected_entry_field:runtime_authorized" in validate_entry(over,root)["blocking_reasons"]
        fake_rel="grand-bruxelles-game/assets/characters/civilian_fake.glb"; fake=root/fake_rel; fake.write_bytes(b"not-a-glb-character"); fake_sha=hashlib.sha256(fake.read_bytes()).hexdigest(); assert "glb_container_invalid" in validate_entry(entry(fake_rel,fake_sha),root)["blocking_reasons"]
        assert "sha256_mismatch" in validate_entry(entry(rel,"0"*64),root)["blocking_reasons"]
        for bad in ("free","custom","royalty-free","public domain"):
            c=entry(rel,sha); c["license"]=bad; assert "license_not_allowed" in validate_entry(c,root)["blocking_reasons"]
        for source,reason in {"https://":"source_url_host_missing","http://example.invalid/source":"source_url_https_required","https://localhost/source":"source_url_localhost_forbidden","https://127.0.0.1/source":"source_url_non_global_ip_forbidden","https://example.invalid/source#claim":"source_url_fragment_forbidden","https://intranet/source":"source_url_single_label_host_forbidden","https://assets.example.invalid./civilian.glb":"source_url_not_canonical"}.items():
            r=validate_entry(entry(rel,sha,source_url=source),root); assert reason in r["blocking_reasons"], (source,r)
        # RED v17: v16 accepts alternate textual spellings because scheme/host comparisons lowercase silently.
        for noncanonical in ("HTTPS://example.invalid/source","https://EXAMPLE.invalid/source"):
            r=validate_entry(entry(rel,sha,source_url=noncanonical),root)
            assert "source_url_not_canonical" in r["blocking_reasons"], (noncanonical,r)
            assert r["roster_eligible"] is False
        player=root/PLAYER_ASSET; player.parent.mkdir(parents=True,exist_ok=True); player.write_bytes(minimal_glb()); psha=hashlib.sha256(player.read_bytes()).hexdigest(); reused=validate_entry(entry(PLAYER_ASSET,psha,"police"),root); assert "player_reuse_forbidden" in reused["blocking_reasons"] and "player_content_reuse_forbidden" in reused["blocking_reasons"]
        canonical=build_payload({"schema":"grand-bruxelles-civ1-roster-registry-v1","entries":[]},root); assert canonical["blocking_reasons"]==[]
        duplicate=root/"duplicate.json"; duplicate.write_text('{"schema":"grand-bruxelles-civ1-roster-registry-v1","entries":[],"entries":[]}',encoding="utf-8"); proc=subprocess.run([sys.executable,str(Path(__file__).with_name("civ1_roster_registration_truth.py")),str(duplicate),"--repo-root",str(root)],text=True,capture_output=True,check=False); assert proc.returncode==2 and "registry_duplicate_json_key:entries" in json.loads(proc.stdout)["blocking_reasons"]
        for token in ("NaN","Infinity","-Infinity"):
            f=root/f"bad_{token.replace('-','m')}.json"; f.write_text(f'{{"schema":"grand-bruxelles-civ1-roster-registry-v1","entries":[{token}]}}',encoding="utf-8"); proc=subprocess.run([sys.executable,str(Path(__file__).with_name("civ1_roster_registration_truth.py")),str(f),"--repo-root",str(root)],text=True,capture_output=True,check=False); assert proc.returncode==2 and f"registry_nonstandard_json_constant:{token}" in json.loads(proc.stdout)["blocking_reasons"]
    print("CIV1_ROSTER_REGISTRATION_TRUTH_V17_GREEN")
if __name__=="__main__": main()
