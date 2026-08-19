# 1000 Bruxelles building completion counter

This QA counter uses the official NGI/IGN postal-canton boundary for **1000 Bruxelles / Brussel** and the current Paradigm UrbIS `Buildings` layer to establish the exact owner inventory. It then reconciles those owners against the locked #898 LoD2 planner, merged C01 source campaign, active C02 source-only draft, exact `data/urbis` source references, production runtime references and non-source-only open implementation pull requests.

A building is removed from `remaining_to_perfect` only by an explicit per-owner completion ledger entry with `status=finished_perfect` merged on `main`. Source registration, runtime presence, a partial visual PASS or a draft PR never counts as perfect.

The artifact contains one JSON summary and one CSV row per official building owner. `unresolved` is intentionally fail-closed: it means the official 2D building owner was not reconciled to the locked LoD2/repository evidence, not that the building does not exist.

This counter is QA-only. It authorizes no runtime mount, geometry, collision, material, semantic identity or JOUABLE promotion.
