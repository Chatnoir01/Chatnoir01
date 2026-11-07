#!/usr/bin/env python3
from __future__ import annotations
import argparse, json
from pathlib import Path
from urllib.parse import urlsplit

LOCAL_SUFFIXES=("local","home.arpa")

def is_local_network_source(source_url: str) -> bool:
    try:
        host=(urlsplit(source_url).hostname or "").rstrip(".").lower()
    except ValueError:
        return False
    if host=="localhost" or host.endswith(".localhost"):
        return True
    return any(host==suffix or host.endswith("."+suffix) for suffix in LOCAL_SUFFIXES)

def violating_sources(registry: object) -> list[str]:
    if not isinstance(registry,dict):
        return []
    entries=registry.get("entries",[])
    if not isinstance(entries,list):
        return []
    bad=[]
    for entry in entries:
        if not isinstance(entry,dict):
            continue
        source=entry.get("source_url")
        if isinstance(source,str) and is_local_network_source(source):
            bad.append(source)
    return bad

def main() -> int:
    ap=argparse.ArgumentParser()
    ap.add_argument("registry",type=Path)
    args=ap.parse_args()
    try:
        registry=json.loads(args.registry.read_text(encoding="utf-8"))
    except (OSError,json.JSONDecodeError) as exc:
        print(f"LOCAL_NETWORK_PROVENANCE_GATE_ERROR {exc}")
        return 2
    bad=violating_sources(registry)
    if bad:
        print("LOCAL_NETWORK_PROVENANCE_FORBIDDEN "+json.dumps(sorted(set(bad))))
        return 2
    print("LOCAL_NETWORK_PROVENANCE_GATE_GREEN")
    return 0

if __name__=="__main__":
    raise SystemExit(main())
