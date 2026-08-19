# 1000 Bruxelles building counter

This QA counter answers one narrow production question: how many official building owners inside postal canton **1000 Bruxelles / Brussel** are still not explicitly certified `finished_perfect`?

It uses the NGI/IGN Territorial Divisions postal-canton boundary, current Paradigm UrbIS `Buildings`, the locked #898 LoD2 planner, merged C01 source registration, active C02 source-only draft evidence, current-main repository references and exact building IDs referenced by non-source-only open pull requests.

`finished_perfect` is deliberately fail-closed. A building is removed from `remaining_to_perfect` only when an explicit per-owner completion ledger entry with `status=finished_perfect` is merged on `main`. Source registration, runtime presence, partial visual PASSes and draft PRs do not count as finished.

Outputs are artifact-only (`JSON` summary + per-owner `CSV`). This lot changes no runtime, geometry, collision, visual, semantic name, world transform or zone promotion state.
