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
        "6040021f3cbfc16a752bfcc1e489f6a4a9aad5db0a2d708b07b12ca73d4eb5df": "workflow must not retain the pre-successor readiness raw lock",
        "0c16d8c14fe6195e40b58e4b11bbcb0b67a5756f4b4fff8132a0122f9ca98f1e": "workflow must not retain the pre-successor semantic lock",
        "mapped_road_count']==56": "workflow must not retain the pre-successor 56-road assumption",
        "mapped_cell_count']==3": "workflow must not retain the pre-successor 3-cell assumption",
    }
    for token, message in forbidden.items():
        assert token not in text, message

    assert "Require persisted readiness lock already exact" in text
    assert "cmp \"$OUT\" \"$LOCK\"" in text
    assert "PERSISTED_READINESS_SEMANTIC" in text
    assert "PERSISTED_CROSSWALK_SEMANTIC" in text
    assert "destination_count']==crosswalk['mapped_road_count']==96" in text
    assert "mapped_cell_count']==crosswalk['mapped_cell_count']==4" in text
    assert "road_cell_mapping_authorized" in text
    assert "jouable_promotion_authorized" in text

    print("ROAD_READINESS_PR_GATE_READ_ONLY_OK self_mutation=false rails_fail_closed=true successor_pair=true")


if __name__ == "__main__":
    main()
