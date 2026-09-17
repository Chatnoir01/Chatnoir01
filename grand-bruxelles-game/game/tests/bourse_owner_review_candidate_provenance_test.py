#!/usr/bin/env python3
"""Fail-closed provenance guard for the historical Bourse owner-review candidate.

This guard does not promote or reconstruct the candidate. It records the live-main
truth that Bourse exact-location presentation remains owned by PR #880 and that
Shared Environment must not silently absorb its stale implementation history.
"""
from __future__ import annotations

import json
import unicodedata
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RECEIPT = ROOT / "data/qa/bourse_owner_review_candidate_provenance.json"
EXPECTED_HERITAGE_FACT = (
    "main boulevard facade: monumental stair leading to a peristyle limited by six "
    "Corinthian columns carrying a triangular pediment"
)
EXPECTED_KEYS = {
    "schema", "live_main_sha", "owner_pr", "owner_head_sha", "owner_base_sha",
    "candidate_status", "source_basis", "frozen_gate", "shared_environment_authorized",
    "runtime_merge_authorized", "visual_acceptance", "jouable_authorized", "next_action",
}


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"BOURSE_OWNER_REVIEW_PROVENANCE_FAIL: {message}")


def require_exact_string(value: object, expected: str, label: str) -> None:
    require(type(value) is str and value == expected, f"{label} drift")


def reject_duplicate_object_pairs(pairs: list[tuple[str, object]]) -> dict[str, object]:
    result: dict[str, object] = {}
    for key, value in pairs:
        require(type(key) is str, "JSON object key must be a string")
        require(key not in result, f"duplicate JSON key: {key}")
        result[key] = value
    return result


def reject_nonstandard_constant(value: str) -> object:
    raise SystemExit(f"BOURSE_OWNER_REVIEW_PROVENANCE_FAIL: non-standard JSON constant: {value}")


def load_strict_json(text: str) -> object:
    try:
        return json.loads(
            text,
            object_pairs_hook=reject_duplicate_object_pairs,
            parse_constant=reject_nonstandard_constant,
        )
    except (json.JSONDecodeError, UnicodeDecodeError) as exc:
        if isinstance(exc, json.JSONDecodeError):
            detail = f"line {exc.lineno} column {exc.colno}"
        else:
            detail = f"unicode decode error at byte {exc.start}"
        raise SystemExit(f"BOURSE_OWNER_REVIEW_PROVENANCE_FAIL: malformed JSON: {detail}") from None


def require_parser_rejects(text: str, expected_fragment: str) -> None:
    try:
        load_strict_json(text)
    except SystemExit as exc:
        require(expected_fragment in str(exc), f"parser rejection drift: {exc}")
        return
    require(False, f"strict parser accepted forbidden JSON: {text}")


def prove_strict_parser_fail_closed() -> None:
    """Executable regression proofs for ambiguity/non-standard/malformed JSON rejection."""
    require_parser_rejects('{"owner_pr":880,"owner_pr":2179}', "duplicate JSON key: owner_pr")
    require_parser_rejects(
        '{"shared_environment_authorized":false,"shared_environment_authoriz\\u0065d":true}',
        "duplicate JSON key: shared_environment_authorized",
    )
    require_parser_rejects('{"source_basis":{"heritage_record":"A001/31241","heritage_record":"spoof"}}', "duplicate JSON key: heritage_record")
    require_parser_rejects('{"shared_environment_authorized":false,"shared_environment_authorized":true}', "duplicate JSON key: shared_environment_authorized")
    require_parser_rejects('{"frozen_gate":{"bbox_px":[616,426],"bbox_px":[1,1]}}', "duplicate JSON key: bbox_px")
    for constant in ("NaN", "Infinity", "-Infinity"):
        require_parser_rejects(f'{{"changed_gt3":{constant}}}', f"non-standard JSON constant: {constant}")
    for malformed in ('{"owner_pr":880', '{"owner_pr":880,}', '{"owner_pr":880} trailing'):
        require_parser_rejects(malformed, "malformed JSON:")
    # Python's JSON decoder accepts lone UTF-16 surrogate escapes into str values.
    # They are not valid Unicode scalar values and must never enter provenance fields.
    for surrogate in ("\\ud800", "\\udfff"):
        parsed = load_strict_json(f'{{"owner_pr":880,"note":"{surrogate}"}}')
        require(type(parsed) is dict, "surrogate regression setup drift")
        note = parsed["note"]
        require(type(note) is str and any(0xD800 <= ord(ch) <= 0xDFFF for ch in note), "surrogate regression setup no longer reproduces")
    require(load_strict_json('{"owner_pr":880,"authorized":false}') == {"owner_pr": 880, "authorized": False}, "strict parser valid-control drift")


def require_unicode_scalars(value: object, path: str = "$") -> None:
    """Reject surrogate and invisible/control Unicode code points anywhere in provenance."""
    if type(value) is str:
        require(not any(0xD800 <= ord(ch) <= 0xDFFF for ch in value), f"invalid Unicode scalar in {path}")
        require(not any(unicodedata.category(ch).startswith("C") for ch in value), f"Unicode control/format code point in {path}")
    elif type(value) is dict:
        for key, child in value.items():
            require_unicode_scalars(key, f"{path}.<key>")
            require_unicode_scalars(child, f"{path}.{key}")
    elif type(value) is list:
        for index, child in enumerate(value):
            require_unicode_scalars(child, f"{path}[{index}]")


def prove_unicode_provenance_fail_closed() -> None:
    """Prove invisible formatting/control characters cannot hide provenance identity drift."""
    for escaped in ("\\u200b", "\\u202e", "\\u2066", "\\u0000"):
        parsed = load_strict_json(f'{{"heritage_record":"A001/31241{escaped}"}}')
        require(type(parsed) is dict, "Unicode-control regression setup drift")
        try:
            require_unicode_scalars(parsed)
        except SystemExit as exc:
            require("Unicode control/format code point" in str(exc), f"Unicode-control rejection drift: {exc}")
        else:
            require(False, f"Unicode-control provenance accepted: {escaped}")


def main() -> None:
    prove_strict_parser_fail_closed()
    prove_unicode_provenance_fail_closed()
    require(RECEIPT.is_file(), "receipt missing")
    data = load_strict_json(RECEIPT.read_text(encoding="utf-8"))
    require_unicode_scalars(data)
    require(type(data) is dict, "receipt must be an object")
    require(set(data) == EXPECTED_KEYS, "receipt keyset drift")
    require_exact_string(data["schema"], "grand-bruxelles-bourse-owner-review-provenance-v1", "schema")
    require_exact_string(data["live_main_sha"], "8938792700837c6e53bf9661f0c304dfeba84897", "live-main identity")
    require(type(data["owner_pr"]) is int and data["owner_pr"] == 880, "Bourse owner PR drift")
    require_exact_string(data["owner_head_sha"], "98b0d73fda776810c4cd20e244c209393d6d21d1", "owner head")
    require_exact_string(data["owner_base_sha"], "0807581e4a711d21b535a7def66f089da037a2f4", "owner base")
    require_exact_string(data["candidate_status"], "OPEN_DRAFT_STALE_OWNER_REVIEW", "candidate status")

    source = data["source_basis"]
    require(type(source) is dict and set(source) == {"heritage_record", "heritage_fact"}, "source basis drift")
    require_exact_string(source["heritage_record"], "A001/31241", "heritage record")
    require_exact_string(source["heritage_fact"], EXPECTED_HERITAGE_FACT, "heritage fact")

    gate = data["frozen_gate"]
    require(type(gate) is dict and set(gate) == {"changed_gt3", "changed_gt3_min", "changed_gt8", "changed_gt8_min", "bbox_px", "bbox_min_px"}, "gate keyset drift")
    for key, expected in (("changed_gt3", 0.008575), ("changed_gt3_min", 0.01), ("changed_gt8", 0.0084), ("changed_gt8_min", 0.005)):
        require(type(gate[key]) is float and gate[key] == expected, f"{key} measurement/type drift")
    require(type(gate["bbox_px"]) is list and gate["bbox_px"] == [616, 426] and all(type(v) is int for v in gate["bbox_px"]), "bbox_px drift")
    require(type(gate["bbox_min_px"]) is list and gate["bbox_min_px"] == [500, 40] and all(type(v) is int for v in gate["bbox_min_px"]), "bbox_min_px drift")

    for key in ("shared_environment_authorized", "runtime_merge_authorized", "visual_acceptance", "jouable_authorized"):
        require(data[key] is False, f"{key} must remain exact false")
    require_exact_string(data["next_action"], "OWNER_REVIEW_OR_CLEAN_CURRENT_MAIN_REBUILD_BY_BOURSE_OWNER", "next action")
    print("BOURSE_OWNER_REVIEW_PROVENANCE_OK")


if __name__ == "__main__":
    main()
