# Player report repository

This directory is the durable repository-side landing zone for exports created by the in-game **SIGNALER** flow.

- `open/` contains player tickets that are still OPEN and must block quality promotion for their zone.
- `archive/` contains tickets that have been resolved/closed and retained for traceability.
- `fixtures/` contains synthetic test-only tickets. Fixtures are never player evidence.
- `player-report-v1.schema.json` is the stable contract for `grand-bruxelles-player-report-v1`.

A real exported `*.gbreport.json` must be copied into `open/` unchanged before continuity ingestion. Do not paste secrets, credentials, email addresses or other unnecessary personal data into the note. The screenshot embedded by the runtime is optional repository evidence and may be removed only by a separate documented sanitization step; the ticket identity, zone, position, note and capture time must remain unchanged.

The runtime currently writes its local source copy under `user://player_reports/open/` and exports a downloadable `.gbreport.json`. PR2 owns the player-facing export UX/build metadata. PR3 owns automatic continuity ingestion into `zone_maturity_registry.json`.
