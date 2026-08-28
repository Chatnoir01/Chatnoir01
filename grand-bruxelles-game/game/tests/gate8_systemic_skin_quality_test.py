import json
import sys
from collections import Counter, defaultdict
from pathlib import Path

manifest = json.loads(Path(sys.argv[1]).read_text())
root = Path(sys.argv[2])
expected = {v['variant']: v for v in manifest['variants']}
results = {}

for variant in expected:
    candidates = list((root / f'v{variant:02d}').rglob('*micropose-result.json'))
    assert len(candidates) == 1, (variant, candidates)
    data = json.loads(candidates[0].read_text())
    assert data['diagnostic_state'] == 'TARGET_MICROPOSE_SKIN_BLOCKED', (variant, data['diagnostic_state'])
    assert data['engine_version'].startswith('4.7.1')
    assert data['measurement'] == manifest['measurement']
    assert data['source_animation_used'] is False
    assert data['retarget_applied'] is False
    assert data['target_skin_modified'] is False
    assert data['target_rest_modified'] is False
    assert data['threshold_changed'] is False
    assert data['visual_approval_claimed'] is False
    assert data['case_count'] == 54
    assert len(data['case_results']) == 54
    assert data['blocked_case_count'] == len(data['blocked_cases'])
    assert data['blocked_case_count'] > 0
    assert data['failures'] == []
    results[variant] = data

role_failures = defaultdict(Counter)
summary = []
for variant, data in sorted(results.items()):
    blocked = [c for c in data['case_results'] if not c['within_gates']]
    assert len(blocked) == data['blocked_case_count'], (variant, len(blocked), data['blocked_case_count'])
    for c in blocked:
        role_failures[c['role']][variant] += 1
    summary.append({
        'variant': variant,
        'blocked_cases': len(blocked),
        'max_edge_change_m': data['max_edge_absolute_change_m'],
        'max_stretch_ratio': data['max_edge_stretch_ratio'],
        'min_compression_ratio': data['min_edge_compression_ratio'],
        'worst_case': data['worst_case'],
    })

assert all(s['blocked_cases'] > 0 for s in summary)
common_failed_roles = sorted(role for role, counts in role_failures.items() if len(counts) == len(results))
assert common_failed_roles, role_failures
shoulder_common = any('shoulder' in role for role in common_failed_roles)
assert shoulder_common, common_failed_roles

out = {
    'format': 'grand-bruxelles-gate8-systemic-skin-quality-result-v1',
    'diagnostic_state': 'GATE8_CURRENT_SKINS_SYSTEMICALLY_BLOCKED',
    'variant_count': len(results),
    'variants': summary,
    'common_failed_roles': common_failed_roles,
    'source_swap_authorized': False,
    'retarget_rescue_authorized': False,
    'visual_witness_authorized': False,
    'next_safe_axis': 'EXPLICIT_REWEIGHT_OR_REGENERATE_SKIN',
}
Path(sys.argv[3]).write_text(json.dumps(out, indent=2, sort_keys=True) + '\n')
print(json.dumps(out, sort_keys=True))
