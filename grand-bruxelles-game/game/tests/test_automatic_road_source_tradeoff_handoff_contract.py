from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
WORKFLOW = ROOT / ".github/workflows/grand-bruxelles-automatic-road-source-longitudinal-safety-tradeoff.yml"
VALIDATOR = ROOT / "grand-bruxelles-game/game/tests/validate_automatic_road_source_tradeoff_receipt.py"


def require(text: str, token: str) -> None:
    if token not in text:
        raise AssertionError(f"missing fail-closed handoff contract token: {token}")


def main() -> None:
    text = WORKFLOW.read_text(encoding="utf-8")
    validator = VALIDATOR.read_text(encoding="utf-8")

    # The source-coverage blocker is only durable if the receipt is bound to the
    # exact source/index bytes and to the exact diagnostic road identity.
    for token in (
        "source_document_sha256",
        "runtime_index_sha256",
        "diagnostic road must resolve to exactly one exact source document",
        "runtime-index source SHA does not match exact source bytes",
        "diagnostic road must exist exactly once in exact OSM source",
        "OpenStreetMap contributors via Overpass API",
        "ODbL-1.0",
        "grand-bruxelles-road-runtime-index-v1",
        "source_lookup_only",
        "BALANCED_CONTEXT_REQUIRES_SOURCE_VIEW_SAFETY_LOSS_GT_EPSILON",
        "SOURCE_VIEW_CORRIDOR_SAFETY_PRECEDES_NETWORK_CONTINUATION_AND_VISUAL_CONTEXT",
        "resolver_mutation_allowed': False",
        "destination_advertisable': False",
        "visual_acceptance': False",
        "jouable': False",
    ):
        require(text, token)

    # The semantic validator must tolerate only the bounded quantization error
    # introduced by the receipt's 3-decimal candidate clearances. This is a QA
    # serialization tolerance, not a gameplay-safety threshold change.
    require(validator, "RELATIVE_GAP_ABS_TOLERANCE = 5e-6")
    require(validator, "serialized-clearance quantization bound")

    # The handoff may never silently turn a source-only runtime index into a
    # downstream authorization boundary.
    for forbidden in (
        "'collision_authorized': True",
        "'jouable_authorized': True",
        "'render_authorized': True",
        "'runtime_mount_authorized': True",
        "'safe_spawn_authorized': True",
        "'resolver_mutation_allowed': True",
        "'destination_advertisable': True",
        "'visual_acceptance': True",
        "'jouable': True",
    ):
        if forbidden in text:
            raise AssertionError(f"forbidden authorization in source blocker handoff: {forbidden}")

    print("AUTOMATIC_ROAD_SOURCE_TRADEOFF_HANDOFF_CONTRACT_GREEN")


if __name__ == "__main__":
    main()
