# ExMateria Sound — Godot 4 addon

Final Fantasy Tactics (PSX) sound reimplementation as a Godot 4 addon.
Plays FFT `.SMD` music and battle effect SFX with disassembly-faithful
sequencing, driven by a native C++ SPU core.

## Install

Drop this `addons/exmateria_sound/` folder into your Godot project's
`addons/` directory. Then in **Project → Project Settings → Plugins**,
enable **ExMateria Sound**.

The folder is self-contained — runtime GDScript, the GDExtension
descriptor, and pre-built native binaries are all inside.

## Native binary

`bin/` contains `libfftspu.<platform>.<target>.<arch>.<so|dll>`. If
your platform isn't present, rebuild from the SPU-Core source (see
[ExMateria-SPU-Core](https://github.com/timbermania/ExMateria-SPU-Core))
or from the umbrella source at [ExMateria-Sound](https://github.com/timbermania/ExMateria-Sound):

```bash
git submodule update --init --recursive extern/godot-cpp
scons platform=<linux|windows|macos> target=template_debug
```

The build script writes directly into this `addons/exmateria_sound/bin/`.

## Asset injection

The addon resolves the FFT-extract tree (the `SOUND/` and `EFFECT/`
dirs from a personally extracted PSX disc) via `AssetPaths`:

1. `EXMATERIA_ASSETS_DIR` env var, if set.
2. Standard exmateria data dir (XDG / AppData / macOS Library).
3. Walk up from the Godot project dir for `project-assets/fft-extract/`
   (monorepo dev fallback).

Override per-call by passing explicit paths.

## Public API

### Music playback

```gdscript
var player := SMDPlayer.new()
add_child(player)
player.load_waveset(AssetPaths.default_waveset_path())
player.play_smd(AssetPaths.default_smd_path(31))
```

### Effect / scene driver

```gdscript
var controller := SoundTrackController.new()
add_child(controller)
controller.configure(AssetPaths.default_sound_dir(), AssetPaths.default_effect_dir())
controller.start_effect(effect_id, ...)
```

### Sound resolution

```gdscript
var resolver := EffectSoundResolver.new()
var bank := resolver.bank_for(sound_id)
```

## What you should NOT poke at

`runtime/effect_sound/` (dispatcher, flush_tick, pool, etc.) is the
internal opcode VM. Treat it as private — names mirror FFT semantics
on purpose so that probe-driven debugging stays legible.

## License

See [LICENSE](../../LICENSE) at the published repo root.

## Source

Developed in the `timbermania/ExMateria-Sound` repo (this repo). For
the SPU C++ core only (no Godot addon), see
[`timbermania/ExMateria-SPU-Core`](https://github.com/timbermania/ExMateria-SPU-Core).
