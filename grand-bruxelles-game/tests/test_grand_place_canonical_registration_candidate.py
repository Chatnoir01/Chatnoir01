#!/usr/bin/env python3
"""Compatibility gate for the retired mis-targeted Grand-Place registration.

The historical bxl-e148000-n170000-s500 bytes remain registered as generic evidence,
but the Grand-Place identity claim is superseded by the spatial-identity HOLD.
"""

from test_grand_place_spatial_identity_hold import main as spatial_hold_main


def main() -> None:
    spatial_hold_main()
    print("GRAND_PLACE_CANONICAL_REGISTRATION_COMPATIBILITY_HOLD_OK")


if __name__ == "__main__":
    main()
