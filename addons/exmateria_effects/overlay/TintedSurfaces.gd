@tool
extends Node
## The registry of tinted surfaces — a set of `ShaderMaterial`s keyed by an opaque
## token, with a stack of colour ops composited onto each.
##
## Renamed from `UnitTintOverlay` in #1223: the class never dereferences the id it
## is keyed by — `src/units/Unit.gd:730` calls `register_surface()` with the
## material, and nothing here asks what the token points at — so `surface_id` is
## an opaque token (ADR-0288 dec. 7, split into a rename half and a merge half by
## ADR-0290 dec. 7).
##
## #1224 absorbed `MapTintOverlay` as the `SURFACE_MAP` case. ADR-0288 dec. 7 read
## *"MapTintOverlay IS UnitTintOverlay WITH THE SURFACE KEY ERASED"*; measured
## against the two files, it was the key plus four differences, preserved here
## rather than flattened:
##
##   1. A surface holds many materials, not one: `MapComposer` emits one material
##      per chunk and `BattlefieldWiring` registers each, while the unit side was
##      1:1, so `_surface_materials` maps a token to an array.
##   2. The map's `update_stack` had no registration guard — materials arrive from
##      `MapComposer` on a signal and may arrive late — so `SURFACE_MAP` is reserved
##      at `_ready` with an empty material list, and `has()` is always true for it.
##   3. `update_layer` used a different mask: the unit's packs `MASK_WHOLE`, the
##      map's packed `MASK_SURFACE0` ("map is a single-surface consumer"). The mask
##      is chosen per surface below; the map's variant had zero callers, so nothing
##      would have caught a flattening.
##   4. The map had a third colour sink the unit side has no counterpart for — the
##      8-bit additive map-illumination applier (FUN_80090dec, Holy/E015). #1224
##      carried it over whole; #1192 (2026-09-12) deleted it: its producer half in
##      `PaletteSubsystem` was measured unreached — 2 hits in its own unit test as a
##      positive control, 0 across eight battle and effect-playback scenes — and the
##      owner ruled the future untextured-terrain scope dead.
##
## Deletion record: `MapTintOverlay.is_active()` — zero callers anywhere, tests
## included; `is_surface_registered()` already answers the neighbouring question.
##
## Implementation (ADR-0067 combat route, issue #164): concatenates each effect
## owner's ColorStack snapshot into the unified `color_layer_*` uniforms, so combat
## palette effects fold through color_apply over the real ALBEDO at 5-bit CLUT
## fidelity (Consumer profile: the palette applier color_tint_blend_apply
## @0x8008f710 — quantize=true, absolute base). This replaces the old additive
## `unit_tint` uniform, which couldn't express the base-dependent luma / absolute-
## base modes. `update_layer(delta)` is kept as the additive bridge for the one
## purely-additive consumer (TrapPaletteController until ADR-0369 retired it). For the map the same fold
## happens on the palette entry before lighting — the faithful CLUT-engine
## behaviour, the map being tinted by its CLUT contents changing.
## Vault: [[Map Tint]]

const ColorStackClass = ExMateriaSchema.ColorStack

## The reserved token for the MAP surface (#1224). Every other token in this registry
## is a `Node.get_instance_id()`, which the engine never returns as 0, so 0 cannot
## collide with a unit. Reserved at `_ready` so its material list exists before
## `BattlefieldWiring` registers anything into it — see difference 2 in the header.
const SURFACE_MAP: int = 0

# Maps an opaque surface token -> Array[ShaderMaterial]. A unit holds one; the map
# holds one per composed chunk (#1224, difference 1). Every non-map token is a
# `Unit.get_instance_id()`; nothing here depends on that (#1223).
var _surface_materials: Dictionary = {}

# Active effect layers for composition.
# Maps surface_id -> {owner_id -> {rgb0: Array[Vector4], rgb1: Array[Vector4], meta: Array[int]}}
# Each entry is a pre-evaluated ColorStack snapshot (see update_stack / update_layer).
var _active_layers: Dictionary = {}

# A unit's STATUS tint (#2060): surface_id -> one packed snapshot, like an owner's. Kept apart
# from the effect owners because the ROM's status palette yields to them: it returns while
# a palette effect owns the unit (`palette_modifier != 0` in
# `battle_gfx_update_misc_unit_status_palette`), and the effect's track reads the sheet's own
# CLUT, not the tinted one. So it is folded only while the surface has no effect owner.
var _status_layers: Dictionary = {}



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
	_status_layers.erase(surface_id)


func set_status_stack(surface_id: int, stack) -> void:
	"""Set (or, with `stack == null`, clear) a unit's status tint (#2060). A snapped,
	time-free stack: it is evaluated at frame 0. Folded only while no effect owner is
	active on the surface — see `_status_layers`."""
	if not _surface_materials.has(surface_id) or surface_id == SURFACE_MAP:
		return
	if stack == null:
		if not _status_layers.has(surface_id):
			return
		_status_layers.erase(surface_id)
	else:
		stack.evaluate(0)
		_status_layers[surface_id] = {
			"rgb0": stack.rgb0().duplicate(),
			"rgb1": stack.rgb1().duplicate(),
			"meta": stack.meta().duplicate(),
		}
	_recomposite(surface_id)


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
	(its consumer, TrapPaletteController, was retired by ADR-0369). The delta becomes one scale=1 affine layer (bias =
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
	var owners: Array = _active_layers[surface_id].values() if _active_layers.has(surface_id) else []
	if owners.is_empty() and _status_layers.has(surface_id):
		owners = [_status_layers[surface_id]]
	for snap in owners:
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
	(`TrapPaletteController`, retired by ADR-0369) only ever asked about units.
	"""
	return _surface_materials.has(surface_id)


func get_surface_count() -> int:
	"""Number of known surfaces, for debugging. Counts the reserved `SURFACE_MAP`, so a
	tree with no units reads 1, not 0."""
	return _surface_materials.size()
