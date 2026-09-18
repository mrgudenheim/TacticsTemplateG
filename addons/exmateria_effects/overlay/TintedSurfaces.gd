@tool
extends Node
## The registry of TINTED SURFACES — a set of `ShaderMaterial`s keyed by an opaque
## token, with a stack of colour ops composited onto each.
##
## 🔴 IT WAS CALLED `UnitTintOverlay` UNTIL #1223, AND THE OLD NAME CLAIMED A
## COUPLING THAT DOES NOT EXIST. This class never dereferences the id it is keyed by:
## `src/units/Unit.gd:730` calls `register_surface()` WITH THE MATERIAL, and nothing
## here ever asks what the token points at. So it was never a registry of units — it
## is a registry of surfaces, and `surface_id` is an opaque token (ADR-0288 dec. 7,
## split into a rename half and a merge half by ADR-0290 dec. 7).
##
## 🔴 #1224 ABSORBED `MapTintOverlay` AS THE `SURFACE_MAP` CASE, AND THE "ERASED KEY"
## FRAMING WAS NOT QUITE TRUE. ADR-0288 dec. 7 reads *"MapTintOverlay IS
## UnitTintOverlay WITH THE SURFACE KEY ERASED"*. Measured against the two files, it
## was the key plus **four** differences, every one of which is preserved here rather
## than flattened:
##
##   1. **A surface holds MANY materials, not one.** `MapTintOverlay` kept
##      `_map_materials: Array[ShaderMaterial]` — `MapComposer` emits one material per
##      chunk and `BattlefieldWiring` registers each — while the unit side was 1:1. So
##      `_surface_materials` now maps a token to an ARRAY. A unit registers one and
##      behaves exactly as before; the map registers several under one token, which is
##      what makes the erased-key claim true instead of nearly true.
##   2. **The map's `update_stack` had no registration guard.** The unit's returns
##      early when the surface is unknown; the map's stored the layer regardless,
##      because materials arrive from `MapComposer` on a signal and may arrive late.
##      `SURFACE_MAP` is therefore RESERVED at `_ready` with an empty material list, so
##      `has()` is always true for it and the guard never fires for the map — identical
##      behaviour on both sides with no branch in the hot path.
##   3. **`update_layer` used a DIFFERENT MASK.** The unit's packs `MASK_WHOLE`; the
##      map's packed `MASK_SURFACE0` (*"map is a single-surface consumer"*). Flattening
##      that would have silently changed what a map delta means, so the mask is chosen
##      per surface below. The map's variant had ZERO callers, so nothing would have
##      caught it.
##   4. **The map had a THIRD colour sink the unit side has no counterpart for** — the
##      8-bit additive map-illumination applier (FUN_80090dec, Holy/E015). #1224 carried
##      it over whole, on the grounds that *deleting a documented retention is a different
##      argument from merging two registries*. 🟢 **#1192 THEN MADE THAT ARGUMENT AND
##      IT IS GONE** (2026-09-12): its producer half in `PaletteSubsystem` was measured
##      unreached — 2 hits in its own unit test as a positive control, 0 across eight
##      battle and effect-playback scenes — and the owner ruled the future
##      untextured-terrain scope dead. Producer and sink were one feature in two files, so
##      both went; keeping this half would have left a sink nothing feeds. The difference
##      is recorded rather than erased because it is why the merge was not a pure
##      key-erasure.
##
## WHAT DID NOT SURVIVE: `MapTintOverlay.is_active()` is gone. Zero callers anywhere,
## tests included, and `is_surface_registered()` already answers the neighbouring
## question. That is a deletion, said out loud, not a fold.
##
## Implementation (ADR-0067 combat route, issue #164): concatenates each effect
## owner's ColorStack snapshot into the unified `color_layer_*` uniforms, so combat
## palette effects fold through color_apply over the real ALBEDO at 5-bit CLUT
## fidelity (Consumer profile: the palette applier color_tint_blend_apply
## @0x8008f710 — quantize=true, absolute base). This REPLACES the old additive
## `unit_tint` uniform, which couldn't express the base-dependent luma / absolute-
## base modes. update_layer(delta) is kept as the additive bridge for the one
## purely-additive consumer (TrapPaletteController). For the map the same fold happens
## on the palette entry BEFORE lighting — the faithful CLUT-engine behaviour, the map
## being tinted by its CLUT contents changing.
## Vault: [[Map Tint]]

const ColorStackClass = ExMateriaSchema.ColorStack

## The reserved token for the MAP surface (#1224). Every other token in this registry
## is a `Node.get_instance_id()`, which the engine never returns as 0, so 0 cannot
## collide with a unit. Reserved at `_ready` so its material list exists before
## `BattlefieldWiring` registers anything into it — see difference 2 in the header.
const SURFACE_MAP: int = 0

# Maps an opaque surface token -> Array[ShaderMaterial]. A unit holds ONE; the map
# holds one per composed chunk (#1224, difference 1). Today every non-map token is a
# `Unit.get_instance_id()`; nothing here depends on that (#1223).
var _surface_materials: Dictionary = {}

# Active effect layers for composition.
# Maps surface_id -> {owner_id -> {rgb0: Array[Vector4], rgb1: Array[Vector4], meta: Array[int]}}
# Each entry is a pre-evaluated ColorStack snapshot (see update_stack / update_layer).
var _active_layers: Dictionary = {}



func _ready() -> void:
	reserve_map_surface()


## `SURFACE_MAP` exists from boot, with no materials yet. See difference 2.
##
## Public so a test that instantiates this script directly (rather than reaching the
## autoload) can put it in the same state — `MapTintOverlay` needed no such call
## because its material list was a plain member.
func reserve_map_surface() -> void:
	if not _surface_materials.has(SURFACE_MAP):
		_surface_materials[SURFACE_MAP] = []
	if not _active_layers.has(SURFACE_MAP):
		_active_layers[SURFACE_MAP] = {}


func register_surface(surface_id: int, material: ShaderMaterial) -> void:
	"""Add a material to a surface's material set.

	Called by Unit._initialize_materials() after creating the material — with the
	MATERIAL, which is why the key is opaque to this class (#1223) — and by
	`src/scenes/BattlefieldWiring.gd` once per composed map material, plus on
	`map_material_created` for every later one.

	DE-DUPLICATES BY DESIGN: `BattlefieldWiring.wire_map` is documented re-callable and
	relies on a repeat registration being a no-op (it was `MapTintOverlay`'s contract
	and it is kept).

	Args:
		surface_id: an opaque token the caller owns — `SURFACE_MAP`, or
			`get_instance_id()` of the Unit node at every other call site today
		material: a shader material belonging to that surface
	"""
	if material == null:
		return
	if not _surface_materials.has(surface_id):
		_surface_materials[surface_id] = []
		_active_layers[surface_id] = {}
	var mats: Array = _surface_materials[surface_id]
	if material not in mats:
		mats.append(material)


func unregister_surface(surface_id: int) -> void:
	"""Drop a surface and clear the tint off its materials.

	Called by Unit._exit_tree() when the unit is removed from the scene. `SURFACE_MAP`
	is reserved and cannot be unregistered — a map's materials are replaced by the next
	composition, never withdrawn, so there is no caller and no meaning for it.

	Args:
		surface_id: the token handed to register_surface
	"""
	if surface_id == SURFACE_MAP:
		return
	if _surface_materials.has(surface_id):
		# Clear the colour stack before removing (count 0 + quantize false = no-op).
		for mat in _surface_materials[surface_id]:
			if mat:
				ColorStackClass.apply_packed(mat, [], [], [], false)
		_surface_materials.erase(surface_id)
	if _active_layers.has(surface_id):
		_active_layers.erase(surface_id)


func update_stack(surface_id: int, owner_id: int, stack, now: int) -> void:
	"""Update an effect's ColorStack contribution to one surface (ADR-0067).

	The stack is evaluated at `now` and its packed snapshot stored; all owners'
	snapshots concatenate into that surface's color_layer_* uniforms, folded by
	color_apply. Over the real ALBEDO for a unit; on the palette entry pre-lighting for
	the map.

	Args:
		surface_id: `SURFACE_MAP`, or get_instance_id() of the target Unit
		owner_id: Unique ID of the effect (PaletteSubsystem.owner_id)
		stack: the owner's ColorStack for this channel
		now: frame to evaluate the stack's DDA at
	"""
	if not _surface_materials.has(surface_id):
		return
	if not _active_layers.has(surface_id):
		_active_layers[surface_id] = {}
	stack.evaluate(now)
	_active_layers[surface_id][owner_id] = {
		"rgb0": stack.rgb0().duplicate(),
		"rgb1": stack.rgb1().duplicate(),
		"meta": stack.meta().duplicate(),
	}
	_recomposite(surface_id)


func update_layer(surface_id: int, owner_id: int, tint: Color) -> void:
	"""Additive-bridge contribution for a purely-additive consumer
	(TrapPaletteController). The delta becomes one scale=1 affine layer (bias =
	delta), so it folds to base + delta through the same stack seam as update_stack.

	🔴 THE MASK DIFFERS BY SURFACE and that is preserved, not flattened (#1224,
	difference 3): a unit delta packs `MASK_WHOLE`, the map's packs `MASK_SURFACE0`
	because the map is a single-surface consumer. The map arm has no caller today, so
	nothing would have caught it being silently changed to `MASK_WHOLE`.

	Args:
		surface_id: `SURFACE_MAP`, or get_instance_id() of the target Unit
		owner_id: Unique ID of the effect
		tint: Color delta (can be negative for darkening)
	"""
	if not _surface_materials.has(surface_id):
		return
	if not _active_layers.has(surface_id):
		_active_layers[surface_id] = {}
	var mask: int = (ColorStackClass.MASK_SURFACE0 if surface_id == SURFACE_MAP
			else ColorStackClass.MASK_WHOLE)
	_active_layers[surface_id][owner_id] = {
		"rgb0": [Vector4(1.0, 1.0, 1.0, 1.0)],  # scale = 1, progress = 1
		"rgb1": [Vector4(tint.r, tint.g, tint.b, 0.0)],  # bias = delta, div = 0 (affine)
		"meta": [mask],
	}
	_recomposite(surface_id)


func remove_layer(surface_id: int, owner_id: int) -> void:
	"""Remove an effect's contribution from a surface's composite.

	Called when an effect ends or is removed from the scene. It used to clear the
	additive illumination sink for the same owner as well; #1192 deleted that sink.

	Args:
		surface_id: `SURFACE_MAP`, or get_instance_id() of the target Unit
		owner_id: Unique ID of the effect to remove
	"""
	if _active_layers.has(surface_id) and _active_layers[surface_id].has(owner_id):
		_active_layers[surface_id].erase(owner_id)
		_recomposite(surface_id)


func remove_all_layers_for_owner(owner_id: int) -> void:
	"""Remove all of one effect owner's contributions, from every surface.

	Called when an effect ends. It used to sweep the additive illumination sink too;
	#1192 deleted that sink.

	Args:
		owner_id: Unique ID of the effect (PaletteSubsystem.owner_id)
	"""
	for surface_id in _active_layers.keys():
		if _active_layers[surface_id].has(owner_id):
			_active_layers[surface_id].erase(owner_id)
			_recomposite(surface_id)


func _recomposite(surface_id: int) -> void:
	"""Concatenate all active owners' ColorStack snapshots and push them to EVERY
	material of that surface as the unified color_layer_* uniforms (ADR-0067)."""
	if not _surface_materials.has(surface_id):
		return

	var rgb0: Array = []
	var rgb1: Array = []
	var meta: Array = []
	if _active_layers.has(surface_id):
		for snap in _active_layers[surface_id].values():
			rgb0.append_array(snap.rgb0)
			rgb1.append_array(snap.rgb1)
			meta.append_array(snap.meta)

	if rgb0.size() > ColorStackClass.MAX_COLOR_LAYERS:
		push_warning("TintedSurfaces: %d combat colour layers on surface %d exceed budget %d; extras dropped" % [
			rgb0.size(), surface_id, ColorStackClass.MAX_COLOR_LAYERS])

	# Palette applier is the 5-bit CLUT engine (Consumer profile) -> quantize=true.
	for mat in _surface_materials[surface_id]:
		if mat:
			ColorStackClass.apply_packed(mat, rgb0, rgb1, meta, true)


func is_surface_registered(surface_id: int) -> bool:
	"""Whether a surface is known to this registry.

	⚠️ TRUE FOR `SURFACE_MAP` FROM BOOT, materials or not — it is reserved (difference
	2). The map never had an is-registered question; the unit side's one caller
	(`TrapPaletteController`) only ever asks about units.
	"""
	return _surface_materials.has(surface_id)


func get_surface_count() -> int:
	"""Number of known surfaces, for debugging. Counts the reserved `SURFACE_MAP`, so a
	tree with no units reads 1, not 0."""
	return _surface_materials.size()
