# Gate-8 variant 01 native retarget A/B

This QA-only lot measures `Jog_Fwd` and `Sprint` on the immutable Gate-8 variant 01 target with Godot 4.7.1 `RetargetModifier3D`.

It intentionally does **not** select a `run` alias, authorize production, change runtime population, or commit external model/animation payloads.

The source animation skeleton keeps its original bone names so imported AnimationPlayer tracks remain untouched. Only the target skeleton's 22 reviewed mapped bones are renamed in memory to the exact source bone names. Rest transforms, parent topology, and bone indices are asserted unchanged.

The modifier is configured with model-space local-pose retargeting (`use_global_pose=false`), rotation enabled, position disabled, and scale disabled. Both candidates are sampled at 120 Hz and must produce finite foot-slide metrics, contact samples, bounded grounding variation, bounded torso deviation, and two real 1280x720 Godot frames before any later selection/adoption lot.
