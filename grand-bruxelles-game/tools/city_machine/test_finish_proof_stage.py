#!/usr/bin/env python3
from __future__ import annotations

import sys

import finish_proof_stage as proof


def main() -> int:
    assert proof.PROOF_GATES == [
        "G1_sources_crs",
        "G2_spawn_ground",
        "G3_buildings_streets",
        "G4_runtime_finish",
        "G5_osm_environment",
    ]
    assert proof.run("jette") == 0

    original = proof.cm.gate_g1
    original_argv = sys.argv[:]
    try:
        def forced_fail(_layer, _profile):
            raise proof.cm.GateError("G1_sources_crs", "forced proof test failure")
        proof.cm.gate_g1 = forced_fail
        sys.argv = ["finish_proof_stage.py", "--zone", "jette"]
        assert proof.main() == 3
    finally:
        proof.cm.gate_g1 = original
        sys.argv = original_argv

    print("CITY_MACHINE_PROOF_TESTS_OK gates=5 forced_gate_exit=3 promotion=false")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
