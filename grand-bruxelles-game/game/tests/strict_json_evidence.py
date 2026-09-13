#!/usr/bin/env python3
import json
import math
from pathlib import Path


class StrictJsonError(ValueError):
    pass


def _object_no_duplicates(pairs):
    out = {}
    for key, value in pairs:
        if key in out:
            raise StrictJsonError(f"duplicate JSON key: {key!r}")
        out[key] = value
    return out


def _finite_float(raw):
    value = float(raw)
    if not math.isfinite(value):
        raise StrictJsonError(f"non-finite JSON number: {raw}")
    return value


def _reject_constant(raw):
    raise StrictJsonError(f"non-standard JSON constant: {raw}")


def loads_strict(text):
    return json.loads(
        text,
        object_pairs_hook=_object_no_duplicates,
        parse_float=_finite_float,
        parse_constant=_reject_constant,
    )


def load_path_strict(path: Path):
    return loads_strict(path.read_text(encoding="utf-8"))
