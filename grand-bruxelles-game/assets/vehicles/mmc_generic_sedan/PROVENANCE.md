# MMC Generic Sedan — CAR-1 intake

Status: **SOURCE_SELECTED / OFFICIAL_BYTES_PENDING / NOT_PRODUCTION_AUTHORIZED**

Integration base: `main@51907a1bfb5caccbcb83b82571d081fe2eaddb1b`

This directory is the controlled intake location for the first close-camera authored civilian car witness.

## Source

- Asset: `Generic Sedan Car`
- Author / publisher: **MMC Works** (`@mmcworks`)
- Sketchfab model ID: `58c33766470d46e7b2aed542650494e5`
- Official Sketchfab page: `https://sketchfab.com/3d-models/generic-sedan-car-58c33766470d46e7b2aed542650494e5`
- Official Fab listing: `https://www.fab.com/listings/427e19dd-ca86-47cd-b1b2-0b0fd01d8853`
- Creator portfolio confirmation: `https://marciomeireles.artstation.com/projects/6NRQn6`

## Declared asset facts

Sketchfab currently declares:

- free download;
- Creative Commons Attribution license;
- 113.2k triangles;
- 58.8k vertices;
- generic sedan design;
- basic paint / bottom / mechanics / interior texture maps;
- rough interior;
- separated parts;
- Rigacar rig;
- NoAI restriction.

Fab currently lists the asset as **Free** and exposes converted `glTF`, `GLB` and `USDZ` formats.

## License / usage rule

The production path accepts this candidate only under the declared CC Attribution terms. Preserve author attribution in the shipped credits / license registry.

The Sketchfab NoAI restriction is also preserved: these asset bytes must not be used as AI/ML training data or as model-development input. Normal game runtime use is separate from that restriction.

Do not substitute mirrors, ripped game assets, unknown reuploads, or brand-specific copies.

## Required local payload

The preferred runtime payload is:

`res://assets/vehicles/mmc_generic_sedan/generic_sedan.glb`

The official download currently requires an authenticated Sketchfab/Fab user flow. The repository therefore does **not** contain third-party bytes yet and must not pretend that CAR-1 is complete.

After the official file is acquired, record before review:

- exact downloaded filename and format;
- download date;
- SHA-256 of every committed payload file;
- exact license snapshot / attribution text;
- texture dependencies;
- imported triangle count;
- imported AABB / real-world scale;
- Web import size.

## Acceptance gate

`production_authorized=false` until all of these are true:

1. official source and license evidence are preserved;
2. SHA-256 is recorded;
3. Godot 4.7.1 imports the asset without missing dependencies;
4. body orientation and real-world scale are proven;
5. existing vehicle physics / collision are unchanged;
6. procedural fallback remains recoverable;
7. 2 m / 5 m / 8 m fixed-camera evidence is reviewed;
8. Web and PC remain green;
9. performance impact is measured;
10. owner verdict is `GARDER`.

Until then the existing procedural civilian vehicle renderer is the fail-closed production fallback.
