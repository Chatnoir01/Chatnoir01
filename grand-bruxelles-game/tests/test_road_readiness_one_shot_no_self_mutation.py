from pathlib import Path


WORKFLOW = Path(".github/workflows/grand-bruxelles-road-readiness-one-shot-persist.yml")


def main() -> None:
    text = WORKFLOW.read_text(encoding="utf-8")

    assert "pull_request:" in text, "road readiness verification must remain a PR gate"
    assert "contents: read" in text, "PR verification must be read-only"
    assert "contents: write" not in text, "PR verification must never receive contents write permission"

    forbidden = {
        "git push": "PR workflow must not recursively push a new head",
        "git commit": "PR workflow must not create bot-authored commits",
        "Persist exact proven readiness candidate once": "automatic persistence step must stay removed",
    }
    for token, message in forbidden.items():
        assert token not in text, message

    assert "Require persisted readiness lock already exact" in text
    assert "cmp \"$OUT\" \"$LOCK\"" in text
    assert "EXPECTED_SEMANTIC_SHA256" in text
    assert "road_cell_mapping_authorized" in text
    assert "jouable_promotion_authorized" in text

    print("ROAD_READINESS_PR_GATE_READ_ONLY_OK self_mutation=false rails_fail_closed=true")


if __name__ == "__main__":
    main()
