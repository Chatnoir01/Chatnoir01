# Decision log

## 2026-08-20 — authored realism strategy

Decision: stop treating procedural humanoids and generated vehicle shells as the final close-camera look.

Production architecture:

1. authored asset at close player distance;
2. optimized authored LOD at medium distance;
3. current procedural runtime as fail-safe/far-distance fallback.

First human source family: Renderpeople downloadable CC-Attribution samples, because the original publisher account provides scanned/rigged humans with modest geometry and high-resolution textures.

First vehicle source leads: one generic detailed sedan plus one modern compact hatchback, both subject to exact package/provenance review before import.

Police characters will reuse the winning civilian body/skeleton pipeline and receive project-authored Belgian police clothing/equipment. Police vehicles will reuse the winning civilian chassis pipeline and receive project-authored Belgian livery/lightbar/equipment.

No expansion to a broad roster/catalogue until a single human witness and a single vehicle witness pass fixed-view player gates.
