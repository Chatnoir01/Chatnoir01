from pathlib import Path

SOURCE_LOOKUP_WORKFLOW = Path('.github/workflows/grand-bruxelles-automatic-road-source-lookup.yml')
SPAWN_WORKFLOW = Path('.github/workflows/grand-bruxelles-automatic-road-spawn.yml')


def require(fragment: str, text: str) -> None:
    if fragment not in text:
        raise AssertionError(f'missing fail-closed workflow contract: {fragment}')


def main() -> None:
    source_text = SOURCE_LOOKUP_WORKFLOW.read_text(encoding='utf-8')
    require('ref: ${{ github.event.pull_request.head.sha || github.sha }}', source_text)
    require('fetch-depth: 0', source_text)
    require('git fetch --no-tags origin main', source_text)
    require('LIVE_MAIN_SHA="$(git rev-parse origin/main)"', source_text)
    require('git merge-base --is-ancestor "$LIVE_MAIN_SHA" HEAD', source_text)
    require('RED: automatic road source lookup candidate does not contain live main', source_text)

    spawn_text = SPAWN_WORKFLOW.read_text(encoding='utf-8')
    require('ref: ${{ github.event.pull_request.head.sha || github.sha }}', spawn_text)
    require('fetch-depth: 0', spawn_text)
    require('git fetch --no-tags origin main', spawn_text)
    require('LIVE_MAIN_SHA="$(git rev-parse origin/main)"', spawn_text)
    require('git merge-base --is-ancestor "$LIVE_MAIN_SHA" HEAD', spawn_text)
    require('grand-bruxelles-game/data/city_machine/road_cell_coverage_candidates.json', spawn_text)
    require('lookup=deterministic_runtime_index_coverage_lock', spawn_text)
    print(
        'AUTOMATIC_ROAD_SOURCE_LOOKUP_WORKFLOW_CONTRACT_OK: '
        'exact_pr_head=true live_main_ancestry=true spawn_exact_head=true coverage_lock_trigger=true'
    )


if __name__ == '__main__':
    main()
