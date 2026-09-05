import importlib.util
from pathlib import Path

P = Path(__file__).parents[1] / "tools" / "build_civ1_skeleton_witness_bundle.py"
s = importlib.util.spec_from_file_location("w", P)
m = importlib.util.module_from_spec(s)
s.loader.exec_module(m)


def test_qmul_identity_preserves_quaternion():
    q = [0.1, -0.2, 0.3, 0.9]
    q = m._quat(q, "q")
    out = m.qmul([0.0, 0.0, 0.0, 1.0], q)
    assert max(abs(a - b) for a, b in zip(out, q)) < 1e-12


def test_quaternion_rejects_nonfinite_and_degenerate():
    for q in ([0.0, 0.0, 0.0, 0.0], [0.0, 0.0, float("nan"), 1.0]):
        try:
            m._quat(q, "bad")
        except ValueError:
            pass
        else:
            raise AssertionError("invalid quaternion accepted")


def _minimum_native():
    # build() must reject the production flags before dereferencing native samples.
    return {"model_space_samples": []}


def _minimum_reconstruction(**overrides):
    value = {
        "schema": "grand-bruxelles-civ1-fixed-length-reconstruction-v2",
        "verdict": "AMELIORER_FIXED_LENGTH_CONTINUOUS_CYCLE",
        "runtime_authorized": False,
        "visual_approval_claimed": False,
        "physical_envelope_pass": True,
        "correction_continuity_pass": True,
    }
    value.update(overrides)
    return value


def test_bundle_rejects_runtime_authorization():
    try:
        m.build(_minimum_native(), _minimum_reconstruction(runtime_authorized=True))
    except ValueError as exc:
        assert "non-production" in str(exc)
    else:
        raise AssertionError("runtime-authorized input accepted")


def test_bundle_rejects_visual_approval_claim():
    try:
        m.build(_minimum_native(), _minimum_reconstruction(visual_approval_claimed=True))
    except ValueError as exc:
        assert "non-production" in str(exc)
    else:
        raise AssertionError("visual-approved input accepted")


def test_bundle_rejects_non_ameliore_verdict():
    try:
        m.build(_minimum_native(), _minimum_reconstruction(verdict="JETER_FIXED_LENGTH_RECONSTRUCTION"))
    except ValueError as exc:
        assert "AMELIORER" in str(exc)
    else:
        raise AssertionError("rejected reconstruction accepted")
