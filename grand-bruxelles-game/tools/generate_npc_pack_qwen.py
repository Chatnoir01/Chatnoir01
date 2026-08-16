#!/usr/bin/env python3
"""Generate a complete NPC profile with the pinned local Qwen model, then bake it.

The game owns the schema. Qwen only authors bounded content fields: persona text,
three thresholds and twenty short dialogue lines. The resulting draft must still
pass `bake_npc_pack.py` before it can become runtime data.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import re
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
SERVER_PATH = ROOT / "tools" / "npc_llm_server.py"
BAKER_PATH = ROOT / "tools" / "bake_npc_pack.py"
MANIFEST_PATH = ROOT / "data" / "ai" / "npc_llm_model.json"
INTENTS = ("greeting", "smalltalk", "warning", "hurt", "police")
FORBIDDEN = (
    "je suis une ia",
    "intelligence artificielle",
    "je suis un modèle",
    "je suis un modele",
    "modèle de langage",
    "modele de langage",
    "mon prompt",
    "system prompt",
    "prompt système",
    "prompt systeme",
)
INTENT_CUES: dict[str, tuple[str, ...]] = {
    "greeting": (),
    "smalltalk": (),
    "warning": ("recule", "calme", "distance", "doucement", "arrête", "arrete", "stop", "attention"),
    "hurt": ("aïe", "aie", "mal", "douleur", "arrête", "arrete", "laisse-moi", "laisse moi"),
    "police": ("police", "agent", "patrouille", "sirène", "sirene", "flic"),
}
INTENT_RULES = {
    "greeting": "Salue ou réponds simplement. Tu peux dire bonjour, salut, bonsoir ou inviter la personne à parler.",
    "smalltalk": "Parle du quotidien, du trajet, de Midi ou de Bruxelles. Ne te présente pas à nouveau.",
    "warning": "Chaque phrase doit clairement demander de reculer, se calmer, garder ses distances ou faire attention. Ne te présente pas.",
    "hurt": "Chaque phrase doit clairement exprimer une douleur ou demander d'arrêter. Ne te présente pas.",
    "police": "Chaque phrase doit explicitement parler de la police, d'un agent, d'une patrouille ou d'une sirène. Ne te présente pas.",
}
LINE_PREFIX_RE = re.compile(r"^\s*(?:[-*•]|\d+[.)-])\s*")
THRESHOLD_RE = re.compile(r"\b(fear|aggression|flee_health)\s*[:=]\s*(0(?:[.,]\d+)?|1(?:[.,]0+)?)\b", re.IGNORECASE)
JSON_LINE_KEYS = {"lines", "phrases", "text", "line", *INTENTS}


class GenerationError(ValueError):
    pass


def _load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


SERVER = _load_module("npc_llm_server_for_pack", SERVER_PATH)
BAKER = _load_module("bake_npc_pack_for_qwen", BAKER_PATH)


def _clean_text(value: str, limit: int = 180) -> str:
    value = value.strip().strip('"').strip("'").strip()
    value = " ".join(value.split())
    if not value or len(value) > limit:
        return ""
    lowered = value.casefold()
    if any(token in lowered for token in FORBIDDEN):
        return ""
    return value


def _matches_intent(line: str, intent: str) -> bool:
    cues = INTENT_CUES.get(intent, ())
    if not cues:
        return True
    lowered = line.casefold()
    return any(cue in lowered for cue in cues)


def parse_persona_output(raw: str) -> dict[str, str]:
    name = ""
    summary = ""
    for source_line in raw.replace("\r", "").splitlines():
        line = source_line.strip()
        lowered = line.casefold()
        if lowered.startswith(("name:", "prénom:", "prenom:")):
            name = _clean_text(line.split(":", 1)[1], 80)
        elif lowered.startswith(("summary:", "résumé:", "resume:")):
            summary = _clean_text(line.split(":", 1)[1], 240)
    if not name or not summary:
        raise GenerationError("persona output must contain name and summary")
    return {"name": name, "summary": summary}


def parse_threshold_output(raw: str) -> dict[str, float]:
    values: dict[str, float] = {}
    for key, raw_value in THRESHOLD_RE.findall(raw):
        values[key.lower()] = float(raw_value.replace(",", "."))
    required = {"fear", "aggression", "flee_health"}
    if set(values) != required:
        raise GenerationError("threshold output must contain fear, aggression and flee_health")
    if any(value < 0.0 or value > 1.0 for value in values.values()):
        raise GenerationError("threshold outside 0..1")
    return {key: round(values[key], 4) for key in ("fear", "aggression", "flee_health")}


def _strip_code_fence(raw: str) -> str:
    candidate = raw.strip()
    if candidate.startswith("```"):
        lines = candidate.splitlines()
        if lines and lines[0].startswith("```"):
            lines = lines[1:]
        if lines and lines[-1].strip() == "```":
            lines = lines[:-1]
        candidate = "\n".join(lines).strip()
    return candidate


def _collect_json_strings(value: Any, trusted: bool = False) -> list[str]:
    result: list[str] = []
    if isinstance(value, str):
        if trusted:
            result.append(value)
        return result
    if isinstance(value, list):
        for item in value:
            result.extend(_collect_json_strings(item, True))
        return result
    if isinstance(value, dict):
        for raw_key, item in value.items():
            key = str(raw_key).casefold()
            if trusted or key in JSON_LINE_KEYS or key.isdigit():
                result.extend(_collect_json_strings(item, True))
        return result
    return result


def parse_dialogue_lines(raw: str) -> list[str]:
    result: list[str] = []
    candidate = _strip_code_fence(raw)
    if candidate.startswith(("[", "{")):
        try:
            parsed = json.loads(candidate)
        except json.JSONDecodeError:
            parsed = None
        if parsed is not None:
            for value in _collect_json_strings(parsed):
                line = _clean_text(value, 180)
                if line and line.casefold() not in INTENTS and line not in result:
                    result.append(line)
    for source_line in candidate.replace("\r", "").splitlines():
        line = source_line.strip()
        if not line or line.startswith("```") or line.startswith(("[", "{", "]", "}")):
            continue
        line = LINE_PREFIX_RE.sub("", line).strip().rstrip(",")
        if line.casefold().startswith(("phrases:", "répliques:", "repliques:")):
            continue
        line = _clean_text(line, 180)
        if line and line.casefold() not in INTENTS and line not in result:
            result.append(line)
    return result


def build_persona_prompt(zone: str, archetype: str) -> str:
    return f"""Crée une persona crédible pour un habitant de Bruxelles, zone {zone}, archétype {archetype}.
Réponds EXACTEMENT en deux lignes, rien d'autre:
name: <prénom humain crédible>
summary: <une phrase courte décrivant caractère, quartier et attitude>
Ne mentionne jamais IA, modèle ou prompt."""


def build_threshold_prompt(zone: str, archetype: str, summary: str) -> str:
    return f"""Choisis trois seuils comportementaux cohérents pour ce PNJ de Bruxelles.
Zone: {zone}. Archétype: {archetype}. Persona: {summary}
Chaque nombre doit être entre 0.0 et 1.0.
Réponds EXACTEMENT en trois lignes, rien d'autre:
fear: 0.x
aggression: 0.x
flee_health: 0.x"""


def build_dialogue_prompt(
    intent: str,
    zone: str,
    archetype: str,
    persona: dict[str, str],
    needed: int,
    used: list[str],
    rejected: list[str] | None = None,
) -> str:
    rejected = rejected or []
    already = "\n".join(f"- {line}" for line in used[-12:]) if used else "(aucune)"
    refused = "\n".join(f"- {line}" for line in rejected[-8:]) if rejected else "(aucune)"
    cue_rule = ""
    cues = INTENT_CUES.get(intent, ())
    if cues:
        cue_rule = "\nChaque phrase doit contenir au moins un de ces indices sémantiques: " + ", ".join(cues) + "."
    return f"""Tu écris des répliques courtes pour {persona['name']}, habitant de Bruxelles.
Zone: {zone}. Archétype: {archetype}. Persona: {persona['summary']}
Intention imposée: {intent}.
Règle de sens: {INTENT_RULES[intent]}{cue_rule}
Il me faut exactement {needed} NOUVELLES phrases françaises naturelles, orales et différentes.

Phrases déjà utilisées à ne jamais répéter:
{already}

Phrases déjà refusées pour mauvais sens ou répétition, à ne jamais reproduire:
{refused}

Réponds uniquement avec {needed} lignes commençant chacune par '- '.
Aucune explication, aucun JSON, aucune présentation du personnage, aucune mention d'IA/modèle/prompt, aucune action technique."""


def _chat_completion(tokenizer, model, prompt: str, max_new_tokens: int) -> str:
    messages = [
        {"role": "system", "content": "Tu écris du contenu court et naturel pour des PNJ bruxellois. Tu respectes exactement le format et l'intention demandés."},
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


def generate_persona(tokenizer, model, zone: str, archetype: str, attempts: int = 3) -> tuple[dict[str, str], str]:
    prompt = build_persona_prompt(zone, archetype)
    errors: list[str] = []
    raw = ""
    for attempt in range(1, attempts + 1):
        raw = _chat_completion(tokenizer, model, prompt, 80)
        try:
            return parse_persona_output(raw), raw
        except GenerationError as exc:
            errors.append(f"attempt {attempt}: {exc}")
            prompt += "\nTon précédent format était invalide. Recommence avec exactement name: puis summary:."
    raise GenerationError("persona generation failed: " + " | ".join(errors))


def generate_thresholds(tokenizer, model, zone: str, archetype: str, summary: str, attempts: int = 3) -> tuple[dict[str, float], str]:
    prompt = build_threshold_prompt(zone, archetype, summary)
    errors: list[str] = []
    raw = ""
    for attempt in range(1, attempts + 1):
        raw = _chat_completion(tokenizer, model, prompt, 48)
        try:
            return parse_threshold_output(raw), raw
        except GenerationError as exc:
            errors.append(f"attempt {attempt}: {exc}")
            prompt += "\nFormat invalide. Recommence uniquement avec les trois clés imposées et des nombres 0..1."
    raise GenerationError("threshold generation failed: " + " | ".join(errors))


def generate_intent_lines(
    tokenizer,
    model,
    intent: str,
    zone: str,
    archetype: str,
    persona: dict[str, str],
    globally_used: list[str],
    target: int = 4,
    attempts: int = 5,
) -> tuple[list[str], list[str]]:
    collected: list[str] = []
    raw_attempts: list[str] = []
    rejected: list[str] = []
    duplicate_count = 0
    semantic_reject_count = 0
    parsed_count = 0
    for attempt in range(1, attempts + 1):
        needed = target - len(collected)
        if needed <= 0:
            break
        prompt = build_dialogue_prompt(intent, zone, archetype, persona, needed, globally_used + collected, rejected)
        prompt += f"\nEssai {attempt}/{attempts}: produis uniquement des phrases nouvelles qui respectent l'intention {intent}."
        raw = _chat_completion(tokenizer, model, prompt, max(56, needed * 36))
        raw_attempts.append(raw)
        parsed = parse_dialogue_lines(raw)
        parsed_count += len(parsed)
        for candidate in parsed:
            if candidate in globally_used or candidate in collected:
                duplicate_count += 1
                if candidate not in rejected:
                    rejected.append(candidate)
                continue
            if not _matches_intent(candidate, intent):
                semantic_reject_count += 1
                if candidate not in rejected:
                    rejected.append(candidate)
                continue
            collected.append(candidate)
            if len(collected) == target:
                break
    if len(collected) != target:
        last_raw = raw_attempts[-1][-600:] if raw_attempts else "<no output>"
        raise GenerationError(
            f"{intent} generation produced {len(collected)}/{target} unique semantic lines; "
            f"parsed={parsed_count} duplicates={duplicate_count} semantic_rejects={semantic_reject_count}; "
            f"last_raw={last_raw!r}"
        )
    return collected, raw_attempts


def attach_generator_metadata(draft: dict[str, Any], manifest: dict[str, Any]) -> dict[str, Any]:
    result = json.loads(json.dumps(draft, ensure_ascii=False))
    result["generator"] = {
        "provider": "local_qwen",
        "model": str(manifest["repo_id"]),
        "revision": str(manifest["revision"]),
        "run_id": "local-pack-generation",
    }
    return result


def generate_and_bake(tokenizer, model, manifest: dict[str, Any], profile_id: str, zone: str, archetype: str, locale: str) -> tuple[dict[str, Any], str]:
    persona, persona_raw = generate_persona(tokenizer, model, zone, archetype)
    thresholds, thresholds_raw = generate_thresholds(tokenizer, model, zone, archetype, persona["summary"])
    dialogue: dict[str, list[str]] = {}
    used: list[str] = []
    raw_sections: list[str] = ["[persona]\n" + persona_raw, "[thresholds]\n" + thresholds_raw]
    for intent in INTENTS:
        lines, attempts = generate_intent_lines(tokenizer, model, intent, zone, archetype, persona, used)
        dialogue[intent] = lines
        used.extend(lines)
        raw_sections.append(f"[{intent}]\n" + "\n--- retry ---\n".join(attempts))
    draft = {
        "profiles": [{
            "id": profile_id,
            "zone": zone,
            "locale": locale,
            "archetype": archetype,
            "persona": persona,
            "thresholds": thresholds,
            "dialogue": dialogue,
        }]
    }
    draft = attach_generator_metadata(draft, manifest)
    baked = BAKER.bake_payload(draft)
    return baked, "\n\n".join(raw_sections)


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
    except (OSError, json.JSONDecodeError, RuntimeError, SERVER.RequestError, BAKER.BakeError, GenerationError) as exc:
        print(f"NPC_PACK_QWEN_FAIL: {exc}", file=sys.stderr)
        return 2
    profile = baked["profiles"][0]
    line_count = sum(len(lines) for lines in profile["dialogue"].values())
    print(f"NPC_PACK_QWEN_OK: profile={profile['id']} lines={line_count} model={baked['generator'].get('model', '')}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
