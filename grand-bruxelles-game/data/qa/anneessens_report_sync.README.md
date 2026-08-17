# Anneessens SIGNALER report sync

This continuity lot deliberately does not commit a fabricated zero-report snapshot.

To produce the durable QA witness from a real player export, copy the contents of the runtime `user://player_reports/open/` directory into a local folder and run:

```bash
python3 grand-bruxelles-game/tools/continuity/continuity.py sync \
  --zone anneessens \
  --reports-dir /path/to/exported/open \
  --out grand-bruxelles-game/data/qa/anneessens_report_sync.json
```

Then ask the loop for the next lot using the persisted witness:

```bash
python3 grand-bruxelles-game/tools/continuity/continuity.py next \
  --zone anneessens \
  --report-sync grand-bruxelles-game/data/qa/anneessens_report_sync.json
```

A complete snapshot with `open_count=0` is the only state that proves zero OPEN Anneessens reports for that export. Absence of the snapshot is not proof of zero reports. If one or more reports are present, the oldest OPEN report is selected first.
