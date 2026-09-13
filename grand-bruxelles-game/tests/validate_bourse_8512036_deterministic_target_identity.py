#!/usr/bin/env python3
import argparse
import copy
import hashlib
from pathlib import Path

from validate_bourse_8512036_deterministic_candidate import (
    distance,
    verify as verify_candidate,
)
from validate_bourse_8512036_masked_native_receipt import (
    finite_pair,
    strict_json_loads,
    verify as verify_native_receipt,
)

TARGET_IDENTITY_EPSILON_M = 0.001


def verify_source_bytes(source_raw, expected_source_sha):
    assert isinstance(source_raw, bytes), "source bytes required"
    assert isinstance(expected_source_sha, str) and len(expected_source_sha) == 64, "expected source SHA-256 malformed"
    try:
        int(expected_source_sha, 16)
    except ValueError as exc:
        raise AssertionError("expected source SHA-256 malformed") from exc
    measured = hashlib.sha256(source_raw).hexdigest()
    assert measured == expected_source_sha.lower(), (
        f"source SHA-256 drift: expected={expected_source_sha.lower()} actual={measured}"
    )
    return measured


def load_locked_source_doc(source_raw, expected_source_sha):
    # The semantic verifier must derive its document from the exact hash-bound
    # bytes itself. Accepting a caller-supplied parsed dict would allow direct
    # imports to bypass source-byte identity even though the CLI is strict.
    verify_source_bytes(source_raw, expected_source_sha)
    return strict_json_loads(source_raw.decode("utf-8", errors="strict"))


def verify(receipt, source_raw, expected_source_sha):
    source_doc = load_locked_source_doc(source_raw, expected_source_sha)
    # Compose the target-identity proof on top of the complete native receipt
    # contract. This prevents this dedicated gate from becoming a parallel,
    # weaker acceptance path for a receipt whose target happens to be correct.
    verify_native_receipt(receipt, source_doc, expected_source_sha)
    candidate = verify_candidate(receipt, source_doc)
    target = receipt.get("target_xz")
    assert finite_pair(target), "receipt target_xz missing or non-finite"
    measured = distance(target, candidate["target"])
    assert measured <= TARGET_IDENTITY_EPSILON_M, (
        f"deterministic target drift: {measured:.9f} m; expected={candidate['target']} actual={target}"
    )
    return candidate


def assert_rejected(mutated, source_raw, expected_source_sha, label):
    try:
        verify(mutated, source_raw, expected_source_sha)
    except (AssertionError, KeyError, UnicodeDecodeError):
        return
    raise AssertionError(f"forged deterministic target receipt accepted: {label}")


def self_test(receipt, source_raw, expected_source_sha):
    verify(receipt, source_raw, expected_source_sha)

    # Causal source-byte regression: semantically equivalent or otherwise valid
    # JSON bytes are still a different locked source and must not inherit the
    # expected source SHA merely because the caller supplied it as an argument.
    try:
        verify(receipt, source_raw + b"\n", expected_source_sha)
    except AssertionError:
        pass
    else:
        raise AssertionError("modified source bytes accepted under locked source SHA")

    # Causal verifier-boundary regression: direct callers must not be able to
    # substitute an already-parsed document that bypasses byte identity.
    source_doc = strict_json_loads(source_raw.decode("utf-8", errors="strict"))
    forged_source_doc = copy.deepcopy(source_doc)
    forged_source_doc["_forged_unhashed_semantic_mutation"] = True
    try:
        verify(receipt, forged_source_doc, expected_source_sha)
    except AssertionError as exc:
        assert "source bytes required" in str(exc), f"unexpected parsed-source rejection: {exc}"
    else:
        raise AssertionError("parsed source document accepted by byte-bound deterministic target verifier")

    bad = copy.deepcopy(receipt)
    target = bad["target_xz"]
    bad["target_xz"] = [float(target[0]) + 100.0, float(target[1])]
    assert_rejected(bad, source_raw, expected_source_sha, "target_drift")

    # Causal composition regression: the target can remain exactly correct while
    # a native no-mutation rail is forged. The target gate must still fail.
    bad = copy.deepcopy(receipt)
    bad["camera_changed"] = True
    assert_rejected(bad, source_raw, expected_source_sha, "native_receipt_camera_mutation")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--receipt", required=True)
    parser.add_argument("--source", required=True)
    parser.add_argument("--source-sha", required=True)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()

    receipt = strict_json_loads(Path(args.receipt).read_text(encoding="utf-8"))
    source_raw = Path(args.source).read_bytes()
    candidate = verify(receipt, source_raw, args.source_sha)
    if args.self_test:
        self_test(receipt, source_raw, args.source_sha)
    print(
        "BOURSE_8512036_DETERMINISTIC_TARGET_IDENTITY_GREEN "
        f"target=({candidate['target'][0]:.6f},{candidate['target'][1]:.6f}) "
        f"epsilon_m={TARGET_IDENTITY_EPSILON_M:.6f} native_receipt_composed=true "
        "source_bytes_sha_bound=true verifier_source_bytes_required=true"
    )


if __name__ == "__main__":
    main()
