#!/usr/bin/env python3
"""Canonicalize LLM-authored NPC dialogue into runtime-safe game data.

This tool deliberately performs no network access and no model invocation. A model or
human author produces a draft JSON file first; this command validates and bakes it into
the contract consumed by `NpcDialogueCatalog`.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Any

SCHEMA = "grand-bruxelles-npc-dialogue-v1"
ALLOWED_LOCALES = {"fr-BE", "nl-BE", "en"}
IDENTIFIER_RE = re.compile(r"^[A-Za-z0-9_-]{1,64}$")
MAX_PERSONAS = 512
MAX_LINES_PER_INTENT = 12
MAX_LINE_LENGTH = 180


class BakeError(ValueError):
    pass


def _validate_identifier(value: Any, field: str) -> str:
    text = str(value).strip()
    if not IDENTIFIER_RE.fullmatch(text):
        raise BakeError(f"invalid {field}: {text!r}")
    return text


def _validate_line(value: Any, persona_id: str, intent: str) -> str:
    if not isinstance(value, str):
        raise BakeError(f"line must be text for {persona_id}/{intent}")
    line = value.strip()
    if not line or len(line) > MAX_LINE_LENGTH:
        raise BakeError(f"line length outside contract for {persona_id}/{intent}")
    if any(ch in line for ch in ("\n", "\r", "\t")):
        raise BakeError(f"control whitespace forbidden for {persona_id}/{intent}")
    return line


def bake_payload(source: dict[str, Any], source_bytes: bytes | None = None) -> dict[str, Any]:
    personas = source.get("personas")
    if not isinstance(personas, list) or not personas or len(personas) > MAX_PERSONAS:
        raise BakeError("persona count outside contract")

    generator = source.get("generator", {})
    if generator is None:
        generator = {}
    if not isinstance(generator, dict):
        raise BakeError("generator metadata must be an object")

    baked_personas: list[dict[str, Any]] = []
    seen_ids: set[str] = set()
    for raw_persona in personas:
        if not isinstance(raw_persona, dict):
            raise BakeError("persona row must be an object")
        persona_id = _validate_identifier(raw_persona.get("id", ""), "persona id")
        if persona_id in seen_ids:
            raise BakeError(f"duplicate persona id: {persona_id}")
        seen_ids.add(persona_id)
        zone = _validate_identifier(raw_persona.get("zone", ""), "zone")
        locale = str(raw_persona.get("locale", ""))
        if locale not in ALLOWED_LOCALES:
            raise BakeError(f"unsupported locale for {persona_id}: {locale!r}")

        raw_intents = raw_persona.get("intents")
        if not isinstance(raw_intents, dict) or not raw_intents:
            raise BakeError(f"intents missing for {persona_id}")
        baked_intents: dict[str, list[str]] = {}
        for raw_intent, raw_lines in raw_intents.items():
            intent = _validate_identifier(raw_intent, "intent")
            if not isinstance(raw_lines, list) or not raw_lines or len(raw_lines) > MAX_LINES_PER_INTENT:
                raise BakeError(f"line count outside contract for {persona_id}/{intent}")
            lines = [_validate_line(line, persona_id, intent) for line in raw_lines]
            if len(set(lines)) != len(lines):
                raise BakeError(f"duplicate generated line for {persona_id}/{intent}")
            baked_intents[intent] = sorted(lines)

        if "greeting" not in baked_intents and "smalltalk" not in baked_intents:
            raise BakeError(f"persona needs greeting or smalltalk: {persona_id}")
        baked_personas.append(
            {
                "id": persona_id,
                "zone": zone,
                "locale": locale,
                "intents": dict(sorted(baked_intents.items())),
            }
        )

    canonical_source = source_bytes
    if canonical_source is None:
        canonical_source = json.dumps(source, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    source_sha256 = hashlib.sha256(canonical_source).hexdigest()

    baked_generator = {
        "mode": "offline_llm_bake",
        "version": "1",
        "source_sha256": source_sha256,
    }
    for key in ("provider", "model", "run_id"):
        value = generator.get(key)
        if value is not None and str(value).strip():
            baked_generator[key] = str(value).strip()

    return {
        "schema": SCHEMA,
        "generator": baked_generator,
        "personas": sorted(baked_personas, key=lambda row: row["id"]),
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True, type=Path, help="LLM/human draft JSON")
    parser.add_argument("--output", required=True, type=Path, help="Runtime .game.json destination")
    args = parser.parse_args(argv)

    try:
        source_bytes = args.input.read_bytes()
        source = json.loads(source_bytes.decode("utf-8"))
        if not isinstance(source, dict):
            raise BakeError("input root must be an object")
        baked = bake_payload(source, source_bytes)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(baked, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    except (OSError, UnicodeError, json.JSONDecodeError, BakeError) as exc:
        print(f"NPC_DIALOGUE_BAKE_FAIL: {exc}", file=sys.stderr)
        return 2

    print(
        "NPC_DIALOGUE_BAKE_OK: personas=%d source_sha256=%s"
        % (len(baked["personas"]), baked["generator"]["source_sha256"])
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
