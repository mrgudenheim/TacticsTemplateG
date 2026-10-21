// Camera angle global — the DECLARATION seam for the active in-game yaw on the PSX
// 0..0xFFF scale (0x000 north, 0x400 east, 0x800 south, 0xC00 west — FFT's BATTLE
// camera angle register). Declaration only.
//
// Same rule as `psx_sprite_stretch.gdshaderinc` beside it and `pixel_aspect.gdshaderinc`
// one directory over: the seam is where the name is declared, so a call site includes
// rather than redeclares.
//
// The writer is `PSXDisplay.set_camera_angle()` in this directory — the sixth global
// the port pushes and the only one that is not a Tune tunable, because it is per-frame
// camera state `PlayerCamera` computes and hands over rather than a knob a human
// scrubs (#590, ADR-0186 dec. 2).
//
// ⚠️ Its sibling `visible_angles_cull_mode` used to be declared beside it and is NOT
// here, because it stopped being a global at all: nothing in the tree ever WROTE it, so
// its only value in any session was the one `project.godot` declared. It is a `const`
// in `fft_visible_angles.gdshaderinc` now. The asymmetry is the test — a global uniform
// earns its host `[shader_globals]` entry by having a writer, and that one never had
// one.

global uniform int psx_camera_angle;  // 0..0xFFF
