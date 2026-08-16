#!/usr/bin/env python3
"""Local-only Qwen NPC inference service for Grand Bruxelles.

The server never downloads a model. It loads the pinned model from the gitignored
`models/` directory with `local_files_only=True`. Game rules remain authoritative:
this service only proposes raw `action + line` text; Godot validates it.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
MANIFEST_PATH = ROOT / "data" / "ai" / "npc_llm_model.json"
SAFE_ID = re.compile(r"^[A-Za-z0-9_-]{1,64}$")
ALLOWED_ACTIONS = ("idle", "walk", "alert", "defend", "fight", "flee", "hurt")
MAX_USER_MESSAGE = 320
MAX_MEMORY = 4
MAX_BODY_BYTES = 32768


class RequestError(ValueError):
    pass


def load_manifest(path: Path = MANIFEST_PATH) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict) or payload.get("schema") != "grand-bruxelles-npc-llm-model-v1":
        raise RequestError("invalid model manifest")
    return payload


def validate_request(payload: dict[str, Any]) -> dict[str, Any]:
    if not isinstance(payload, dict):
        raise RequestError("request must be an object")
    npc_id = str(payload.get("npc_id", "")).strip()
    if not SAFE_ID.fullmatch(npc_id):
        raise RequestError("invalid npc_id")

    persona_value = payload.get("persona", {})
    if not isinstance(persona_value, dict):
        raise RequestError("persona must be an object")
    name = str(persona_value.get("name", "")).strip()
    zone = str(persona_value.get("zone", "")).strip()
    if not name or len(name) > 80 or not SAFE_ID.fullmatch(zone):
        raise RequestError("invalid persona")

    blackboard = payload.get("blackboard", {})
    if not isinstance(blackboard, dict):
        raise RequestError("blackboard must be an object")

    user_message = str(payload.get("user_message", "")).strip()
    if not user_message or len(user_message) > MAX_USER_MESSAGE:
        raise RequestError("user message outside contract")

    memory_value = payload.get("memory", [])
    if not isinstance(memory_value, list):
        raise RequestError("memory must be an array")
    memory: list[dict[str, str]] = []
    for row in memory_value[-MAX_MEMORY:]:
        if not isinstance(row, dict):
            continue
        user = str(row.get("user", "")).strip()[:MAX_USER_MESSAGE]
        action = str(row.get("action", "idle")).strip()
        line = str(row.get("line", "")).strip()[:180]
        if user and action in ALLOWED_ACTIONS and line:
            memory.append({"user": user, "action": action, "line": line})

    return {
        "npc_id": npc_id,
        "persona": {"name": name, "zone": zone},
        "blackboard": dict(blackboard),
        "memory": memory,
        "user_message": user_message,
    }


def build_system_prompt(name: str, zone: str) -> str:
    return (
        f"Tu es {name}, habitant de Bruxelles, dans le quartier/zone {zone}.\n"
        "Tu n'es pas une IA. Tu ne le sais pas. Tu ne le dis jamais.\n"
        "Tu as un corps, des peurs, un quartier.\n"
        "Réponds court, oral, naturel, en français.\n"
        "Si on parle d'IA, de modèle ou de prompt, tu ne comprends pas.\n"
        "Les règles et le blackboard du jeu sont autoritatifs. Tu proposes seulement; le jeu décide.\n"
        "Réponds EXACTEMENT avec deux lignes et rien d'autre :\n"
        "action: <idle|walk|alert|defend|fight|flee|hurt>\n"
        "line: <phrase française courte>"
    )


def build_messages(request: dict[str, Any]) -> list[dict[str, str]]:
    persona = request["persona"]
    messages: list[dict[str, str]] = [
        {"role": "system", "content": build_system_prompt(persona["name"], persona["zone"])}
    ]
    for row in request["memory"][-MAX_MEMORY:]:
        messages.append({"role": "user", "content": row["user"]})
        messages.append(
            {
                "role": "assistant",
                "content": f"action: {row['action']}\nline: {row['line']}",
            }
        )
    blackboard = json.dumps(request["blackboard"], ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    messages.append(
        {
            "role": "user",
            "content": (
                "Blackboard de jeu autoritatif : "
                + blackboard
                + "\nMessage du joueur : "
                + request["user_message"]
            ),
        }
    )
    return messages


def parse_two_line_output(text: str) -> dict[str, str]:
    lines = [line.strip() for line in text.strip().splitlines() if line.strip()]
    if len(lines) != 2 or not lines[0].startswith("action:") or not lines[1].startswith("line:"):
        raise RequestError("model output is not the forced two-line format")
    action = lines[0][len("action:") :].strip()
    line = lines[1][len("line:") :].strip()
    if action not in ALLOWED_ACTIONS or not line or len(line) > 180:
        raise RequestError("model output escaped the proposal contract")
    return {"action": action, "line": line}


def load_local_model(model_dir: Path):
    os.environ["HF_HUB_OFFLINE"] = "1"
    os.environ["TRANSFORMERS_OFFLINE"] = "1"
    try:
        from transformers import AutoModelForCausalLM, AutoTokenizer
    except ImportError as exc:
        raise RequestError(
            "transformers is required; install transformers and CPU torch before starting the local server"
        ) from exc
    if not (model_dir / "model.safetensors").exists():
        raise RequestError(f"local model missing at {model_dir}; run tools/download_npc_llm.py first")
    tokenizer = AutoTokenizer.from_pretrained(str(model_dir), local_files_only=True)
    model = AutoModelForCausalLM.from_pretrained(str(model_dir), local_files_only=True, device_map=None)
    model.eval()
    return tokenizer, model


def generate_text(tokenizer, model, request: dict[str, Any], max_new_tokens: int = 64) -> str:
    messages = build_messages(request)
    try:
        inputs = tokenizer.apply_chat_template(
            messages,
            add_generation_prompt=True,
            tokenize=True,
            return_dict=True,
            return_tensors="pt",
            enable_thinking=False,
        )
    except TypeError:
        inputs = tokenizer.apply_chat_template(
            messages,
            add_generation_prompt=True,
            tokenize=True,
            return_dict=True,
            return_tensors="pt",
        )
    device = next(model.parameters()).device
    inputs = {key: value.to(device) for key, value in inputs.items()}
    outputs = model.generate(
        **inputs,
        max_new_tokens=max_new_tokens,
        do_sample=False,
        pad_token_id=tokenizer.pad_token_id or tokenizer.eos_token_id,
    )
    prompt_length = inputs["input_ids"].shape[-1]
    return tokenizer.decode(outputs[0][prompt_length:], skip_special_tokens=True).strip()


class NpcLlmHandler(BaseHTTPRequestHandler):
    tokenizer = None
    model = None
    max_new_tokens = 64

    def log_message(self, format: str, *args) -> None:  # noqa: A003
        sys.stdout.write("NPC_LLM_HTTP: " + (format % args) + "\n")

    def _write_json(self, code: int, payload: dict[str, Any]) -> None:
        raw = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def do_POST(self) -> None:  # noqa: N802
        if self.path != "/v1/npc/respond":
            self._write_json(404, {"error": "not_found"})
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            if length <= 0 or length > MAX_BODY_BYTES:
                raise RequestError("request body outside size contract")
            body = self.rfile.read(length)
            payload = json.loads(body.decode("utf-8"))
            request = validate_request(payload)
            text = generate_text(self.tokenizer, self.model, request, self.max_new_tokens)
            # This parser is a server smoke guard only. Godot repeats the authoritative filter.
            parse_two_line_output(text)
            self._write_json(200, {"npc_id": request["npc_id"], "text": text})
        except (UnicodeError, json.JSONDecodeError, RequestError) as exc:
            self._write_json(400, {"error": str(exc)})
        except Exception as exc:  # inference boundary: fail closed to Godot fallback
            self._write_json(500, {"error": f"inference_failed: {type(exc).__name__}"})


def smoke(model_dir: Path, max_new_tokens: int) -> int:
    tokenizer, model = load_local_model(model_dir)
    request = validate_request(
        {
            "npc_id": "npc-smoke-01",
            "persona": {"name": "Nora", "zone": "jette"},
            "blackboard": {
                "threat": 0.2,
                "health": 100.0,
                "police_nearby": False,
                "distance_to_player": 1.4,
                "zone": "jette",
            },
            "memory": [],
            "user_message": "Salut, tu habites dans le coin ?",
        }
    )
    text = generate_text(tokenizer, model, request, max_new_tokens=max_new_tokens)
    parsed = parse_two_line_output(text)
    print("NPC_LLM_REAL_SMOKE_OK: action=%s line=%s" % (parsed["action"], parsed["line"]))
    return 0


def main(argv: list[str] | None = None) -> int:
    manifest = load_manifest()
    runtime = manifest.get("runtime", {})
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model-dir", type=Path, default=ROOT / str(manifest["local_dir"]))
    parser.add_argument("--host", default=str(runtime.get("host", "127.0.0.1")))
    parser.add_argument("--port", type=int, default=int(runtime.get("port", 8765)))
    parser.add_argument("--smoke", action="store_true")
    args = parser.parse_args(argv)

    try:
        if args.smoke:
            return smoke(args.model_dir, int(runtime.get("max_new_tokens", 64)))
        tokenizer, model = load_local_model(args.model_dir)
    except (OSError, json.JSONDecodeError, RequestError) as exc:
        print(f"NPC_LLM_SERVER_FAIL: {exc}", file=sys.stderr)
        return 2

    NpcLlmHandler.tokenizer = tokenizer
    NpcLlmHandler.model = model
    NpcLlmHandler.max_new_tokens = int(runtime.get("max_new_tokens", 64))
    server = ThreadingHTTPServer((args.host, args.port), NpcLlmHandler)
    print(
        "NPC_LLM_SERVER_READY: host=%s port=%d model=%s revision=%s"
        % (args.host, args.port, manifest["repo_id"], manifest["revision"])
    )
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
