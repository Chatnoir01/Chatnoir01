# Streamed collision + asset cache probe

This probe extends the Brussels cell streaming foundation with two runtime layers:

- **Near-player collision tier**: a prefetched cell may remain visually loaded while heavy terrain collision is created only inside the scheduler collision radius and released again outside it.
- **Warm local resource cache**: explicit `res://` resources used by streamed cells remain cached after unload so a later activation can reuse the already loaded resource instead of reloading it from scratch.

The implementation is clean-room GDScript. It copies no OpenRW/OpenLiberty code and consumes no GTA data/assets. Brussels/UrbIS contracts remain authoritative.

The current runtime witness is the existing Ixelles `bxl-e149000-n169000-s500` cell. CI verifies predictive visual prefetch, collision activation/deactivation without visual unload, full cell unload, second activation through the warm cache, Web export and existing game regressions.
