from pathlib import Path

SCRIPT = Path('grand-bruxelles-game/tools/civ1_contact_phase_causality.py')
WORKFLOW = Path('.github/workflows/grand-bruxelles-civ1-contact-phase-causality.yml')


def main() -> None:
    s = SCRIPT.read_text(encoding='utf-8')
    w = WORKFLOW.read_text(encoding='utf-8')
    required_script = [
        'TARGET_SAMPLES = [68, 69, 70, 71]',
        'source_hips_static',
        'strict_lower_envelope_descent',
        'planted_interval_claimable',
        'quantitative_foot_slide_candidate',
        'animation_correction_authorized',
        'runtime_authorized',
    ]
    for token in required_script:
        assert token in s, token
    assert 'WEIGHT_THRESHOLD' not in s
    assert 'percentile' not in s.lower()
    assert 'camera' not in s.lower()
    assert '10039569596' in w
    assert '9996432028' in w
    assert 'ca8e4fd953d638409d3271789e471beae18c3c6ff549238d1df4e211f13257b8' in w
    assert '9b4dd309157ce1f3e5aae44125f5931fac409238eece1a0632b8ad07933ebb00' in w
    assert '76183910ea9ffd2933f9e80c64c3a283f548aa47' in w
    print('CIV1_CONTACT_PHASE_CONTRACT_OK')


if __name__ == '__main__':
    main()
