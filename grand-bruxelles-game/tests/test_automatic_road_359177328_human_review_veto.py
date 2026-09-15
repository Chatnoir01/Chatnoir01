import json
import math
import re
from contextlib import contextmanager
from pathlib import Path

REVIEW_PATH = Path(__file__).resolve().parents[1] / "data" / "qa" / "corridor" / "automatic_road_359177328_human_review.json"
GIT_SHA1_RE = re.compile(r"^[0-9a-f]{40}$")
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
DIGEST_RE = re.compile(r"^sha256:[0-9a-f]{64}$")
EXPECTED_REVIEW_KEYS = {"schema","reviewed_head_sha","workflow_run_id","artifact_id","artifact_name","artifact_digest","repository_id","head_repository_id","png_name","png_sha256","destination","osm_id","source_name","width","height","full_frame_inspected","verdict","rejection_reasons","rejection_reason_codes","camera_changed","source_geometry_changed","resolver_thresholds_lowered","destination_advertisable","runtime_mount_authorized","rendered_geometry_authorized","collision_authorized","safe_spawn_authorized","visual_acceptance","jouable_authorized"}

@contextmanager
def _raises_value_error(match=None):
    try: yield
    except ValueError as exc:
        if match is not None and re.search(match, str(exc)) is None: raise AssertionError(f"ValueError did not match {match!r}: {exc}") from exc
    else: raise AssertionError("expected ValueError")

def _reject_duplicate_keys(pairs):
    result = {}
    for key, value in pairs:
        if key in result: raise ValueError(f"duplicate JSON key: {key}")
        result[key] = value
    return result

def _reject_constant(value): raise ValueError(f"non-standard JSON constant: {value}")
def _finite_float(value):
    parsed = float(value)
    if not math.isfinite(parsed): raise ValueError(f"non-finite JSON number: {value}")
    return parsed

def _load_review_bytes(raw):
    review = json.loads(raw.decode("utf-8"), object_pairs_hook=_reject_duplicate_keys, parse_constant=_reject_constant, parse_float=_finite_float)
    if not isinstance(review, dict): raise ValueError("human review root must be an object")
    return review

def _require_positive_json_integer(review, field):
    value = review.get(field)
    if type(value) is not int or value <= 0: raise ValueError(f"{field} must be a positive JSON integer")
    return value

def _require_nonzero_hex(value, pattern, field):
    if not isinstance(value, str) or pattern.fullmatch(value) is None: raise ValueError(f"{field} must have the canonical digest form")
    payload = value.removeprefix("sha256:")
    if set(payload) == {"0"}: raise ValueError(f"{field} cannot be an all-zero sentinel")
    return value

def test_lemonnier_human_review_parser_fails_closed():
    canonical = REVIEW_PATH.read_bytes(); assert _load_review_bytes(canonical)["verdict"] == "REJECT"
    duplicate = canonical.replace(b'"verdict": "REJECT",', b'"verdict": "REJECT",\n  "verdict": "KEEP",', 1)
    with _raises_value_error("duplicate JSON key: verdict"): _load_review_bytes(duplicate)
    for bad in (b"NaN", b"Infinity", b"-Infinity", b"1e309", b"-1e309"):
        with _raises_value_error(): _load_review_bytes(canonical.replace(b'"width": 1280', b'"width": '+bad, 1))
def test_lemonnier_human_review_schema_is_closed(): assert set(_load_review_bytes(REVIEW_PATH.read_bytes())) == EXPECTED_REVIEW_KEYS
def test_lemonnier_human_review_reject_remains_fail_closed():
    review = _load_review_bytes(REVIEW_PATH.read_bytes())
    assert review["destination"] == "road-359177328" and _require_positive_json_integer(review,"osm_id") == 359177328
    assert review["verdict"] == "REJECT" and review["full_frame_inspected"] is True
    assert review["rejection_reason_codes"] == ["foreground_open_area_dominance","urban_mass_sparse_or_distant"]
    for field, pattern in (("reviewed_head_sha",GIT_SHA1_RE),("png_sha256",SHA256_RE),("artifact_digest",DIGEST_RE)): _require_nonzero_hex(review[field],pattern,field)
    for field in ("workflow_run_id","artifact_id","repository_id","head_repository_id","width","height"): _require_positive_json_integer(review,field)
    for field in ("destination_advertisable","runtime_mount_authorized","rendered_geometry_authorized","collision_authorized","safe_spawn_authorized","visual_acceptance","jouable_authorized"): assert review[field] is False
    assert review["camera_changed"] is False and review["source_geometry_changed"] is False and review["resolver_thresholds_lowered"] is False

def main():
    test_lemonnier_human_review_parser_fails_closed(); test_lemonnier_human_review_schema_is_closed(); test_lemonnier_human_review_reject_remains_fail_closed()
    print("AUTOMATIC_ROAD_359177328_HUMAN_REVIEW_VETO_GREEN"); return 0
if __name__ == "__main__": raise SystemExit(main())
