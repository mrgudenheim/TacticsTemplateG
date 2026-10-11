# DEPTH writes use the engine's window-depth convention, in one place

Every shader in TacticsTemplateG that writes `DEPTH` converts NDC z to window depth via `psx_window_depth()` in `src/shaders/psx_window_depth.gdshaderinc`. That function is the only place in the project allowed to know the convention; no call site reasons about it.

The project previously wrote raw NDC z, which spans [-1, 1], into `DEPTH`, which is a window depth in [0, 1]. Under the Compatibility renderer this halves usable depth precision and clamps all geometry past the mid-plane into a single slot. It was invisible because all eleven computation sites were wrong identically, so the game still sorted correctly against itself; installing ExMateria Effects, which writes the depth the engine actually wants, is what made the disagreement observable.

The conversion is a range conversion, not a reversed-Z inversion. Compatibility uses reversed depth — near is positive NDC z, far is negative — and near stays high after conversion. It is applied after any depth bias so the bias magnitude scales with it.

`src/shaders/psx_depth_common.gdshaderinc` now holds the shared computation as `psx_depth()`, which the eight shaders that take their sort point from an object origin call. Its header previously promised a `PSX_DEPTH_VERTEX` macro that never existed, and the computation was copy-pasted into each shader instead.

## Calibration and bias mechanism stay the project's own

Depth bias remains a shift of the sort point through the world, applied before projection, using the project's own `VfxConstants.DEPTH_BIAS_*` magnitudes.

Adopting the addon's `addons/exmateria_schema/compositing_key/ot_depth.gdshaderinc` wholesale was considered and rejected. Its mode vocabulary is identical to `VfxConstants.DepthMode` name for name, and converging on it would make the two agree by construction, but it expresses relative bias as a fixed offset in NDC (`world_bias * PROJECTION_MATRIX[2][2]`), which is exact only for a true orthographic camera. This project has a live perspective toggle — `camera_controller.on_orthographic_toggled`, wired to `battle_manager`'s `OrthographicCheckBox` — under which a constant NDC offset is not a world distance at all, and a `PULL_FORWARD_8` bias of 3 world units would land far outside the NDC range. Adoption would also have orphaned the `bias_*` shader parameters baked into `src/Unit/unit.tscn` and `src/Unit/unit_sprites_manager.tscn`, which Godot drops silently when a uniform disappears.

Agreement with the addon does not require a shared implementation, only a shared convention: for the same world point in `STANDARD` mode both now compute `(clip.z / clip.w) * 0.5 + 0.5`.

This decision does not reject adopting `ot_depth` later. If the perspective toggle is removed, or the addon's bias gains a projection-independent form, the case for one implementation instead of two stands on its own.

## What was measured

Verified on the project's pinned engine, Godot 4.7.2.stable.official under `gl_compatibility`, with a probe rig whose passes each carry a colour control:

- Compatibility uses reversed depth; raw NDC written to `DEPTH` wrongly occludes a quad that is genuinely nearer, and the converted form does not.
- `CURRENT_RENDERER` and `RENDERER_COMPATIBILITY` are real engine-provided preprocessor defines here. This needed its own check: absent names compare `0 == 0`, which would make the guard silently true, so the rig also asks for `RENDERER_FORWARD_PLUS` and requires exactly one of the two comparisons to hold.
- All three fixed modes (`FIXED_FRONT`, `FIXED_BACK`, `FIXED_16`) still pin to the front and back of the buffer, tested in both polarities.
- The map's per-face centroid path in `map_shader.gdshader`, which projects `CUSTOM0` through `MODELVIEW_MATRIX` rather than an object origin, sorts correctly against depth written by the addon's real include.
- Each ordering test was also run against the pre-fix convention and reports disagreement there, so the passing verdicts are known to be capable of failing.

A visual check inside a running battle was not performed. The ROM-derived content resources this checkout would need for that (`*.map_data.tres` and the rest of `GameData`'s index) have never been generated here, so rendering a real FFT map is blocked on standing up that pipeline, which is outside this change.
