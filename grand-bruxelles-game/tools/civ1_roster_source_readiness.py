#!/usr/bin/env python3
from __future__ import annotations

import argparse, hashlib, json, math, os, stat, unicodedata
from pathlib import Path, PurePosixPath

CIV1_PREFIX="grand-bruxelles-game/assets/characters/civilians/civ1/"
STATUS_PATH=Path("grand-bruxelles-game/assets/characters/civilians/civ1/source_status.json")
SOURCE_ROOT=PurePosixPath("assets/characters/civilians/civ1/source")
REGISTRY_SCHEMA="grand-bruxelles-civ1-roster-registry-v1"
REQUIRED_READY_FLAGS=("production_authorized","activation_ready","source_package_present")
ALLOWED_SOURCE_LICENSES=frozenset({"CC0-1.0","CC-BY-4.0","CC-BY-SA-4.0","MIT","Apache-2.0","BSD-2-Clause","BSD-3-Clause","GPL-3.0-only","GPL-3.0-or-later"})
WINDOWS_FORBIDDEN_CHARS=frozenset('<>:"|?*')
WINDOWS_RESERVED_STEMS=frozenset({"CON","PRN","AUX","NUL","CONIN$","CONOUT$",*(f"COM{i}" for i in range(1,10)),*(f"LPT{i}" for i in range(1,10)),*(f"COM{i}" for i in "¹²³"),*(f"LPT{i}" for i in "¹²³")})
WINDOWS_MAX_COMPONENT_UTF16_UNITS=255
MAX_STATUS_BYTES=1 << 20
MAX_SOURCE_PAYLOAD_BYTES=512 << 20
MAX_TOTAL_SOURCE_BYTES=1 << 30
MAX_SOURCE_FILES=64
class DuplicateJSONKeyError(ValueError): pass
class NonStandardJSONConstantError(ValueError): pass
def _reject_duplicate_keys(pairs):
    result={}
    for key,value in pairs:
        if key in result: raise DuplicateJSONKeyError(key)
        result[key]=value
    return result
def _reject_nonstandard_constant(token): raise NonStandardJSONConstantError(token)
def _parse_finite_float(token):
    value=float(token)
    if not math.isfinite(value): raise NonStandardJSONConstantError(token)
    return value
def _loads_strict_json(text): return json.loads(text,object_pairs_hook=_reject_duplicate_keys,parse_float=_parse_finite_float,parse_constant=_reject_nonstandard_constant)
def _load_strict_json(path): return _loads_strict_json(path.read_text(encoding="utf-8"))
def _git_blob_sha1(data):
    digest=hashlib.sha1(); digest.update(f"blob {len(data)}\0".encode("ascii")); digest.update(data); return digest.hexdigest()
def _has_symlink_component(base,parts):
    current=base
    if current.is_symlink(): return True
    for part in parts:
        current=current/part
        if current.is_symlink(): return True
    return False
def _utf16_code_units(value):
    try: return len(value.encode("utf-16-le"))//2
    except UnicodeEncodeError: return WINDOWS_MAX_COMPONENT_UTF16_UNITS+1
def _windows_portable_component(part):
    if not part or part.endswith((" ",".")) or any(c in WINDOWS_FORBIDDEN_CHARS for c in part): return False
    if _utf16_code_units(part)>WINDOWS_MAX_COMPONENT_UTF16_UNITS: return False
    return part.split(".",1)[0].upper() not in WINDOWS_RESERVED_STEMS
def _canonical_path_text(value):
    if not isinstance(value,str) or not value or "\\" in value or "\x00" in value: return None
    if value!=value.strip() or unicodedata.normalize("NFC",value)!=value: return None
    if any(unicodedata.category(c).startswith("C") or unicodedata.category(c) in ("Zs","Zl","Zp") for c in value): return None
    pure=PurePosixPath(value)
    if pure.is_absolute() or ".." in pure.parts or pure.as_posix()!=value: return None
    if not all(_windows_portable_component(part) for part in pure.parts): return None
    return value
def _source_file(repo_root,source_path):
    canonical=_canonical_path_text(source_path)
    if canonical is None or canonical.endswith("/"): return None
    pure=PurePosixPath(canonical); root_parts=SOURCE_ROOT.parts
    if len(pure.parts)<=len(root_parts) or pure.parts[:len(root_parts)]!=root_parts or pure.name in ("",".",".."): return None
    if _has_symlink_component(repo_root,("grand-bruxelles-game",)+pure.parts): return None
    game_root=(repo_root/"grand-bruxelles-game").resolve(); allowed=(game_root/Path(*root_parts)).resolve(); candidate=(game_root/Path(*pure.parts)).resolve()
    try: candidate.relative_to(allowed)
    except ValueError: return None
    return candidate
def _read_regular_single_link(path,max_bytes=None):
    flags=os.O_RDONLY|getattr(os,"O_NONBLOCK",0)|getattr(os,"O_CLOEXEC",0)|getattr(os,"O_NOFOLLOW",0)
    fd=os.open(path,flags)
    try:
        metadata=os.fstat(fd)
        if not stat.S_ISREG(metadata.st_mode) or metadata.st_nlink!=1: return None
        if max_bytes is not None and (not isinstance(max_bytes,int) or isinstance(max_bytes,bool) or max_bytes<0 or metadata.st_size>max_bytes): return None
        with os.fdopen(fd,"rb",closefd=False) as source:
            data=source.read() if max_bytes is None else source.read(max_bytes+1)
        if max_bytes is not None and len(data)>max_bytes: return None
        return data
    finally:
        os.close(fd)
def _source_manifest_integrity(status,repo_root):
    source_paths=status.get("source_paths"); manifest=status.get("source_manifest")
    if not isinstance(source_paths,list) or not source_paths or len(source_paths)>MAX_SOURCE_FILES: return False
    if len({p.casefold() for p in source_paths if isinstance(p,str)})!=len(source_paths): return False
    if not isinstance(manifest,dict) or not manifest or len(manifest)>MAX_SOURCE_FILES or set(source_paths)!=set(manifest): return False
    if len({p.casefold() for p in manifest if isinstance(p,str)})!=len(manifest): return False
    total_source_bytes=0
    for record in manifest.values():
        if not isinstance(record,dict): return False
        expected_size=record.get("size_bytes")
        if not isinstance(expected_size,int) or isinstance(expected_size,bool) or expected_size<=0 or expected_size>MAX_SOURCE_PAYLOAD_BYTES: return False
        total_source_bytes += expected_size
        if total_source_bytes>MAX_TOTAL_SOURCE_BYTES: return False
    if not all(_canonical_path_text(p) is not None and _source_file(repo_root,p) is not None for p in source_paths): return False
    if not all(_canonical_path_text(p) is not None and _source_file(repo_root,p) is not None for p in manifest): return False
    upstream_identities=[]
    for source_path in source_paths:
        record=manifest.get(source_path)
        if not isinstance(record,dict) or record.get("license_scope_verified") is not True: return False
        upstream_path=record.get("upstream_path")
        if _canonical_path_text(upstream_path) is None or upstream_path.endswith("/"): return False
        upstream_pure=PurePosixPath(upstream_path)
        if upstream_pure.name in ("",".",".."): return False
        if PurePosixPath(source_path).name != upstream_pure.name: return False
        upstream_identities.append(upstream_path)
        license_id=record.get("license")
        if not isinstance(license_id,str) or license_id not in ALLOWED_SOURCE_LICENSES: return False
        expected_sha1=record.get("git_blob_sha1"); expected_size=record.get("size_bytes")
        if not isinstance(expected_sha1,str) or len(expected_sha1)!=40 or expected_sha1!=expected_sha1.lower() or any(c not in "0123456789abcdef" for c in expected_sha1): return False
        candidate=_source_file(repo_root,source_path)
        if candidate is None: return False
        try: data=_read_regular_single_link(candidate,expected_size)
        except OSError: return False
        if data is None or len(data)!=expected_size or _git_blob_sha1(data)!=expected_sha1: return False
    if len({p.casefold() for p in upstream_identities})!=len(upstream_identities): return False
    return True
def _status_consistent(status,repo_root):
    if not isinstance(status,dict) or status.get("candidate_id")!="CIV-1": return False
    if not all(status.get(k) is True for k in REQUIRED_READY_FLAGS): return False
    if status.get("blocker") not in (None,""): return False
    character_source=status.get("character_source")
    if not isinstance(character_source,dict): return False
    license_evidence=character_source.get("license_evidence")
    if not isinstance(license_evidence,dict): return False
    unresolved=license_evidence.get("unresolved_components")
    if not isinstance(unresolved,list) or unresolved: return False
    return _source_manifest_integrity(status,repo_root)
def source_ready(repo_root):
    if _has_symlink_component(repo_root,tuple(STATUS_PATH.parts)): return False
    status_path=repo_root/STATUS_PATH
    try:
        raw=_read_regular_single_link(status_path,MAX_STATUS_BYTES)
        if raw is None or not raw: return False
        status=_loads_strict_json(raw.decode("utf-8"))
    except (OSError,UnicodeDecodeError,json.JSONDecodeError,ValueError): return False
    return _status_consistent(status,repo_root)
def _canonical_asset_path(value):
    canonical=_canonical_path_text(value)
    if canonical is None: return None
    pure=PurePosixPath(canonical)
    if len(pure.parts)<2 or canonical.endswith("/") or pure.name in ("",".",".."): return None
    return canonical
def registry_consistent(registry):
    if not isinstance(registry,dict) or registry.get("schema")!=REGISTRY_SCHEMA: return False
    entries=registry.get("entries")
    if not isinstance(entries,list): return False
    identities=[]
    for entry in entries:
        if not isinstance(entry,dict): return False
        asset_path=_canonical_asset_path(entry.get("asset_path"))
        if asset_path is None: return False
        identities.append(asset_path)
    return len(identities)==len({identity.casefold() for identity in identities})
def blocking_entries(registry,repo_root):
    if not registry_consistent(registry): raise ValueError("invalid CIV-1 roster registry structure")
    if source_ready(repo_root): return []
    return [e["asset_path"] for e in registry["entries"] if e["asset_path"].startswith(CIV1_PREFIX)]
def main():
    parser=argparse.ArgumentParser(); parser.add_argument("registry",type=Path); parser.add_argument("--repo-root",type=Path,default=Path(".")); args=parser.parse_args()
    try: registry=_load_strict_json(args.registry); blocked=blocking_entries(registry,args.repo_root)
    except (OSError,json.JSONDecodeError,DuplicateJSONKeyError,NonStandardJSONConstantError,ValueError) as exc: print(f"CIV1_ROSTER_SOURCE_READINESS_ERROR {exc}"); return 2
    if blocked: print("CIV1_ROSTER_SOURCE_NOT_READY "+json.dumps(sorted(set(blocked)))); return 2
    print("CIV1_ROSTER_SOURCE_READINESS_GREEN"); return 0
if __name__=="__main__": raise SystemExit(main())
