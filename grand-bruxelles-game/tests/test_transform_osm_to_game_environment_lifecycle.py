#!/usr/bin/env python3
from __future__ import annotations

import sys
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT))

from tools import transform_osm_to_game


LIFECYCLE_STATE_FLAGS = ("disused", "abandoned")
LIFECYCLE_SHADOW_PREFIXES = ("construction", "proposed", "disused", "abandoned")


def _node(tags: dict[str, str]) -> dict[str, object]:
    return {
        "elements": [
            {
                "type": "node",
                "id": 6601,
                "lat": 50.8415,
                "lon": 4.3485,
                "tags": tags,
            }
        ]
    }


def _assert_not_materialized(tags: dict[str, str], label: str) -> None:
    converted = transform_osm_to_game.convert(
        _node(tags),
        transform_osm_to_game.DEFAULT_ORIGIN,
    )
    assert converted["environment_points"] == [], label


def main() -> int:
    kinds = (
        ("tree", {"natural": "tree"}),
        ("street_lamp", {"highway": "street_lamp"}),
        ("bollard", {"barrier": "bollard"}),
    )

    for kind, base_tags in kinds:
        for lifecycle_flag in LIFECYCLE_STATE_FLAGS:
            tags = dict(base_tags)
            tags[lifecycle_flag] = "yes"
            _assert_not_materialized(
                tags,
                f"{kind} + {lifecycle_flag}=yes must not materialize into active environment points",
            )

        semantic_key, semantic_value = next(iter(base_tags.items()))
        for lifecycle_prefix in LIFECYCLE_SHADOW_PREFIXES:
            tags = dict(base_tags)
            tags[f"{lifecycle_prefix}:{semantic_key}"] = semantic_value
            _assert_not_materialized(
                tags,
                f"{kind} + {lifecycle_prefix}:{semantic_key} must fail closed",
            )

        positive = transform_osm_to_game.convert(
            _node(dict(base_tags)),
            transform_osm_to_game.DEFAULT_ORIGIN,
        )
        assert len(positive["environment_points"]) == 1
        assert positive["environment_points"][0]["kind"] == kind

    print(
        "TRANSFORM_OSM_ENVIRONMENT_LIFECYCLE_OK "
        "state_flags_rejected=true lifecycle_shadow_conflicts_rejected=true "
        "positive_controls_retained=true network_used=false"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
