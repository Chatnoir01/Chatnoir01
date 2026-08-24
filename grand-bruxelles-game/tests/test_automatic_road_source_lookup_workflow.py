from pathlib import Path

WORKFLOW = Path('.github/workflows/grand-bruxelles-automatic-road-source-lookup.yml')


def require(fragment: str, text: str) -> None:
    if fragment not in text:
        raise AssertionError(f'missing fail-closed workflow contract: {fragment}')


def main() -> None:
    text = WORKFLOW.read_text(encoding='utf-8')
    require('ref: ${{ github.event.pull_request.head.sha || github.sha }}', text)
    require('fetch-depth: 0', text)
    require('git fetch --no-tags origin main', text)
    require('LIVE_MAIN_SHA="$(git rev-parse origin/main)"', text)
    require('git merge-base --is-ancestor "$LIVE_MAIN_SHA" HEAD', text)
    require('RED: automatic road source lookup candidate does not contain live main', text)
    print('AUTOMATIC_ROAD_SOURCE_LOOKUP_WORKFLOW_CONTRACT_OK: exact_pr_head=true live_main_ancestry=true')


if __name__ == '__main__':
    main()
