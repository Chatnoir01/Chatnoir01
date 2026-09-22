#!/usr/bin/env python3
from __future__ import annotations
import argparse, hashlib, ipaddress, json, struct, unicodedata
from pathlib import Path, PurePosixPath
from urllib.parse import urlsplit

SCHEMA="grand-bruxelles-civ1-roster-registration-truth-v38"
REGISTRY_SCHEMA="grand-bruxelles-civ1-roster-registry-v1"
PLAYER_ASSET="grand-bruxelles-game/assets/characters/player_character.glb"
CHARACTER_ROOT=PurePosixPath("grand-bruxelles-game/assets/characters")
ALLOWED_ROLES={"civilian","police"}
REQUIRED={"asset_path","role","sha256","source_url","license"}
ALLOWED_LICENSES={"CC0-1.0","CC-BY-4.0","CC-BY-SA-4.0","MIT","Apache-2.0","BSD-2-Clause","BSD-3-Clause","GPL-3.0-only","GPL-3.0-or-later"}
HEX=set("0123456789ABCDEF")
DNS_CHARS=set("abcdefghijklmnopqrstuvwxyz0123456789-")
RFC3986_PCHAR_ASCII=set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~!$&'()*+,;=:@")
RESERVED_EXACT_HOSTS={"example.com","example.net","example.org"}
RESERVED_TLDS={"invalid","test","example"}

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
    if "//" in path or any(s in {".",".."} for s in path.split("/")): return False
    decoded_parts=[]; i=0
    while i<len(path):
        if path[i]!="%":
            if path[i]!="/" and path[i] not in RFC3986_PCHAR_ASCII: return False
            decoded_parts.append(path[i]); i+=1; continue
        octets=bytearray()
        while i<len(path) and path[i]=="%":
            if i+2>=len(path): return False
            pair=path[i+1:i+3]
            if any(c not in HEX for c in pair): return False
            octets.append(int(pair,16)); i+=3
        if not octets or any(b<0x80 for b in octets): return False
        try: text=bytes(octets).decode("utf-8","strict")
        except UnicodeDecodeError: return False
        if not text or any(ord(c)<0x80 for c in text): return False
        if any(unicodedata.category(c) in {"Cc","Cf","Cs","Zs","Zl","Zp"} for c in text): return False
        decoded_parts.append(text)
    decoded="".join(decoded_parts)
    return unicodedata.normalize("NFC",decoded)==decoded

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

def _idna_alabel_valid(label):
    if not label.startswith("xn--"): return True
    try:
        decoded=label.encode("ascii").decode("idna")
        return decoded.encode("idna").decode("ascii").lower()==label.lower()
    except UnicodeError:
        return False

def _reserved_host(host):
    if any(host==reserved or host.endswith("."+reserved) for reserved in RESERVED_EXACT_HOSTS): return True
    labels=host.split(".")
    return bool(labels and labels[-1] in RESERVED_TLDS)

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
            else: value=int(token,10)
        except ValueError: return False
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
    path_end=len(raw)
    for marker in ("?","#"):
        pos=raw.find(marker)
        if pos>=0: path_end=min(path_end,pos)
    tail=raw[path_end:]
    if "?" in tail: r.append("source_url_query_forbidden")
    if "#" in tail: r.append("source_url_fragment_forbidden")
    if not p.path or not _canonical_path(p.path): r.append("source_url_not_canonical")
    if any(ord(c)>127 for c in p.path): r.append("source_url_non_ascii_path_forbidden")
    raw_host,raw_port=_raw_host_port(p.netloc); host=p.hostname or ""
    if any(ord(c)>127 for c in raw_host): r.append("source_url_non_ascii_host_forbidden")
    if host.endswith(".") or raw_host!=raw_host.lower(): r.append("source_url_not_canonical")
    if raw_port is not None and (port is None or raw_port!=str(port)): r.append("source_url_not_canonical")
    if p.scheme.lower()=="https" and port==443 and raw_port=="443": r.append("source_url_not_canonical")
    canonical_host=host.rstrip(".").lower(); localhost=canonical_host=="localhost" or canonical_host.endswith(".localhost")
    if localhost: r.append("source_url_localhost_forbidden")
    if _reserved_host(canonical_host): r.append("source_url_reserved_host_forbidden")
    if canonical_host:
        try: address=ipaddress.ip_address(canonical_host)
        except ValueError:
            if _legacy_ipv4_spelling(canonical_host): r.append("source_url_ip_literal_not_canonical")
            elif not localhost and "." not in canonical_host: r.append("source_url_single_label_host_forbidden")
            elif not localhost and not _canonical_dns_host(canonical_host): r.append("source_url_dns_host_invalid")
            elif not localhost and any(not _idna_alabel_valid(label) for label in canonical_host.split(".")): r.append("source_url_idna_label_invalid")
        else:
            if isinstance(address,ipaddress.IPv6Address) and raw_host!=address.compressed: r.append("source_url_ip_literal_not_canonical")
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
    r += _source_reasons(str(entry.get("source_url",""))); r += _license_reasons(str(entry.get("license","")))
    if path is not None:
        if not path.is_file(): r.append("asset_missing")
        else:
            r += _glb_reasons(asset_path,path)
            actual=hashlib.sha256(path.read_bytes()).hexdigest()
            if actual!=sha: r.append("sha256_mismatch")
    player_sha=_player_sha(repo_root)
    if player_sha and path is not None and path.is_file() and hashlib.sha256(path.read_bytes()).hexdigest()==player_sha: r.append("player_content_reuse_forbidden")
    r=sorted(set(r)); return {"asset_path":asset_path,"role":role,"valid":not r,"blocking_reasons":r,"roster_eligible":not r}

def _strict_load(path):
    def _finite_float(token):
        value=float(token)
        if not __import__("math").isfinite(value): raise NonStandardJSONConstantError(token)
        return value
    return json.loads(path.read_text(encoding="utf-8"),object_pairs_hook=_pairs,parse_constant=_constant,parse_float=_finite_float)

def build_payload(registry,repo_root):
    entries=registry.get("entries",[]) if isinstance(registry,dict) else []
    results=[validate_entry(e,repo_root) for e in entries] if isinstance(entries,list) else []
    global_reasons=[]
    if not isinstance(registry,dict): global_reasons.append("registry_not_object")
    elif registry.get("schema")!=REGISTRY_SCHEMA: global_reasons.append("registry_schema_invalid")
    elif not isinstance(entries,list): global_reasons.append("registry_entries_not_list")
    else:
        paths={}; shas={}; sources={}
        for i,e in enumerate(entries):
            if not isinstance(e,dict): continue
            path=e.get("asset_path"); sha=e.get("sha256"); source=e.get("source_url")
            if isinstance(path,str): paths.setdefault(path.casefold(),[]).append(i)
            if isinstance(sha,str): shas.setdefault(sha.strip().lower(),[]).append(i)
            if isinstance(source,str): sources.setdefault(source,[]).append(i)
        for mapping,reason in ((paths,"duplicate_asset_path"),(shas,"duplicate_content_sha256"),(sources,"duplicate_source_url")):
            for idxs in mapping.values():
                if len(idxs)>1:
                    global_reasons.append(reason)
                    for idx in idxs:
                        if reason not in results[idx]["blocking_reasons"]: results[idx]["blocking_reasons"].append(reason)
                        results[idx]["blocking_reasons"].sort(); results[idx]["valid"]=False; results[idx]["roster_eligible"]=False
    global_reasons=sorted(set(global_reasons)); invalid=sum(not e.get("roster_eligible",False) for e in results)
    return {"schema":SCHEMA,"registration_count":len(results),"eligible_count":sum(e.get("roster_eligible",False) for e in results),"invalid_entry_count":invalid,"entries":results,"blocking_reasons":global_reasons,"unique_content_identity_required":True,"unique_source_provenance_required":True,"source_url_idna_alabel_roundtrip_required":True,"source_url_query_forbidden":True,"source_url_fragment_forbidden":True,"source_url_empty_delimiters_forbidden":True,"source_url_reserved_host_forbidden":True,"source_url_reserved_domain_subdomains_forbidden":True,"source_url_local_network_forbidden":True,"roster_authorized":bool(results) and invalid==0 and not global_reasons,"runtime_authorized":False,"visual_approval_claimed":False}

def main():
    ap=argparse.ArgumentParser(); ap.add_argument("registry",type=Path); ap.add_argument("--repo-root",type=Path,default=Path(".")); args=ap.parse_args()
    try: registry=_strict_load(args.registry)
    except (OSError,json.JSONDecodeError,DuplicateJSONKeyError,NonStandardJSONConstantError) as exc: print(f"CIV1_ROSTER_REGISTRATION_TRUTH_ERROR {exc}"); return 2
    payload=build_payload(registry,args.repo_root); print(json.dumps(payload,sort_keys=True))
    return 0 if not payload["blocking_reasons"] else 2

if __name__=="__main__": raise SystemExit(main())