#!/usr/bin/env python3
from __future__ import annotations

import json
import tempfile
from pathlib import Path

from validate_thandi_source_status import validate


def write(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def main() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        status = root / "source_status.json"
        write(status, {
            "format": "grand-bruxelles-thandi-source-status-v1",
            "source_package_present": False,
            "runtime_authored_asset_present": False,
            "required_files": ["source/Thandi.fbx", "textures/Thandi_Body_Diffuse.png"],
            "runtime_asset": "Thandi.glb",
            "blocker": "source_binary_and_textures_not_committed",
        })
        result = validate(root, status)
        assert result["truthful"] is True
        assert result["missing_required_files"] == ["source/Thandi.fbx", "textures/Thandi_Body_Diffuse.png"]
        assert result["runtime_asset_present"] is False

        (root / "source").mkdir()
        (root / "source/Thandi.fbx").write_bytes(b"fbx")
        try:
            validate(root, status)
        except ValueError as exc:
            assert "status says source package absent" in str(exc)
        else:
            raise AssertionError("partially present source did not invalidate absent status")

        (root / "textures").mkdir()
        (root / "textures/Thandi_Body_Diffuse.png").write_bytes(b"png")
        data = json.loads(status.read_text(encoding="utf-8"))
        data["source_package_present"] = True
        data["blocker"] = None
        write(status, data)
        result = validate(root, status)
        assert result["source_package_present"] is True
        assert result["missing_required_files"] == []

    print("THANDI_SOURCE_STATUS_TEST_OK")


if __name__ == "__main__":
    main()
