# City Machine finish pipeline pilot

1. Midi is JOUABLE, but current main does not prove a zone-scoped machine rebuild from Midi buildings + streets inputs.
2. Jette has committed UrbIS phase2 buildings + street surfaces and an existing deterministic machine path.
3. Therefore the campaign pilot is **Jette** under the fixed selection law.
4. The pilot is locked for this campaign; no mid-run zone switch is allowed.
5. Missing optional layers log SKIP/disabled and never invent source geometry.

## Rebuild in 10 lines

1. Install `pyproj>=3.7,<4`.
2. Run `python3 grand-bruxelles-game/tools/city_machine/finish_pipeline.py build --zone jette`.
3. Geometry starts first and rebuilds the cached UrbIS runtime outputs.
4. OSM environment runs second from the committed Jette ODbL cache.
5. Finish materials currently logs `SKIP status=missing`; no hero material is invented.
6. Life currently logs `SKIP status=disabled`; no synthetic crowd is created.
7. Final proof reruns hard G1→G5 against the resulting tracked outputs.
8. Any hard gate failure returns non-zero and stops the command.
9. CI requires zero tracked diff after a nominal rebuild.
10. The machine never promotes LABO to JOUABLE; that remains human-only.
