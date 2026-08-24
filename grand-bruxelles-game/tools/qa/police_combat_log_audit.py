#!/usr/bin/env python3
import argparse
from pathlib import Path

AUDIO_ERROR = 'ERROR: Condition "status < 0" is true. Returning: ERR_CANT_OPEN'
AUDIO_SITE = 'at: init_output_device (drivers/alsa/audio_driver_alsa.cpp:97)'
AUDIO_FALLBACK = 'WARNING: All audio drivers failed, falling back to the dummy driver.'
HARD_MARKERS = ('SCRIPT ERROR', 'Parse Error:', 'ERROR: Failed to load script')


def audit_text(text: str, allow_known_audio_fallback: bool = False) -> list[str]:
    lines = text.splitlines()
    failures: list[str] = []
    for index, line in enumerate(lines):
        if any(marker in line for marker in HARD_MARKERS):
            failures.append(line.strip())
            continue
        if not line.startswith('ERROR:'):
            continue
        if allow_known_audio_fallback and line == AUDIO_ERROR:
            window = lines[index + 1:index + 5]
            has_site = any(AUDIO_SITE in candidate for candidate in window)
            has_fallback = any(AUDIO_FALLBACK in candidate for candidate in lines[index + 1:index + 8])
            if has_site and has_fallback:
                continue
        failures.append(line.strip())
    return failures


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('logs', nargs='+')
    parser.add_argument('--allow-known-audio-fallback', action='store_true')
    args = parser.parse_args()

    failures: list[str] = []
    for raw_path in args.logs:
        path = Path(raw_path)
        if not path.is_file():
            failures.append(f'missing log: {path}')
            continue
        for failure in audit_text(path.read_text(encoding='utf-8', errors='replace'), args.allow_known_audio_fallback):
            failures.append(f'{path}: {failure}')

    if failures:
        print('POLICE_COMBAT_VISUAL_LOG_AUDIT_FAIL')
        for failure in failures:
            print(failure)
        return 1
    print('POLICE_COMBAT_VISUAL_LOG_AUDIT_OK')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
