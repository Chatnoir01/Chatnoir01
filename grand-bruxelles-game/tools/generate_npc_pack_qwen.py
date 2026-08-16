#!/usr/bin/env python3
"""Generate a complete NPC pack draft with the pinned local Qwen model, then bake it.

Weights remain outside Git. This command requires the model downloaded by
`tools/download_npc_llm.py`. Qwen authors the persona summary, thresholds and 20
lines; `bake_npc_pack.py` remains the mandatory authority boundary before runtime.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
SERVER_PATH = ROOT / "tools" / "npc_llm_server.py"
BAKER_PATH = ROOT / "tools" / "bake_npc_pack.py"
MANIFEST_PATH = ROOT / "data" / "ai" / "npc_llm_model.json"


def _load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


SERVER = _load_module("npc_llm_server_for_pack", SERVER_PATH)
BAKER = _load_module("bake_npc_pack_for_qwen", BAKER_PATH)


def build_prompt(profile_id: str, zone: str, archetype: str, locale: str) -> str:
    return f"""Tu crées UN habitant crédible de Bruxelles pour un jeu vidéo.
Zone: {zone}
Archetype: {archetype}
Locale: {locale}
Identifiant imposé: {profile_id}

Retourne uniquement un objet JSON, sans markdown ni commentaire, avec cette forme exacte:
{{
  "profiles": [{{
    "id": "{profile_id}",
    "zone": "{zone}",
    "locale": "{locale}",
    "archetype": "{archetype}",
    "persona": {{"name": "prénom crédible", "summary": "une phrase courte"}},
    "thresholds": {{"fear": 0.0, "aggression": 0.0, "flee_health": 0.0}},
    "dialogue": {{
      "greeting": [4 phrases],
      "smalltalk": [4 phrases],
      "warning": [4 phrases],
      "hurt": [4 phrases],
      "police": [4 phrases]
    }}
  }}]
}}

Contraintes:
- exactement 20 phrases, toutes différentes, courtes, naturelles, en français belge courant;
- aucune mention d'IA, modèle ou prompt;
- seuils entre 0 et 1 cohérents avec l'archétype;
- aucune action de jeu, aucun code, aucune instruction technique;
- persona bruxelloise crédible, sans caricature.
"""


def extract_json_object(text: str) -> dict[str, Any]:
    candidate = text.strip()
    if candidate.startswith("```"):
        lines = candidate.splitlines()
        if lines and lines[0].startswith("```"):
            lines = lines[1:]
        if lines and lines[-1].strip() == "```":
            lines = lines[:-1]
        candidate = "\n".join(lines).strip()
    start = candidate.find("{")
    end = candidate.rfind("}")
    if start < 0 or end <= start:
        raise BAKER.BakeError("Qwen output contains no JSON object")
    parsed = json.loads(candidate[start : end + 1])
    if not isinstance(parsed, dict):
        raise BAKER.BakeError("Qwen JSON root must be an object")
    return parsed


def attach_generator_metadata(draft: dict[str, Any], manifest: dict[str, Any]) -> dict[str, Any]:
    result = json.loads(json.dumps(draft, ensure_ascii=False))
    result["generator"] = {
        "provider": "local_qwen",
        "model": str(manifest["repo_id"]),
        "revision": str(manifest["revision"]),
        "run_id": "local-pack-generation",
    }
    return result


def validate_generated_identity(draft: dict[str, Any], profile_id: str, zone: str, archetype: str, locale: str) -> None:
    rows = draft.get("profiles")
    if not isinstance(rows, list) or len(rows) != 1 or not isinstance(rows[0], dict):
        raise BAKER.BakeError("Qwen must generate exactly one profile")
    row = rows[0]
    expected = {"id": profile_id, "zone": zone, "archetype": archetype, "locale": locale}
    actual = {key: str(row.get(key, "")) for key in expected}
    if actual != expected:
        differences = ", ".join(
            f"{key}: expected={expected[key]!r} actual={actual[key]!r}"
            for key in expected if actual[key] != expected[key]
        )
        raise BAKER.BakeError("Qwen changed imposed identity: " + differences)


def generate_raw_text(tokenizer, model, prompt: str, max_new_tokens: int = 900) -> str:
    messages = [
        {"role": "system", "content": "Tu es un auteur de données JSON pour des PNJ bruxellois. Tu respectes exactement le schéma demandé."},
        {"role": "user", "content": prompt},
    ]
    try:
        rendered = tokenizer.apply_chat_template(messages, tokenize=False, add_generation_prompt=True, enable_thinking=False)
    except TypeError:
        rendered = tokenizer.apply_chat_template(messages, tokenize=False, add_generation_prompt=True)
    inputs = tokenizer(rendered, return_tensors="pt")
    device = next(model.parameters()).device
    inputs = {key: value.to(device) for key, value in inputs.items()}
    outputs = model.generate(
        **inputs,
        max_new_tokens=max_new_tokens,
        do_sample=False,
        eos_token_id=tokenizer.eos_token_id,
        pad_token_id=tokenizer.pad_token_id or tokenizer.eos_token_id,
    )
    prompt_len = inputs["input_ids"].shape[-1]
    return tokenizer.decode(outputs[0][prompt_len:], skip_special_tokens=True).strip()


def generate_and_bake(tokenizer, model, manifest: dict[str, Any], profile_id: str, zone: str, archetype: str, locale: str, attempts: int = 3) -> tuple[dict[str, Any], str]:
    prompt = build_prompt(profile_id, zone, archetype, locale)
    errors: list[str] = []
    for attempt in range(1, attempts + 1):
        raw = generate_raw_text(tokenizer, model, prompt)
        try:
            draft = extract_json_object(raw)
            validate_generated_identity(draft, profile_id, zone, archetype, locale)
            draft = attach_generator_metadata(draft, manifest)
            baked = BAKER.bake_payload(draft)
            return baked, raw
        except (json.JSONDecodeError, BAKER.BakeError) as exc:
            errors.append(f"attempt {attempt}: {exc}")
            prompt += "\nLe précédent essai était invalide. Repars de zéro et respecte strictement le JSON et les 20 phrases uniques."
    raise BAKER.BakeError("Qwen pack generation failed: " + " | ".join(errors))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile-id", default="midi_qwen_01")
    parser.add_argument("--zone", default="midi")
    parser.add_argument("--archetype", choices=["civilian", "aggressive", "runner"], default="civilian")
    parser.add_argument("--locale", choices=["fr-BE", "nl-BE", "en"], default="fr-BE")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--raw-output", type=Path)
    args = parser.parse_args(argv)
    try:
        manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
        model_dir = ROOT / str(manifest["local_dir"])
        tokenizer, model = SERVER.load_local_model(model_dir)
        baked, raw = generate_and_bake(tokenizer, model, manifest, args.profile_id, args.zone, args.archetype, args.locale)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(baked, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        if args.raw_output is not None:
            args.raw_output.parent.mkdir(parents=True, exist_ok=True)
            args.raw_output.write_text(raw + "\n", encoding="utf-8")
    except (OSError, json.JSONDecodeError, RuntimeError, SERVER.RequestError, BAKER.BakeError) as exc:
        print(f"NPC_PACK_QWEN_FAIL: {exc}", file=sys.stderr)
        return 2
    profile = baked["profiles"][0]
    line_count = sum(len(lines) for lines in profile["dialogue"].values())
    print(f"NPC_PACK_QWEN_OK: profile={profile['id']} lines={line_count} model={baked['generator'].get('model', '')}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
