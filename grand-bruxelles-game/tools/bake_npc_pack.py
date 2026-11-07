#!/usr/bin/env python3
"""Bake an LLM-authored NPC profile draft into runtime-safe JSON."""
from __future__ import annotations

import argparse, hashlib, json, re, sys
from pathlib import Path
from typing import Any

SCHEMA = "grand-bruxelles-npc-pack-v1"
ID_RE = re.compile(r"^[A-Za-z0-9_-]{1,64}$")
LOCALES = {"fr-BE", "nl-BE", "en"}
ARCHETYPES = {"civilian", "aggressive", "runner"}

class BakeError(ValueError): pass

def ident(value: Any, field: str) -> str:
    text = str(value).strip()
    if not ID_RE.fullmatch(text): raise BakeError(f"invalid {field}: {text!r}")
    return text

def text(value: Any, field: str, limit: int = 180) -> str:
    if not isinstance(value, str): raise BakeError(f"{field} must be text")
    value = value.strip()
    if not value or len(value) > limit or any(c in value for c in "\r\n\t"):
        raise BakeError(f"invalid {field}")
    return value

def bake_payload(source: dict[str, Any], source_bytes: bytes | None = None) -> dict[str, Any]:
    rows = source.get("profiles")
    if not isinstance(rows, list) or not rows or len(rows) > 64: raise BakeError("profile count outside contract")
    generator = source.get("generator", {})
    if not isinstance(generator, dict): raise BakeError("generator must be an object")
    baked, seen_ids = [], set()
    for raw in rows:
        if not isinstance(raw, dict): raise BakeError("profile row must be an object")
        profile_id = ident(raw.get("id", ""), "profile id")
        if profile_id in seen_ids: raise BakeError(f"duplicate profile id: {profile_id}")
        seen_ids.add(profile_id)
        zone, locale = ident(raw.get("zone", ""), "zone"), str(raw.get("locale", ""))
        if locale not in LOCALES: raise BakeError("unsupported locale")
        archetype = str(raw.get("archetype", ""))
        if archetype not in ARCHETYPES: raise BakeError("unsupported archetype")
        persona = raw.get("persona")
        if not isinstance(persona, dict): raise BakeError("persona missing")
        persona_out = {"name": text(persona.get("name"), "persona name", 80), "summary": text(persona.get("summary"), "persona summary", 240)}
        thresholds = raw.get("thresholds")
        if not isinstance(thresholds, dict): raise BakeError("thresholds missing")
        threshold_out = {}
        for key in ("fear", "aggression", "flee_health"):
            value = float(thresholds.get(key, -1.0))
            if value < 0.0 or value > 1.0: raise BakeError(f"invalid threshold: {key}")
            threshold_out[key] = round(value, 4)
        dialogue = raw.get("dialogue")
        if not isinstance(dialogue, dict) or not dialogue: raise BakeError("dialogue missing")
        dialogue_out, all_lines = {}, []
        for raw_intent, raw_lines in dialogue.items():
            intent = ident(raw_intent, "intent")
            if not isinstance(raw_lines, list) or not raw_lines or len(raw_lines) > 12: raise BakeError("intent line count outside contract")
            lines = [text(line, f"{profile_id}/{intent}") for line in raw_lines]
            if len(set(lines)) != len(lines): raise BakeError("duplicate line inside intent")
            dialogue_out[intent] = sorted(lines)
            all_lines.extend(lines)
        if len(all_lines) < 20 or len(all_lines) > 40: raise BakeError("profile must contain 20-40 dialogue lines")
        if len(set(all_lines)) != len(all_lines): raise BakeError("duplicate line across intents")
        if "greeting" not in dialogue_out or "smalltalk" not in dialogue_out: raise BakeError("greeting and smalltalk required")
        baked.append({"id": profile_id, "zone": zone, "locale": locale, "archetype": archetype, "persona": persona_out, "thresholds": threshold_out, "dialogue": dict(sorted(dialogue_out.items()))})
    raw_bytes = source_bytes or json.dumps(source, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()
    meta = {"mode": "offline_llm_bake", "version": "1", "source_sha256": hashlib.sha256(raw_bytes).hexdigest()}
    for key in ("provider", "model", "revision", "run_id"):
        if str(generator.get(key, "")).strip(): meta[key] = str(generator[key]).strip()
    return {"schema": SCHEMA, "generator": meta, "profiles": sorted(baked, key=lambda row: row["id"])}

def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True, type=Path); parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args(argv)
    try:
        raw = args.input.read_bytes(); source = json.loads(raw.decode())
        if not isinstance(source, dict): raise BakeError("input root must be an object")
        baked = bake_payload(source, raw); args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(baked, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    except (OSError, UnicodeError, json.JSONDecodeError, BakeError) as exc:
        print(f"NPC_PACK_BAKE_FAIL: {exc}", file=sys.stderr); return 2
    print(f"NPC_PACK_BAKE_OK: profiles={len(baked['profiles'])} source_sha256={baked['generator']['source_sha256']}"); return 0

if __name__ == "__main__": raise SystemExit(main())
