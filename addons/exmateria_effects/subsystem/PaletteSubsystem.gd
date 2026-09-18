extends "res://addons/exmateria_effects/subsystem/ColorSubsystem.gd"
## Runtime processor for palette-subsystem keyframes (map + unit tinting) - the
## ADR-0067 combat-colour route. Three [ColorSubsystem] channels: affected_units ->
## the TintedSurfaces SURFACE_MAP token; caster / target -> the units' own tokens.
## Each channel's keyframes reduce to a [ColorStack] (build_stack / build_stream),
## self-delivered (ADR-0014 dec. 2) over the real ALBEDO/CLUT base - the faithful
## PALETTE applier (color_tint_blend_apply @0x8008f710, 5-bit CLUT, quantize=true,
## absolute base). The stack is re-derived every frame, so any `now` is directly
## evaluable. Stepper-replacement + illumination-deletion record:
## .vaults/comments/exmateria_effects/palette-subsystem-history.md
## Vault: [[Combat Color Appliers]]
## Vault: [[Map Tint]]

# ADR-0211 dec. 4 - the addon's facade is its whole symbol surface. One alias line
# per file keeps every use site's spelling.
const ColorStackClass = ExMateriaSchema.ColorStack

## The tint registry reached through its PORT - a member may name no autoload at all
## (ADR-0308 dec. 1). `SURFACE_MAP` comes off the port too, and it has to: a GDScript
## const is not a property, so node.SURFACE_MAP on a resolved autoload fails at RUNTIME.
## vault: .vaults/comments/exmateria_effects/port-contracts.md
const TintedSurfacesPort = preload("res://addons/exmateria_effects/install/TintedSurfacesPort.gd")

# 🟢 THE ILLUMINATION MACHINERY IS GONE (#1192): the 8-bit additive map flood was
# deleted on probe evidence (0x across eight battle/effect scenes). WHAT STAYS is
# exmateria_battlefield's (MapIlluminationDDA.gd, the map_illum_add uniform, still
# covered by MapIlluminationDDATest) - that package's call, not this one's
# (ADR-0287 dec. 5: an extraction must not carry dead code into an addon).
# Full record: .vaults/comments/exmateria_effects/palette-subsystem-history.md

# ADR-0208 dec. 2 + dec. 5 (NAMED, NOT PRELOADED) - the alias this described
# (MapIlluminationDDA) was deleted at #1192; the warning stands:
# ⚠️ DO NOT SPELL THE OLD res://addons/... PATH HERE, not even in prose -
# check_lattice_scene.py does not strip comments (ADR-0208 dec. 7), so a comment
# quoting the literal re-creates the very row that path paid.

# Parsed palette-keyframe data (PaletteData)
var palette_data = null

# Channel names.
const AFFECTED_UNITS = "affected_units"
const CASTER = "caster"
const TARGET = "target"
const ALL_CHANNELS = [AFFECTED_UNITS, CASTER, TARGET]

# Caster / target unit references for unit tinting - self-delivered in advance()
# (ADR-0014 dec. 2). Set by EffectInstance via set_units().
var _caster_unit: WeakRef = null
var _target_unit: WeakRef = null


## Build the per-channel [ColorStack] for ONE phase from the parsed keyframes - the
## ADR-0067 combat-colour route; the PALETTE applier profile: 5-bit CLUT so
## `quantize=true`, base = the surface's committed colour (absolute, not delta-on-0).
func build_stack(channel: String, phase: String = EffectPhaseClass.PHASE_FOR_EACH) -> ColorStackClass:
	var stack: ColorStackClass = ColorStackClass.new()
	stack.set_quantize(true)  # palette applier is 5-bit CLUT (Consumer profile)
	_push_phase_ops(stack, channel, phase, 0)
	return stack


## Build ONE continuous stack for `channel` spanning EVERY started phase at its
## ABSOLUTE start frame: the PSX color engine is one stateful CLUT DDA with no
## phase concept, so this keeps phase1's settled tint under for_each's fade-in - no
## pop at the boundary (Raise/E005 color-parity fix). A phase absent from
## `phase_starts` contributes nothing; a future phase's ops are inert anyway.
func build_stream(channel: String, phase_starts: Dictionary) -> ColorStackClass:
	var stack: ColorStackClass = ColorStackClass.new()
	stack.set_quantize(true)  # palette applier is 5-bit CLUT (Consumer profile)
	# Studio Solo/Mute: a muted lane (palette:<phase>:<channel>) excludes its ops from
	# the fold - recompiled per frame, so this + a rescrub drops just that lane. The
	# runtime never mutes, so short-circuit the per-phase key build in the common path.
	var has_mutes: bool = not _muted_ops.is_empty()
	for phase in EffectPhaseClass.ALL:
		if not phase_starts.has(phase):
			continue
		if has_mutes and _muted_ops.has("%s/%s" % [phase, channel]):
			continue
		_push_phase_ops(stack, channel, phase, phase_starts[phase])
	return stack


## Walk one phase's channel keyframes in timeline order, invoking `emit(kf, at)` for
## each ENABLED keyframe at its absolute frame. The single definition of the
## keyframe-timeline rule: the max_keyframe-1 processing window, the
## disabled-advances-timing-only skip, and the duration accumulation - a sink just
## says what to push, so a timing fix lands once.
func _each_keyframe(channel: String, phase: String, base_offset: int, emit: Callable) -> void:
	var ch = palette_data.get_channel(phase, channel)
	if not ch or ch.keyframes.is_empty():
		return
	var start_frame := 0
	# The PSX stepper breaks at kf_idx >= max_keyframe - 1, so it applies only
	# indices 0..max_keyframe-2; the rest are terminators/padding.
	var last_idx: int = mini(ch.keyframes.size(), maxi(0, ch.max_keyframe - 1))
	for i in range(last_idx):
		var kf = ch.keyframes[i]
		# Disabled keyframes (ctrl bit 7 clear) advance timing only - no PSX apply call.
		if kf.enabled:
			emit.call(kf, base_offset + start_frame)
		start_frame += maxi(1, kf.duration_frames)


## Push one phase's channel keyframes onto the 5-bit CLUT `stack`, each at its
## absolute frame. Shared by build_stack (single phase, offset 0) and build_stream.
func _push_phase_ops(stack: ColorStackClass, channel: String, phase: String, base_offset: int) -> void:
	_each_keyframe(channel, phase, base_offset, func(kf, at: int) -> void:
		stack.push_op(kf.blend_mode, kf.rgb.x, kf.rgb.y, kf.rgb.z, kf.time_value, at))


func initialize(data) -> void:
	"""Initialize subsystem with parsed palette-keyframe data. Channels are declared
	for owner_id / phase scaffolding; the tint itself is derived on demand from the
	keyframes by build_stack (no per-frame cursor state to seed)."""
	palette_data = data
	_setup_channels(ALL_CHANNELS)


func _evaluate(_channel: String, _phase: String) -> void:
	"""No-op: the palette timeline is DECLARATIVE (build_stack + the ColorStack DDA),
	so there is no per-frame stepper. _deliver_output rebuilds and delivers the stack
	each frame. Overridden empty because the base marks _evaluate abstract."""
	pass


func _reset_outputs() -> void:
	"""No held per-frame output state — the stack is rebuilt from the keyframes on
	every _deliver_output, so there is nothing to clear here."""
	pass


func set_units(caster, target) -> void:
	"""Set caster/target unit refs for unit tinting. The palette subsystem
	self-delivers the caster/target tints (ADR-0014 dec. 2), so it holds the unit refs
	EffectInstance used to push from. WeakRef avoids keeping freed units alive."""
	_caster_unit = weakref(caster) if caster else null
	_target_unit = weakref(target) if target else null


func _deliver_output() -> void:
	"""Self-deliver palette output (ADR-0014 dec. 2, ADR-0067): each channel's
	ColorStack -> its overlay, folded through color_apply over the real base. Map
	tint -> TintedSurfaces.SURFACE_MAP; caster/target tints -> the units' own tokens,
	which are runtime-only - no live caster/target in the editor preview."""
	# Every palette channel folds the WHOLE keyframe stream (all started phases at
	# their absolute offsets) at the absolute effect frame - the PSX-faithful one-
	# stateful-CLUT model, so no channel pops back to base at a phase boundary
	# (Raise/E005).
	TintedSurfacesPort.update_stack(TintedSurfacesPort.SURFACE_MAP, owner_id, build_stream(AFFECTED_UNITS, _phase_first_frame), _frame)
	# Map ILLUMINATION (8-bit additive, FUN_80090dec) is INTENTIONALLY NOT delivered:
	# statically it only tints the PSX's UNTEXTURED flat-colour terrain class, which
	# Godot doesn't render - the framebuffer A/B over Holy's map is pixel-identical
	# with the additive on vs off. The battlefield half stays in exmateria_battlefield
	# (header); rebuilt scoped to such a class if one is ever added, never globally.
	# Unit tints are runtime-only - no live caster/target in the editor preview.
	if Engine.is_editor_hint():
		return
	if _caster_unit:
		var caster = _caster_unit.get_ref()
		if caster:
			TintedSurfacesPort.update_stack(caster.get_instance_id(), owner_id, build_stream(CASTER, _phase_first_frame), _frame)
	if _target_unit:
		var target = _target_unit.get_ref()
		if target:
			TintedSurfacesPort.update_stack(target.get_instance_id(), owner_id, build_stream(TARGET, _phase_first_frame), _frame)
