# Grand Bruxelles — Realism Asset Intake

Base: `main@96e26ee71f8428ff1ab4887a471c9e35d3174b20`

Scope is deliberately limited to **civilians, police character visuals, civilian cars, police vehicle visuals, locomotion, and their PBR support assets**.

## Architecture

The production target is **authored near camera + authored LOD + existing procedural fallback**.

- 2–8 m: highest-quality authorized authored asset.
- Medium distance: optimized authored LOD / lower-cost authored variant.
- Far distance, Web pressure, missing asset, or failed import: current procedural runtime remains available.
- No asset intake owns navigation, AI, traffic routing, spawn density, combat, or vehicle movement.

## Hard legal/provenance gate

Before any third-party bytes enter `assets/`:

1. preserve exact source URL and author/publisher;
2. preserve declared license and attribution requirements;
3. reject NC/ND/unknown/ripped assets for the public production path;
4. record local SHA-256 after download;
5. archive a text provenance note with source date and any special terms;
6. never treat a search result, thumbnail, or model title as sufficient provenance;
7. never copy models extracted from GTA, racing games, police simulators, or other commercial games;
8. paid/store assets may only be used if their runtime/redistribution license is compatible, and raw proprietary files must not be committed to a public repository unless redistribution is explicitly allowed.

The machine-readable shortlist is `data/qa/realism_asset_candidates.json`.

## First character witnesses

### 1. Renderpeople Eric Rigged 001

Primary male close-camera witness. The publisher's Sketchfab page declares a rigged scanned person around 20.5k triangles with high-resolution diffuse/normal/alpha textures under CC Attribution. This is a materially stronger first realism witness than multiplying the current procedural roster.

### 2. Renderpeople Carla Rigged 001

Primary female close-camera witness on the same source/pipeline. Using the same publisher family reduces unknowns while we prove the authored NPC bridge.

### 3. Nathan Animated 003 + Sophia Animated 003

Motion references rather than automatic production identities. Nathan provides a loopable baked walk and Sophia a loopable baked idle/waiting motion. They are useful to measure cadence, grounding, arm behaviour, cloth/skin response and visible foot slide before retargeting a larger roster.

### Secondary character candidates

- Joe — strong game-ready PBR topology, but needs a rig before it can compete with the first witnesses.
- Additional third-party female candidates stay behind a provenance gate until their original-work chain is manually confirmed.
- MakeHuman remains valuable as a CC0 controlled generator/fallback source and for custom Belgian police clothing, but no MakeHuman candidate becomes a close-camera hero merely because it is technically green.

## First vehicle witnesses

### 1. MMC Works Generic Sedan

Primary sedan candidate: generic design, separated parts, rough interior, Rigacar rig and texture maps. At ~113k triangles it requires a deliberate LOD and texture pass before Web production, but it is appropriate for a 2–5 m authored witness.

### 2. Compact Modern Hatchback candidate

Primary modern hatchback lead from the current search. Its page declares ~110k triangles, detailed exterior and clean real-time topology. It remains provenance-gated until original-work/source evidence is manually confirmed.

### 3. Generic European low-cost authored traffic

`Milano '95` (~18.1k triangles) and the MaG80 European compact van (~11.4k triangles) are useful candidates for medium-distance authored variety because their geometry cost is far closer to Web budgets. Brand-likeness must still be reviewed and visible logos/identifiers must not be imported.

## Animation

Adobe's current Mixamo FAQ states that Mixamo characters and animations can be used royalty-free for personal, commercial and non-profit projects including video games. Use Mixamo only as an animation/rigging source under its current terms; raw redistribution rights are not assumed, and its content must not be used to train/test/improve AI/ML systems.

Required locomotion set for the authored NPC bridge:

- idle;
- walk;
- run;
- start/stop;
- left/right turn;
- optional phone/talking/standing variations after locomotion is green.

## Materials

Poly Haven is preferred for general PBR support because its assets are CC0. MakeHuman official/checked CC0 packs are also valid inputs when the individual pack license is confirmed.

## Production gate for every imported witness

A candidate is not done when Godot imports it.

Required sequence:

`source -> license/provenance -> local hash -> import -> runtime binding -> 2m/5m/8m fixed views -> no-slide/grounding -> Web/PC performance -> owner verdict GARDER`

### Character RED conditions

- mannequin/scan artifact visible at 2–8 m;
- bad face/eyes/hair;
- clipping;
- feet floating or penetrating ground;
- obvious walk sliding;
- identical synchronized NPC motion;
- broken normals/materials;
- texture memory unsuitable for Web;
- fallback hidden before authored mesh is proven valid.

### Vehicle RED conditions

- visibly generic primitive/procedural body at 2–5 m;
- white/missing materials;
- wheels or body pivot wrong;
- scale differs from runtime envelope;
- obvious brand/logo copied into generic production use;
- no usable LOD path;
- fallback hidden before authored mesh validation;
- movement/collision ownership changed by the renderer.

## Police path

Police characters should reuse the winning civilian skeleton/material pipeline and receive a project-authored Belgian police clothing/equipment kit. Police vehicles should reuse the winning civilian authored chassis and then receive project-authored Belgian livery/lightbar/equipment. The current police decals and emergency-light runtime remain functional references; they are not sufficient to declare realism complete.

## Immediate intake order

1. Eric rigged witness.
2. Carla rigged witness.
3. Nathan walk reference.
4. Sophia idle reference.
5. Generic Sedan close-camera witness.
6. Modern Hatchback close-camera witness.
7. Generic European compact authored traffic.
8. Compact van authored traffic.

Do **not** expand to a 6+ character roster or a large vehicle catalogue until the first close-camera character and first close-camera vehicle each receive a real `GARDER` verdict.
