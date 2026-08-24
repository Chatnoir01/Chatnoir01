from pathlib import Path
import importlib.util

WORKFLOW = Path('.github/workflows/grand-bruxelles-police-combat-visual-witness.yml')
TEXT = WORKFLOW.read_text(encoding='utf-8')
AUDIT_PATH = Path('grand-bruxelles-game/tools/qa/police_combat_log_audit.py')


def require(fragment: str) -> None:
    if fragment not in TEXT:
        raise AssertionError(f'missing police combat visual log contract fragment: {fragment}')


def load_audit_module():
    spec = importlib.util.spec_from_file_location('police_combat_log_audit', AUDIT_PATH)
    if spec is None or spec.loader is None:
        raise AssertionError('failed to load police combat log audit helper')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main() -> None:
    require('grand-bruxelles-game/tools/qa/police_combat_log_audit.py')
    require('--allow-known-audio-fallback')
    require('POLICE_COMBAT_VISUAL_LOG_AUDIT_OK')
    require('POLICE_COMBAT_VISUAL_LOG_AUDIT_FAIL')

    audit = load_audit_module()
    known_audio = '\n'.join([
        'ERROR: Condition "status < 0" is true. Returning: ERR_CANT_OPEN',
        '   at: init_output_device (drivers/alsa/audio_driver_alsa.cpp:97)',
        'WARNING: All audio drivers failed, falling back to the dummy driver.',
    ])
    if audit.audit_text(known_audio, True):
        raise AssertionError('known CI audio fallback must be explicitly allowed')
    if not audit.audit_text(known_audio, False):
        raise AssertionError('known audio ERROR must fail without explicit allow flag')
    if not audit.audit_text('ERROR: Rendering device lost', True):
        raise AssertionError('unexpected engine ERROR must fail closed')
    if not audit.audit_text('SCRIPT ERROR: Invalid call', True):
        raise AssertionError('script errors must fail closed')
    print('POLICE_COMBAT_VISUAL_LOG_CONTRACT_OK')


if __name__ == '__main__':
    main()
