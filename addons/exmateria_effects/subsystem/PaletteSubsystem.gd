extends "res://addons/exmateria_effects/subsystem/ColorSubsystem.gd"
## Runtime processor for palette-subsystem keyframes (map + unit tinting) - the
## ADR-0067 combat-colour route. Each channel's keyframes reduce to a [ColorStack]
## self-delivered (ADR-0014 dec. 2) over the real ALBEDO/CLUT base - the faithful
## PALETTE applier (color_tint_blend_apply @0x8008f710, 5-bit CLUT, quantize=true,
## absolute base); the stack is re-derived every frame, so any `now` is directly
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

# 8-bit additive map illumination deleted here (#1192); WHAT STAYS is
# exmateria_battlefield's MapIlluminationDDA.gd (ADR-0287 dec. 5: an extraction
# must not carry dead code into an addon).
# Full record: .vaults/comments/exmateria_effects/palette-subsystem-history.md

# DO NOT SPELL THE OLD res://addons/... PATH HERE, not even in prose -
# check_lattice_scene.py does not strip comments (ADR-0208 dec. 7), so a comment
# quoting the literal re-creates the very row that path paid.

# Parsed palette-keyframe data (PaletteData)
var palette_data = null

const AFFECTED_UNITS = "affected_units"
const CASTER = "caster"
const TARGET = "target"
const ALL_CHANNELS = [AFFECTED_UNITS, CASTER, TARGET]

# Caster / target unit refs for unit tinting; set by EffectInstance via set_units().
var _caster_unit: WeakRef = null
var _target_unit: WeakRef = null


## Build the per-channel [ColorStack] for ONE phase from the parsed keyframes.
## PALETTE applier profile: 5-bit CLUT (quantize=true); base is absolute, not delta-on-0.
func build_stack(channel: String, phase: String = EffectPhaseClass.PHASE_FOR_EACH) -> ColorStackClass:
	var stack: ColorStackClass = ColorStackClass.new()
	stack.set_quantize(true)  # palette applier is 5-bit CLUT (Consumer profile)
	_push_phase_ops(stack, channel, phase, 0)
	return stack


## Build ONE continuous stack for `channel` spanning every started phase at its
## ABSOLUTE start frame: the PSX engine is one stateful CLUT DDA with no phase
## concept - phase1's settled tint persists under for_each, no boundary pop (Raise/E005).
func build_stream(channel: String, phase_starts: Dictionary) -> ColorStackClass:
	var stack: ColorStackClass = ColorStackClass.new()
	stack.set_quantize(true)  # palette applier is 5-bit CLUT (Consumer profile)
	# Studio Solo/Mute: a muted lane (palette:<phase>:<channel>) excludes its ops from
	# the fold; recompiled per frame, so this + a rescrub drops just that lane.
	var has_mutes: bool = not _muted_ops.is_empty()
	for phase in EffectPhaseClass.ALL:
		if not phase_starts.has(phase):
			continue
		if has_mutes and _muted_ops.has("%s/%s" % [phase, channel]):
			continue
		_push_phase_ops(stack, channel, phase, phase_starts[phase])
	return stack


## Walk one phase's channel keyframes in timeline order, invoking `emit(kf, at)` for
## each ENABLED keyframe at its absolute frame.
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
	"""Take this owner's map and unit tints back out of the scene. The stack itself is
	rebuilt on every _deliver_output, but the LAYERS live in the tint registry, not the
	instance, so a seek to 0 (Studio Stop, U17) that pumps no frame would otherwise leave
	the map and the units tinted at the last played frame. The next advance re-delivers."""
	TintedSurfacesPort.remove_all_layers_for_owner(owner_id)


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
	# All started phases fold at their absolute offsets, so no channel pops back to
	# base at a phase boundary (Raise/E005).
	TintedSurfacesPort.update_stack(TintedSurfacesPort.SURFACE_MAP, owner_id, build_stream(AFFECTED_UNITS, _phase_first_frame), _frame)
	# Map ILLUMINATION (8-bit additive, FUN_80090dec) is INTENTIONALLY NOT delivered:
	# it only tints the PSX's UNTEXTURED flat-colour terrain, which Godot doesn't
	# render (framebuffer A/B on Holy's map: pixel-identical on vs off). Rebuild
	# scoped to such a class if one is ever added, never globally.
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
