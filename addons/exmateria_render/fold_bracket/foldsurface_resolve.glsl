#[vertex]
#version 450

// Fullscreen triangle (no vertex buffer). Pass C of the combat display-space
// composite (#209): resolve the DISPLAY-SPACE fold accumulator back into the LINEAR
// color layer. Runs once per frame after all mode buckets have folded into the
// scratch (pass A copy-in + pass B per-bucket blend).
//
// It resolves EVERY PIXEL. There is no coverage mark and no discard — see the block
// above main() for why the one this pass used to carry was deleted (ADR-0309).
void main() {
	vec2 v = vec2(float((gl_VertexIndex << 1) & 2), float(gl_VertexIndex & 2));
	gl_Position = vec4(v * 2.0 - 1.0, 0.0, 1.0);
}

#[fragment]
#version 450

layout(set = 0, binding = 0) uniform sampler2D scratch_tex;   // display-space fold accumulator

layout(location = 0) out vec4 frag_color;

layout(push_constant, std430) uniform Params {
	vec2 raster_size;
	float quantize_levels;   // steps-1 per channel; 31.0 == PSX RGB555. <= 0 disables (ADR-0152)
	float _pad;              // still 16 bytes: GDScript sends [x,y,levels,0]; the size is enforced exactly
} params;

vec3 srgb_to_lin(vec3 c) {
	c = clamp(c, vec3(0.0), vec3(1.0));
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}
// Framebuffer quantization — snap the display-space result to `levels+1` steps per
// channel. Applied ONCE here (not per prim): within a same-direction run integer add/sub
// has no rounding, so grouped-then-quantized == the per-prim fold (proto_ordered_fold Q3).
//
// The LEVEL is a policy the bracket is given, not a constant it owns (ADR-0152, goal #8).
// 31.0 is the PSX RGB555 framebuffer and is what this game runs; `levels <= 0` is a
// consumer that wants the fold without the 5-bit crush, and costs a branch, not a fork.
vec3 quantize(vec3 c, float levels) {
	c = clamp(c, vec3(0.0), vec3(1.0));
	if (levels <= 0.0) {
		return c;
	}
	return floor(c * levels + 0.5) / levels;
}

// THERE IS NO COVERAGE MARK (ADR-0309). This pass used to ask "did a carrier draw on this
// pixel?" and `discard` when the answer was no, so the untouched 3D background kept its
// full precision. The question is deleted, not merely answered better.
//
// 0. IT LOOKS BETTER — the user's reading of the shipped frame: "it makes the dithering look
//    better." FFT's art is dithered FOR a 5-bit framebuffer, and a dither exists to fake
//    intermediate colours on a coarse lattice; leave the background at full precision and the
//    pattern has no lattice under it and reads as noise instead of the gradient it fakes.
//    This is the ground that settles it. The three below are why it is also correct:
//
// 1. THE PLAYSTATION HAD NO SUCH CARVE-OUT. Its framebuffer was 15-bit for the WHOLE
//    screen: terrain, sprites and effects alike. `Render` IS the PlayStation look
//    (ADR-0117 dec. 6, ADR-0150), so sparing the background from the crush was the
//    infidelity and the mark was preserving it. The carve-out was never an ADR decision —
//    it entered as a property of `proto_ordered_fold` ("only touch effect pixels") and
//    survived here as a comment.
//
// 2. THE MARK COULD NOT BE COMPUTED FROM WHAT THIS PASS CAN SEE. Coverage was read off the
//    accumulator's ALPHA, seeded to a 0.5 baseline because Godot's `blend_sub` drives alpha
//    DOWN (REVERSE_SUBTRACT) while add/mix drive it UP. That test is not injective: a mix
//    carrier maps a_dst -> a_src + a_dst*(1 - a_src), so a mix whose own alpha IS the
//    baseline, landing on a pixel a sub carrier already drove to 0, returns
//    0.5 + 0*(1 - 0.5) = 0.5 — the untouched value, bit for bit. Live, that pair is {76}
//    Dark Screen's half blend over a unit's subtractive ground shadow: both contributions
//    were discarded and the shadow's footprint came back as the raw undrawn scene, BRIGHTER
//    than the dim around it. No baseline fixes it (every B in [0,1) is the fixed point of
//    some mix alpha), and the carriers blend into the only channel a mark could live in.
//
// 3. RESOLVING EVERYTHING COSTS 4/255, AND IT DOES NOT BAND. Measured over a real Orbonne
//    battle frame (1024x960): 88.34% of pixels move, 79.47% of channel samples move, worst
//    4/255, mean 1.366/255. Banding was the one real objection and it does not appear —
//    along the frame's smoothest large region the mean run of one identical colour goes
//    3.90 px -> 3.91 px, against a synthetic-gradient control arm where the same
//    measurement goes 3.48 px -> 28.00 px. This frame is dithered ROM palette art; it has
//    no smooth long-range gradient for a band to form in. Distinct colours 2432 -> 809,
//    which is what a 15-bit framebuffer is.
//
// The alternative that was NOT taken is a real per-pixel mark in the STENCIL, which is
// buildable — probed on the fork, not reasoned: `stencil_mode write` works on a
// `compositor_layer` member inside the engine's held-out pass (it LOADs the shared scene
// depth), and the stencil aspect is cleared every frame, including on the branch that
// clears depth only, because a combined depth/stencil attachment takes one load op for
// both. It was refused on FIDELITY ALONE — reason 1 says the carve-out it would implement
// faithfully is the wrong carve-out. It is NOT expensive: a discarded fragment does not
// write the stencil (probed), 17 of the 22 carriers already discard, and the price is 22
// one-line `stencil_mode` additions plus a depth attachment here. A cheap way to build the
// wrong thing is still the wrong thing. ADR-0309's "Considered options" carries the numbers
// and retracts the inflated cost an earlier reading of it claimed.
void main() {
	vec2 uv = gl_FragCoord.xy / max(params.raster_size, vec2(1.0));
	vec4 s = texture(scratch_tex, uv);
	frag_color = vec4(srgb_to_lin(quantize(s.rgb, params.quantize_levels)), 1.0);
}
