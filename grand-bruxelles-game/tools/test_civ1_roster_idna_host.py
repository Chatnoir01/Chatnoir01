#!/usr/bin/env python3
from __future__ import annotations
from civ1_idna_provenance import idna_host_reasons

def main():
    for source in (
        "https://xn--abc.invalid/source/civilian.glb",
        "https://xn--a.invalid/source/civilian.glb",
        "https://xn--0.invalid/source/civilian.glb",
        "https://xn--invalid-.invalid/source/civilian.glb",
    ):
        assert idna_host_reasons(source)==["source_url_idna_label_invalid"], source
    for source in (
        "https://xn--exmple-cua.invalid/source/civilian.glb",
        "https://xn--caf-dma.invalid/source/civilian.glb",
        "https://example.invalid/source/civilian.glb",
    ):
        assert idna_host_reasons(source)==[], source
    print("CIV1_ROSTER_IDNA_HOST_GREEN")

if __name__=="__main__": main()
