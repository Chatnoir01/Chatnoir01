from pathlib import Path

WORKFLOW = Path('.github/workflows/grand-bruxelles-police-combat-visual-witness.yml')
TEXT = WORKFLOW.read_text(encoding='utf-8')


def require(fragment: str) -> None:
    if fragment not in TEXT:
        raise AssertionError(f'missing police combat visual log contract fragment: {fragment}')


def main() -> None:
    require('grand-bruxelles-game/tools/qa/police_combat_log_audit.py')
    require('--allow-known-audio-fallback')
    require('POLICE_COMBAT_VISUAL_LOG_AUDIT_OK')
    require('POLICE_COMBAT_VISUAL_LOG_AUDIT_FAIL')
    print('POLICE_COMBAT_VISUAL_LOG_CONTRACT_OK')


if __name__ == '__main__':
    main()
