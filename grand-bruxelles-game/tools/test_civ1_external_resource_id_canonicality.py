#!/usr/bin/env python3
from __future__ import annotations

import civ1_authored_skin_integrity as skin
import civ1_external_resource_header_schema as header_schema
import civ1_external_resource_id_canonicality as id_gate
import civ1_resource_table_uniqueness as table


def main() -> int:
    scene = id_gate._fixture(r"Skin\u005fbody", r"Skin\u005fbody")

    ids, attrs, syntax, malformed = table.resource_table_conflicts(scene)
    assert ids == []
    assert attrs == []
    assert syntax == []
    assert malformed == []
    assert header_schema.external_resource_header_conflicts(scene) == []

    integrity = skin.scene_integrity(scene)
    assert len(integrity) == 1
    assert integrity[0]["authored_skin_integrity_ready"] is True, (
        "causal precondition failed: authored-skin evidence no longer accepts the escaped single-ID spelling"
    )

    conflicts = id_gate.external_resource_id_conflicts(scene)
    assert len(conflicts) == 1
    assert conflicts[0]["reason"] == "external_resource_id_noncanonical_lexeme"
    assert conflicts[0]["raw_id"] == r"Skin\u005fbody"
    assert conflicts[0]["decoded_id"] == "Skin_body"
    assert conflicts[0]["canonical_id_payload"] == "Skin_body"

    print("CIV1_EXTERNAL_RESOURCE_ID_CANONICALITY_REGRESSION_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
