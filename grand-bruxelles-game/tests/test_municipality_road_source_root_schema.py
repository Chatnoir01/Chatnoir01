import importlib.util
import json
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
TOOL = ROOT / "tools" / "city_machine" / "acquire_municipality_road_source.py"
PLANS = ROOT / "data" / "source_plans"


def run_tool(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(TOOL), *args],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )


def load_tool_module():
    spec = importlib.util.spec_from_file_location("acquire_municipality_road_source_under_test", TOOL)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_registry_rejects_unknown_root_key(tmp_path: Path) -> None:
    payload = json.loads((PLANS / "brussels_missing_road_source_registry.json").read_text(encoding="utf-8"))
    payload["unexpected_root"] = "must-fail-closed"
    registry = tmp_path / "registry.json"
    registry.write_text(json.dumps(payload), encoding="utf-8")

    result = run_tool(
        "--registry", str(registry),
        "--municipality-nis", "21002",
        "--municipality-id", "auderghem",
        "--manifest-output", str(tmp_path / "manifest.json"),
    )

    assert result.returncode != 0
    assert "unexpected registry root keys: unexpected_root" in (result.stdout + result.stderr)


def test_manifest_rejects_unknown_root_key_before_transport(tmp_path: Path) -> None:
    payload = json.loads((PLANS / "auderghem_road_source_acquisition.json").read_text(encoding="utf-8"))
    payload["unexpected_root"] = "must-fail-closed"
    manifest = tmp_path / "manifest.json"
    manifest.write_text(json.dumps(payload), encoding="utf-8")

    result = run_tool(
        "--manifest", str(manifest),
        "--raw-output", str(tmp_path / "raw.json"),
        "--game-output", str(tmp_path / "game.json"),
        "--receipt-output", str(tmp_path / "receipt.json"),
        "--retries", "1",
    )

    assert result.returncode != 0
    assert "unexpected manifest root keys: unexpected_root" in (result.stdout + result.stderr)


def test_manifest_rejects_output_contract_drift_without_transport(tmp_path: Path) -> None:
    payload = json.loads((PLANS / "auderghem_road_source_acquisition.json").read_text(encoding="utf-8"))
    payload["output"]["normalized_game_source"] = "artifacts/elsewhere.game.json"
    manifest = tmp_path / "manifest.json"
    manifest.write_text(json.dumps(payload), encoding="utf-8")

    module = load_tool_module()
    try:
        module.read_manifest(manifest)
    except SystemExit as exc:
        assert "manifest output contract drift" in str(exc)
    else:
        raise AssertionError("manifest output drift must fail closed before transport")


def test_manifest_rejects_missing_output_contract_without_transport(tmp_path: Path) -> None:
    payload = json.loads((PLANS / "auderghem_road_source_acquisition.json").read_text(encoding="utf-8"))
    payload.pop("output")
    manifest = tmp_path / "manifest.json"
    manifest.write_text(json.dumps(payload), encoding="utf-8")

    module = load_tool_module()
    try:
        module.read_manifest(manifest)
    except SystemExit as exc:
        assert "manifest output contract drift" in str(exc)
    else:
        raise AssertionError("missing manifest output contract must fail closed before transport")


def test_generated_manifest_materializes_locked_output_contract(tmp_path: Path) -> None:
    registry = PLANS / "brussels_missing_road_source_registry.json"
    manifest = tmp_path / "manifest.json"

    result = run_tool(
        "--registry", str(registry),
        "--municipality-nis", "21002",
        "--municipality-id", "auderghem",
        "--manifest-output", str(manifest),
    )

    assert result.returncode == 0, result.stdout + result.stderr
    payload = json.loads(manifest.read_text(encoding="utf-8"))
    assert payload["output"] == {
        "normalized_game_source": "artifacts/auderghem_road_source.game.json",
        "raw_overpass_snapshot": "artifacts/auderghem_road_source.raw.json",
        "receipt": "artifacts/auderghem_road_source.receipt.json",
    }


def test_acquisition_rejects_aliased_output_paths_before_transport(tmp_path: Path) -> None:
    manifest = PLANS / "auderghem_road_source_acquisition.json"
    shared_output = tmp_path / "shared.json"

    result = run_tool(
        "--manifest", str(manifest),
        "--raw-output", str(shared_output),
        "--game-output", str(shared_output),
        "--receipt-output", str(tmp_path / "receipt.json"),
        "--retries", "1",
    )

    assert result.returncode != 0
    assert "acquisition paths alias: raw-output=game-output" in (result.stdout + result.stderr)
    assert not shared_output.exists()


def test_manifest_generation_rejects_registry_output_alias(tmp_path: Path) -> None:
    registry = tmp_path / "registry.json"
    registry.write_bytes((PLANS / "brussels_missing_road_source_registry.json").read_bytes())
    original = registry.read_bytes()

    result = run_tool(
        "--registry", str(registry),
        "--municipality-nis", "21002",
        "--municipality-id", "auderghem",
        "--manifest-output", str(registry),
    )

    assert result.returncode != 0
    assert "registry/manifest paths alias: registry=manifest-output" in (result.stdout + result.stderr)
    assert registry.read_bytes() == original


def test_acquisition_rejects_cli_output_contract_drift_without_transport(tmp_path: Path) -> None:
    module = load_tool_module()
    manifest = module.read_manifest(PLANS / "auderghem_road_source_acquisition.json")

    try:
        module.validate_acquisition_output_paths(
            manifest,
            Path("artifacts/wrong.raw.json"),
            Path("artifacts/auderghem_road_source.game.json"),
            Path("artifacts/auderghem_road_source.receipt.json"),
        )
    except SystemExit as exc:
        assert "acquisition output contract drift" in str(exc)
    else:
        raise AssertionError("CLI output path drift must fail closed before transport")
