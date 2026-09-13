#!/usr/bin/env python3
import json

from strict_json_evidence import StrictJsonError, loads_strict

samples = {
    "duplicate_key": '{"format":"good","format":"evil"}',
    "nan": '{"x":NaN}',
    "overflow": '{"x":1e309}',
}

permissive = []
strict_rejected = []
for name, payload in samples.items():
    try:
        json.loads(payload)
    except (ValueError, json.JSONDecodeError):
        pass
    else:
        permissive.append(name)
    try:
        loads_strict(payload)
    except (StrictJsonError, ValueError, json.JSONDecodeError):
        strict_rejected.append(name)

assert sorted(permissive) == sorted(samples), f"regression precondition drifted: {permissive}"
assert sorted(strict_rejected) == sorted(samples), f"strict parser accepted ambiguous evidence: {strict_rejected}"
print("AUTOMATIC_ROAD_RUNTIME_INDEX_STRICT_JSON_REGRESSION_GREEN")
