#!/usr/bin/env python3
import json
import sys
from pathlib import Path

CONTRACT = Path('grand-bruxelles-game/data/qa/gate8_variant01_kaykit_walk_source_intake.json')


def fail(message: str) -> None:
    print(f'ERROR: {message}', file=sys.stderr)
    raise SystemExit(1)


def main() -> None:
    data = json.loads(CONTRACT.read_text(encoding='utf-8'))
    if data.get('license') != 'CC0-1.0':
        fail('KayKit candidate must remain CC0-1.0')
    if data.get('source_page') != 'https://opengameart.org/content/kaykit-character-animations':
        fail('unexpected source page')
    if data.get('download_url') != 'https://opengameart.org/sites/default/files/kaykit_character_animations_1.2.zip':
        fail('unexpected download URL')
    if sorted(data.get('format_expectations', [])) != ['fbx', 'gltf']:
        fail('expected GLTF and FBX formats')
    if data.get('semantic_expectations') != ['idle', 'walk', 'run']:
        fail('expected exact idle/walk/run semantic intake')
    if data.get('pin_state') != 'PENDING_FIRST_PARTY_BYTE_ACQUISITION':
        fail('source must stay pending until exact bytes are acquired')
    if data.get('source_sha256') or data.get('source_size_bytes') != 0:
        fail('do not invent hash/size before acquisition')
    for key in ('production_authorized', 'activation_ready', 'adoption_ready', 'mixamo_allowed', 'player_character_reuse_allowed'):
        if data.get(key) is not False:
            fail(f'{key} must remain false')
    if data.get('walk_alias_selected') or data.get('run_alias_selected'):
        fail('no locomotion alias may be selected during intake')
    print('GATE8_KAYKIT_SOURCE_INTAKE_CONTRACT_OK pending_pin=true production=false aliases=empty')


if __name__ == '__main__':
    main()
