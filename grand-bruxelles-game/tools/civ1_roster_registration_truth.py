#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import ipaddress
import json
import struct
from pathlib import Path, PurePosixPath
from urllib.parse import urlsplit

SCHEMA = "grand-bruxelles-civ1-roster-registration-truth-v19"
REGISTRY_SCHEMA = "grand-bruxelles-civ1-roster-registry-v1"
PLAYER_ASSET = "grand-bruxelles-game/assets/characters/player_character.glb"
CHARACTER_ROOT = PurePosixPath("grand-bruxelles-game/assets/characters")
ALLOWED_ROLES = {"civilian", "police"}
REQUIRED = {"asset_path", "role", "sha256", "source_url", "license"}
ALLOWED_ENTRY_FIELDS = set(REQUIRED)
ALLOWED_REGISTRY_FIELDS = {"schema", "entries"}
ALLOWED_LICENSES = {"CC0-1.0","CC-BY-4.0","CC-BY-SA-4.0","MIT","Apache-2.0","BSD-2-Clause","BSD-3-Clause","GPL-3.0-only","GPL-3.0-or-later"}
UNRESOLVED_LICENSE_MARKERS = {"unknown", "tbd", "todo", "n/a", "none"}

class DuplicateJSONKeyError(ValueError):
    def __init__(self, key: str) -> None:
        super().__init__(f"duplicate JSON key: {key}")
        self.key = key
class NonStandardJSONConstantError(ValueError):
    def __init__(self, token: str) -> None:
        super().__init__(f"non-standard JSON constant: {token}")
        self.token = token

def _reject_duplicate_json_keys(pairs):
    result={}
    for key,value in pairs:
        if key in result: raise DuplicateJSONKeyError(key)
        result[key]=value
    return result

def _reject_nonstandard_json_constant(token): raise NonStandardJSONConstantError(token)

def _resolve_character_asset(value, repo_root):
    raw=value.strip(); posix_raw=raw.replace('\\','/'); pure=PurePosixPath(posix_raw); normalized=pure.as_posix(); root_parts=CHARACTER_ROOT.parts
    canonical=bool(raw) and raw==posix_raw==normalized
    confined=(not pure.is_absolute() and '..' not in pure.parts and len(pure.parts)>len(root_parts) and pure.parts[:len(root_parts)]==root_parts)
    if not canonical or not confined: return normalized,None
    resolved_repo=repo_root.resolve(); resolved_root=(resolved_repo/Path(*root_parts)).resolve(); candidate=(resolved_repo/Path(*pure.parts)).resolve()
    try: candidate.relative_to(resolved_root)
    except ValueError: return normalized,None
    return normalized,candidate

def _player_content_sha256(repo_root):
    asset_path,player=_resolve_character_asset(PLAYER_ASSET,repo_root)
    if asset_path!=PLAYER_ASSET or player is None or not player.is_file(): return None
    return hashlib.sha256(player.read_bytes()).hexdigest()

def _glb_container_reasons(asset_path,path):
    reasons=[]
    if PurePosixPath(asset_path).suffix!='.glb': reasons.append('glb_extension_required')
    try: data=path.read_bytes()
    except OSError: return [*reasons,'glb_container_invalid']
    if len(data)<20: return [*reasons,'glb_container_invalid']
    try: magic,version,declared_length=struct.unpack_from('<4sII',data,0); json_length,json_type=struct.unpack_from('<I4s',data,12)
    except struct.error: return [*reasons,'glb_container_invalid']
    if magic!=b'glTF' or version!=2 or declared_length!=len(data): reasons.append('glb_container_invalid')
    if json_type!=b'JSON' or json_length%4!=0 or 20+json_length>len(data): reasons.append('glb_container_invalid')
    return sorted(set(reasons))

def _source_url_reasons(value):
    reasons=[]; raw=value.strip()
    if not raw: return reasons
    if raw!=value or any(ch.isspace() or ord(ch)<32 for ch in raw) or '\\' in raw: reasons.append('source_url_not_canonical')
    try: parsed=urlsplit(raw); parsed_port=parsed.port
    except ValueError: return sorted(set([*reasons,'source_url_invalid']))
    raw_scheme=raw.partition(':')[0]
    if parsed.scheme.lower()!='https': reasons.append('source_url_https_required')
    elif raw_scheme!='https': reasons.append('source_url_not_canonical')
    if not parsed.hostname: reasons.append('source_url_host_missing')
    if parsed.username is not None or parsed.password is not None: reasons.append('source_url_credentials_forbidden')
    if parsed.query: reasons.append('source_url_query_forbidden')
    if parsed.fragment: reasons.append('source_url_fragment_forbidden')
    parsed_host=parsed.hostname or ''
    hostport=parsed.netloc.rsplit('@',1)[-1]
    if hostport.startswith('['): raw_host=hostport[1:hostport.find(']')] if ']' in hostport else hostport
    else: raw_host=hostport.rsplit(':',1)[0] if ':' in hostport else hostport
    if parsed_host.endswith('.') or raw_host!=raw_host.lower(): reasons.append('source_url_not_canonical')
    if parsed.scheme.lower()=='https' and parsed_port==443 and hostport.endswith(':443'): reasons.append('source_url_not_canonical')
    host=parsed_host.rstrip('.').lower(); is_localhost=host=='localhost' or host.endswith('.localhost')
    if is_localhost: reasons.append('source_url_localhost_forbidden')
    if host:
        try: address=ipaddress.ip_address(host)
        except ValueError:
            if not is_localhost and '.' not in host: reasons.append('source_url_single_label_host_forbidden')
        else:
            if not address.is_global: reasons.append('source_url_non_global_ip_forbidden')
    return sorted(set(reasons))

def _license_reasons(value):
    reasons=[]; license_value=value.strip()
    if value!=license_value: reasons.append('license_not_canonical')
    if not license_value: return reasons
    if license_value.lower() in UNRESOLVED_LICENSE_MARKERS: reasons.append('license_not_resolved')
    elif license_value not in ALLOWED_LICENSES: reasons.append('license_not_allowed')
    return sorted(set(reasons))

def validate_entry(entry,repo_root):
    reasons=[]
    if not isinstance(entry,dict): return {'valid':False,'blocking_reasons':['entry_not_object'],'roster_eligible':False}
    unexpected=sorted(set(entry)-ALLOWED_ENTRY_FIELDS); reasons.extend(f'unexpected_entry_field:{f}' for f in unexpected)
    missing=sorted(k for k in REQUIRED if not isinstance(entry.get(k),str) or not entry.get(k,'').strip()); reasons.extend(f'missing_or_empty_{k}' for k in missing)
    asset_path,path=_resolve_character_asset(str(entry.get('asset_path','')),repo_root); role=str(entry.get('role',''))
    if role not in ALLOWED_ROLES: reasons.append('role_not_explicit_civilian_or_police')
    if asset_path==PLAYER_ASSET: reasons.append('player_reuse_forbidden')
    if path is None: reasons.append('asset_path_not_canonically_confined')
    sha_raw=str(entry.get('sha256','')); sha=sha_raw.strip().lower()
    if sha_raw!=sha: reasons.append('sha256_not_canonical')
    if len(sha)!=64 or any(c not in '0123456789abcdef' for c in sha): reasons.append('sha256_invalid')
    actual_sha=None; glb_container_valid=False
    if path is not None:
        if not path.is_file(): reasons.append('asset_missing')
        else:
            actual_sha=hashlib.sha256(path.read_bytes()).hexdigest()
            if sha!=actual_sha: reasons.append('sha256_mismatch')
            glb_reasons=_glb_container_reasons(asset_path,path); reasons.extend(glb_reasons); glb_container_valid=not glb_reasons
            player_sha=_player_content_sha256(repo_root)
            if player_sha is not None and actual_sha==player_sha: reasons.append('player_content_reuse_forbidden')
    source=str(entry.get('source_url','')); reasons.extend(_source_url_reasons(source)); license_raw=str(entry.get('license','')); license_value=license_raw.strip(); reasons.extend(_license_reasons(license_raw)); valid=not reasons
    return {'asset_path':asset_path,'role':role or None,'declared_sha256':sha_raw or None,'normalized_sha256':sha or None,'actual_sha256':actual_sha,'glb_container_valid':glb_container_valid,'source_url':source or None,'license':license_raw or None,'normalized_license':license_value or None,'valid':valid,'blocking_reasons':sorted(set(reasons)),'roster_eligible':valid}

def _invalidate(results,indices,reason):
    for i in indices:
        results[i]['valid']=False; results[i]['roster_eligible']=False; results[i]['blocking_reasons']=sorted(set([*results[i].get('blocking_reasons',[]),reason]))

def build_payload(registry,repo_root):
    entries=registry.get('entries',[]) if isinstance(registry,dict) else []; top_reasons=[]; registry_schema=registry.get('schema') if isinstance(registry,dict) else None; registry_schema_valid=registry_schema==REGISTRY_SCHEMA
    if not registry_schema_valid: top_reasons.append('registry_schema_invalid')
    if not isinstance(registry,dict): top_reasons.append('registry_not_object'); entries=[]
    else:
        top_reasons.extend(f'unexpected_registry_field:{f}' for f in sorted(set(registry)-ALLOWED_REGISTRY_FIELDS))
        if not isinstance(entries,list): top_reasons.append('entries_not_array'); entries=[]
    results=[validate_entry(item,repo_root) for item in entries]; by_path={}; by_content={}
    for i,item in enumerate(results):
        if item.get('asset_path'): by_path.setdefault(item['asset_path'],[]).append(i)
        if item.get('actual_sha256'): by_content.setdefault(item['actual_sha256'],[]).append(i)
    for reason,groups in (('duplicate_asset_path',by_path),('duplicate_content_sha256',by_content)):
        for indices in groups.values():
            if len(indices)>1: top_reasons.append(reason); _invalidate(results,indices,reason)
    invalid_indices=[i for i,item in enumerate(results) if item.get('valid') is not True]
    if invalid_indices: top_reasons.append('invalid_entries_present')
    eligible=[item for item in results if item.get('roster_eligible') is True]
    return {'schema':SCHEMA,'registry_parse_valid':True,'registry_schema':registry_schema,'registry_schema_valid':registry_schema_valid,'registration_count':len(results),'eligible_count':len(eligible),'invalid_entry_count':len(invalid_indices),'civilian_count':sum(item.get('role')=='civilian' for item in eligible),'police_count':sum(item.get('role')=='police' for item in eligible),'blocking_reasons':sorted(set(top_reasons)),'explicit_registration_required':True,'registry_schema_contract_required':True,'strict_registry_fields_required':True,'strict_entry_fields_required':True,'canonical_provenance_values_required':True,'duplicate_json_keys_forbidden':True,'nonstandard_json_constants_forbidden':True,'invalid_entries_fail_closed':True,'source_license_hash_required':True,'license_allowlist_required':True,'allowed_licenses':sorted(ALLOWED_LICENSES),'glb_container_integrity_required':True,'glb_version_required':2,'source_url_structural_provenance_required':True,'source_url_https_required':True,'source_url_local_network_forbidden':True,'source_url_multilabel_dns_required':True,'source_url_canonical_host_spelling_required':True,'source_url_canonical_scheme_host_case_required':True,'source_url_default_https_port_forbidden':True,'source_url_query_forbidden':True,'canonical_character_path_confinement_required':True,'unique_content_identity_required':True,'filename_role_inference_forbidden':True,'player_reuse_as_roster_forbidden':True,'player_content_identity_reuse_forbidden':True,'roster_authorized':False,'runtime_authorized':False,'visual_approval_claimed':False,'entries':results}

def main():
    parser=argparse.ArgumentParser(); parser.add_argument('registry',type=Path); parser.add_argument('--repo-root',type=Path,default=Path('.')); parser.add_argument('--out',type=Path); args=parser.parse_args(); duplicate_key=None; nonstandard_constant=None
    try: registry=json.loads(args.registry.read_text(encoding='utf-8'),object_pairs_hook=_reject_duplicate_json_keys,parse_constant=_reject_nonstandard_json_constant)
    except DuplicateJSONKeyError as exc: registry={'schema':None,'entries':[]}; parse_error=True; duplicate_key=exc.key
    except NonStandardJSONConstantError as exc: registry={'schema':None,'entries':[]}; parse_error=True; nonstandard_constant=exc.token
    except (OSError,json.JSONDecodeError): registry={'schema':None,'entries':[]}; parse_error=True
    else: parse_error=False
    payload=build_payload(registry,args.repo_root)
    if parse_error:
        payload['registry_parse_valid']=False; parse_reasons=[*payload['blocking_reasons'],'registry_unreadable_or_invalid_json']
        if duplicate_key is not None: parse_reasons.append(f'registry_duplicate_json_key:{duplicate_key}')
        if nonstandard_constant is not None: parse_reasons.append(f'registry_nonstandard_json_constant:{nonstandard_constant}')
        payload['blocking_reasons']=sorted(set(parse_reasons))
    text=json.dumps(payload,indent=2,sort_keys=True)+'\n'
    if args.out: args.out.parent.mkdir(parents=True,exist_ok=True); args.out.write_text(text,encoding='utf-8')
    print(json.dumps(payload,sort_keys=True)); return 2 if payload['blocking_reasons'] else 0
if __name__=='__main__': raise SystemExit(main())
