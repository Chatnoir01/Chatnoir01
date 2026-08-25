#!/usr/bin/env python3
import json
import sys
from pathlib import Path

CONTRACT = Path('grand-bruxelles-game/data/qa/gate8_variant01_kaykit_walk_source_intake.json')
EXPECTED_SHA256 = 'c9d3fbea492dc6edd0903939369a564c2240b892430bcd99e0aee4876110bb8f'
EXPECTED_SIZE = 7959257
EXPECTED_COUNTS = {'archive_file_count': 67, 'gltf_or_glb_count': 4, 'fbx_count': 34, 'idle_candidate_count': 1, 'walk_candidate_count': 1, 'run_candidate_count': 1}

def validate(data: dict) -> list[str]:
    errors: list[str] = []
    if data.get('license') != 'CC0-1.0': errors.append('KayKit candidate must remain CC0-1.0')
    if data.get('source_page') != 'https://opengameart.org/content/kaykit-character-animations': errors.append('unexpected source page')
    if data.get('download_url') != 'https://opengameart.org/sites/default/files/kaykit_character_animations_1.2.zip': errors.append('unexpected download URL')
    if sorted(data.get('format_expectations', [])) != ['fbx', 'gltf']: errors.append('expected GLTF and FBX formats')
    if data.get('semantic_expectations') != ['idle', 'walk', 'run']: errors.append('expected exact idle/walk/run semantic intake')
    if data.get('pin_state') != 'PINNED_FIRST_PARTY_BYTES_VERIFIED': errors.append('KayKit source must remain pinned to acquired bytes')
    if data.get('source_sha256') != EXPECTED_SHA256: errors.append('KayKit source SHA-256 drift')
    if data.get('source_size_bytes') != EXPECTED_SIZE: errors.append('KayKit source byte-size drift')
    for key, expected in EXPECTED_COUNTS.items():
        if data.get(key) != expected: errors.append(f'{key} drift: expected {expected}')
    if data.get('pin_evidence_run') != 32876921778 or data.get('pin_evidence_artifact') != 9574284192: errors.append('pin evidence identity drift')
    for key in ('production_authorized', 'activation_ready', 'adoption_ready', 'mixamo_allowed', 'player_character_reuse_allowed'):
        if data.get(key) is not False: errors.append(f'{key} must remain false')
    if data.get('walk_alias_selected') or data.get('run_alias_selected'): errors.append('no locomotion alias may be selected during pinned intake')
    return errors

def main() -> None:
    data = json.loads(CONTRACT.read_text(encoding='utf-8'))
    errors = validate(data)
    if errors:
        for error in errors: print(f'ERROR: {error}', file=sys.stderr)
        raise SystemExit(1)
    print(f'GATE8_KAYKIT_SOURCE_PIN_OK sha256={EXPECTED_SHA256} bytes={EXPECTED_SIZE} files=67 gltf=4 fbx=34 idle=1 walk=1 run=1 production=false aliases=empty')

if __name__ == '__main__': main()
