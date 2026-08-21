#!/usr/bin/env python3
from __future__ import annotations

import city_machine as cm


def expect_machine_error(fn, contains: str) -> None:
    try:
        fn()
    except cm.MachineError as exc:
        assert contains in str(exc), exc
    else:
        raise AssertionError(f"expected MachineError containing {contains!r}")


def main() -> int:
    registry = cm.load_registry()
    assert registry["version"] == 4

    assert cm.layer_enabled({"enabled_zones": ["*"]}, "future_zone")
    assert cm.layer_enabled({"enabled_zones": ["jette"]}, "jette")
    assert not cm.layer_enabled({"enabled_zones": ["jette"]}, "future_zone")
    assert not cm.layer_enabled({"enabled_zones": []}, "jette")

    for layer in registry["layers"]:
        if layer["kind"] != "disabled":
            assert cm.layer_enabled(layer, "future_zone"), layer["layer_id"]

    jette = registry["zone_profiles"]["jette"]
    assert cm.profile_script(jette, "validator_script").is_file()
    assert cm.profile_script(jette, "runtime_script").is_file()

    missing_validator = dict(jette)
    missing_validator.pop("validator_script")
    expect_machine_error(lambda: cm.profile_script(missing_validator, "validator_script"), "validator_script")

    missing_runtime = dict(jette)
    missing_runtime["runtime_script"] = "game/zones/not-real.gd"
    expect_machine_error(lambda: cm.profile_script(missing_runtime, "runtime_script"), "runtime_script")

    catalog = cm.read_json(cm.CATALOG)
    assert cm.resolve_zone(catalog, "anneessens")["id"] == "anneessens"
    assert cm.resolve_zone(catalog, "bourse")["id"] == "bourse"
    expect_machine_error(lambda: cm.build("anneessens", dry=True), "not enabled")
    expect_machine_error(lambda: cm.build("bourse", dry=True), "not enabled")

    assert cm.build("jette", dry=True) is None

    print("CITY_MACHINE_REGIONAL_ONBOARDING_OK wildcard_layers=true profile_scripts=true jette_dry_run=true incomplete_zones_fail_closed=true")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
