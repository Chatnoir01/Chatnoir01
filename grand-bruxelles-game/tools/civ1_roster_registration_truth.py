#!/usr/bin/env python3
from __future__ import annotations
import argparse, hashlib, ipaddress, json, struct
from pathlib import Path, PurePosixPath
from urllib.parse import urlsplit

SCHEMA="grand-bruxelles-civ1-roster-registration-truth-v26"
REGISTRY_SCHEMA="grand-bruxelles-civ1-roster-registry-v1"
PLAYER_ASSET="grand-bruxelles-game/assets/characters/player_character.glb"
CHARACTER_ROOT=PurePosixPath("grand-bruxelles-game/assets/characters")
ALLOWED_ROLES={"civilian","police"}
REQUIRED={"asset_path","role","sha256","source_url","license"}
ALLOWED_LICENSES={"CC0-1.0","CC-BY-4.0","CC-BY-SA-4.0","MIT","Apache-2.0","BSD-2-Clause","BSD-3-Clause","GPL-3.0-only","GPL-3.0-or-later"}
UNRESERVED=set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
HEX=set("0123456789ABCDEF")
DNS_CHARS=set("abcdefghijklmnopqrstuvwxyz0123456789-")

class DuplicateJSONKeyError(ValueError): pass
class NonStandardJSONConstantError(ValueError): pass

def _pairs(pairs):
    out={}
    for k,v in pairs:
        if k in out: raise DuplicateJSONKeyError(k)
        out[k]=v
    return out

def _constant(token): raise NonStandardJSONConstantError(token)

def _resolve(value,root):
    raw=value.strip(); posix=raw.replace("\\","/"); pure=PurePosixPath(posix); normalized=pure.as_posix(); rp=CHARACTER_ROOT.parts
    if not raw or raw!=posix or raw!=normalized or pure.is_absolute() or ".." in pure.parts or len(pure.parts)<=len(rp) or pure.parts[:len(rp)]!=rp: return normalized,None
    base=root.resolve(); allowed=(base/Path(*rp)).resolve(); candidate=(base/Path(*pure.parts)).resolve()
    try: candidate.relative_to(allowed)
    except ValueError: return normalized,None
    return normalized,candidate

def _player_sha(root):
    _,p=_resolve(PLAYER_ASSET,root)
    return hashlib.sha256(p.read_bytes()).hexdigest() if p and p.is_file() else None

def _glb_reasons(asset_path,path):
    r=[]
    if PurePosixPath(asset_path).suffix!=".glb": r.append("glb_extension_required")
    try: data=path.read_bytes()
    except OSError: return [*r,"glb_container_invalid"]
    if len(data)<20: return [*r,"glb_container_invalid"]
    try: magic,version,total=struct.unpack_from("<4sII",data,0); jlen,jtype=struct.unpack_from("<I4s",data,12)
    except struct.error: return [*r,"glb_container_invalid"]
    if magic!=b"glTF" or version!=2 or total!=len(data) or jtype!=b"JSON" or jlen%4 or 20+jlen>len(data): r.append("glb_container_invalid")
    return sorted(set(r))

def _canonical_path(path):
    if any(s in {".",".."} for s in path.split("/")): return False
    i=0
    while i<len(path):
        if path[i]!="%": i+=1; continue
        if i+2>=len(path): return False
        pair=path[i+1:i+3]
        if any(c not in HEX for c in pair) or chr(int(pair,16)) in UNRESERVED: return False
        i+=3
    return True

def _raw_host_port(netloc):
    hp=netloc.rsplit("@",1)[-1]
    if hp.startswith("["):
        close=hp.find("]")
        host=hp[1:close] if close>=0 else hp
        suffix=hp[close+1:] if close>=0 else ""
        return host,(suffix[1:] if suffix.startswith(":") else None)
    return hp.rsplit(":",1) if ":" in hp else (hp,None)

def _canonical_dns_host(host):
    if len(host)>253: return False
    labels=host.split(".")
    return all(label and len(label)<=63 and label[0] in DNS_CHARS-{"-"} and label[-1] in DNS_CHARS-{"-"} and all(c in DNS_CHARS for c in label) for label in labels)

def _legacy_ipv4_spelling(host):
    parts=host.split(".")
    if not 1<=len(parts)<=4: return False
    values=[]
    for token in parts:
        if not token: return False
        try:
            if token.lower().startswith("0x"):
                if len(token)<=2: return False
                value=int(token[2:],16)
            elif len(token)>1 and token.startswith("0"):
                value=int(token,8)
            else:
                value=int(token,10)
        except ValueError:
            return False
        if value<0: return False
        values.append(value)
    if len(values)==1: return values[0]<=0xffffffff
    if len(values)==2: return values[0]<=0xff and values[1]<=0xffffff
    if len(values)==3: return values[0]<=0xff and values[1]<=0xff and values[2]<=0xffff
    return all(v<=0xff for v in values)

def _source_reasons(value):
    r=[]; raw=value.strip()
    if not raw: return r
    if raw!=value or any(c.isspace() or ord(c)<32 for c in raw) or "\\" in raw: r.append("source_url_not_canonical")
    try: p=urlsplit(raw); port=p.port
    except ValueError: return sorted(set([*r,"source_url_invalid"]))
    if p.scheme.lower()!="https": r.append("source_url_https_required")
    elif raw.partition(":")[0]!="https": r.append("source_url_not_canonical")
    if not p.hostname: r.append("source_url_host_missing")
    if p.username is not None or p.password is not None: r.append("source_url_credentials_forbidden")
    if p.query: r.append("source_url_query_forbidden")
    if p.fragment: r.append("source_url_fragment_forbidden")
    if not p.path or not _canonical_path(p.path): r.append("source_url_not_canonical")
    raw_host,raw_port=_raw_host_port(p.netloc); host=p.hostname or ""
    if any(ord(c)>127 for c in raw_host): r.append("source_url_non_ascii_host_forbidden")
    if host.endswith(".") or raw_host!=raw_host.lower(): r.append("source_url_not_canonical")
    if raw_port is not None and (port is None or raw_port!=str(port)): r.append("source_url_not_canonical")
    if p.scheme.lower()=="https" and port==443 and raw_port=="443": r.append("source_url_not_canonical")
    canonical_host=host.rstrip(".").lower(); localhost=canonical_host=="localhost" or canonical_host.endswith(".localhost")
    if localhost: r.append("source_url_localhost_forbidden")
    if canonical_host:
        try: address=ipaddress.ip_address(canonical_host)
        except ValueError:
            if _legacy_ipv4_spelling(canonical_host): r.append("source_url_ip_literal_not_canonical")
            elif not localhost and "." not in canonical_host: r.append("source_url_single_label_host_forbidden")
            elif not localhost and not _canonical_dns_host(canonical_host): r.append("source_url_dns_host_invalid")
        else:
            if not address.is_global: r.append("source_url_non_global_ip_forbidden")
    return sorted(set(r))

def _license_reasons(value):
    v=value.strip(); r=[]
    if value!=v: r.append("license_not_canonical")
    if v.lower() in {"unknown","tbd","todo","n/a","none"}: r.append("license_not_resolved")
    elif v and v not in ALLOWED_LICENSES: r.append("license_not_allowed")
    return r

def validate_entry(entry,repo_root):
    if not isinstance(entry,dict): return {"valid":False,"blocking_reasons":["entry_not_object"],"roster_eligible":False}
    r=[f"unexpected_entry_field:{k}" for k in sorted(set(entry)-REQUIRED)]
    r += [f"missing_or_empty_{k}" for k in sorted(REQUIRED) if not isinstance(entry.get(k),str) or not entry.get(k,"").strip()]
    asset_path,path=_resolve(str(entry.get("asset_path","")),repo_root); role=str(entry.get("role",""))
    if role not in ALLOWED_ROLES: r.append("role_not_explicit_civilian_or_police")
    if asset_path==PLAYER_ASSET: r.append("player_reuse_forbidden")
    if path is None: r.append("asset_path_not_canonically_confined")
    sha_raw=str(entry.get("sha256","")); sha=sha_raw.strip().lower()
    if sha_raw!=sha: r.append("sha256_not_canonical")
    if len(sha)!=64 or any(c not in "0123456789abcdef" for c in sha): r.append("sha256_invalid")
    actual=None; glb_ok=False
    if path is not None:
        if not path.is_file(): r.append("asset_missing")
        else:
            actual=hashlib.sha256(path.read_bytes()).hexdigest()
            if sha!=actual: r.append("sha256_mismatch")
            gr=_glb_reasons(asset_path,path); r+=gr; glb_ok=not gr
            if _player_sha(repo_root)==actual: r.append("player_content_reuse_forbidden")
    source=str(entry.get("source_url","")); r+=_source_reasons(source)
    lic=str(entry.get("license","")); r+=_license_reasons(lic)
    r=sorted(set(r)); valid=not r
    return {"asset_path":asset_path,"role":role or None,"declared_sha256":sha_raw or None,"normalized_sha256":sha or None,"actual_sha256":actual,"glb_container_valid":glb_ok,"source_url":source or None,"license":lic or None,"normalized_license":lic.strip() or None,"valid":valid,"blocking_reasons":r,"roster_eligible":valid}

def build_payload(registry,repo_root):
    top=[]; schema=registry.get("schema") if isinstance(registry,dict) else None; schema_ok=schema==REGISTRY_SCHEMA
    if not schema_ok: top.append("registry_schema_invalid")
    entries=registry.get("entries",[]) if isinstance(registry,dict) else []
    if not isinstance(registry,dict): top.append("registry_not_object"); entries=[]
    else:
        top += [f"unexpected_registry_field:{k}" for k in sorted(set(registry)-{"schema","entries"})]
        if not isinstance(entries,list): top.append("entries_not_array"); entries=[]
    results=[validate_entry(e,repo_root) for e in entries]
    paths={}; contents={}
    for i,e in enumerate(results):
        if e.get("asset_path"): paths.setdefault(e["asset_path"],[]).append(i)
        if e.get("actual_sha256"): contents.setdefault(e["actual_sha256"],[]).append(i)
    for reason,groups in (("duplicate_asset_path",paths),("duplicate_content_sha256",contents)):
        for inds in groups.values():
            if len(inds)>1:
                top.append(reason)
                for i in inds:
                    results[i]["valid"]=results[i]["roster_eligible"]=False
                    results[i]["blocking_reasons"]=sorted(set(results[i]["blocking_reasons"]+[reason]))
    invalid=[e for e in results if e.get("valid") is not True]
    if invalid: top.append("invalid_entries_present")
    eligible=[e for e in results if e.get("roster_eligible") is True]
    flags={"explicit_registration_required":True,"registry_schema_contract_required":True,"strict_registry_fields_required":True,"strict_entry_fields_required":True,"canonical_provenance_values_required":True,"duplicate_json_keys_forbidden":True,"nonstandard_json_constants_forbidden":True,"invalid_entries_fail_closed":True,"source_license_hash_required":True,"license_allowlist_required":True,"glb_container_integrity_required":True,"glb_version_required":2,"source_url_structural_provenance_required":True,"source_url_https_required":True,"source_url_local_network_forbidden":True,"source_url_multilabel_dns_required":True,"source_url_canonical_host_spelling_required":True,"source_url_canonical_scheme_host_case_required":True,"source_url_default_https_port_forbidden":True,"source_url_canonical_port_spelling_required":True,"source_url_query_forbidden":True,"source_url_canonical_percent_encoding_required":True,"source_url_dot_segments_forbidden":True,"source_url_ascii_host_required":True,"source_url_canonical_dns_host_required":True,"source_url_canonical_ip_literal_required":True,"source_url_explicit_root_path_required":True,"canonical_character_path_confinement_required":True,"unique_content_identity_required":True,"filename_role_inference_forbidden":True,"player_reuse_as_roster_forbidden":True,"player_content_identity_reuse_forbidden":True,"roster_authorized":False,"runtime_authorized":False,"visual_approval_claimed":False}
    return {"schema":SCHEMA,"registry_parse_valid":True,"registry_schema":schema,"registry_schema_valid":schema_ok,"registration_count":len(results),"eligible_count":len(eligible),"invalid_entry_count":len(invalid),"civilian_count":sum(e.get("role")=="civilian" for e in eligible),"police_count":sum(e.get("role")=="police" for e in eligible),"blocking_reasons":sorted(set(top)),"allowed_licenses":sorted(ALLOWED_LICENSES),"entries":results,**flags}

def main():
    ap=argparse.ArgumentParser(); ap.add_argument("registry",type=Path); ap.add_argument("--repo-root",type=Path,default=Path(".")); ap.add_argument("--out",type=Path); a=ap.parse_args(); parse_error=None
    try: registry=json.loads(a.registry.read_text(encoding="utf-8"),object_pairs_hook=_pairs,parse_constant=_constant)
    except (OSError,json.JSONDecodeError,DuplicateJSONKeyError,NonStandardJSONConstantError) as exc: registry={"schema":None,"entries":[]}; parse_error=exc
    payload=build_payload(registry,a.repo_root)
    if parse_error:
        payload["registry_parse_valid"]=False; payload["blocking_reasons"]=sorted(set(payload["blocking_reasons"]+["registry_unreadable_or_invalid_json"]))
    text=json.dumps(payload,indent=2,sort_keys=True)+"\n"
    if a.out: a.out.parent.mkdir(parents=True,exist_ok=True); a.out.write_text(text,encoding="utf-8")
    print(json.dumps(payload,sort_keys=True)); return 2 if payload["blocking_reasons"] else 0
if __name__=="__main__": raise SystemExit(main())
