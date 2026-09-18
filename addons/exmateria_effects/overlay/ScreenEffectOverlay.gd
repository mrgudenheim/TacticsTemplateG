extends Node
## Global singleton for screen background color during effects
##
## This is the BACKGROUND layer - map, units, and particles render ON TOP of it.
## Supports multi-effect composition via delta-based blending.
##
## Implementation: Finds the ScreenBackground quad in the camera scene.
## The quad is positioned at z=-100 behind everything else.
## render_priority -100 ensures it draws before (behind) other objects.
## Vault: [[Color Screen Opcode]]
## Vault: [[Screen Effect Gradient System]]

## ADR-0212 dec. 1 — `addons/exmateria_schema` used to declare six bare globals,
## every one of them generic English (`Fold`, `DepthMode`, `ColorStack`,
## `ColorRecipe`, `CellMarking`, `TerrainCell`). It now declares only
## `ExMateriaSchema`, so these lines are what keep the use sites below spelled the
## way they were (ADR-0211 dec. 4).
const ColorRecipe = ExMateriaSchema.ColorRecipe
const ColorStack = ExMateriaSchema.ColorStack

# Active effect layers for composition
# Each effect contributes a delta (change from default) that gets summed
var active_layers: Dictionary = {}  # owner_id -> {delta: Color, tint: Color}

# Current owner (for legacy last-writer-wins tracking)
var current_owner_id: int = 0

# Default gradient colors (returned to when effect clears)
# These should be set by the map/scene - the hardcoded values are fallbacks
var default_tl: Color = Color(0.1, 0.15, 0.3)  # Dark blue top
var default_tr: Color = Color(0.1, 0.15, 0.3)
var default_bl: Color = Color(0.3, 0.5, 0.7)   # Light blue bottom
var default_br: Color = Color(0.3, 0.5, 0.7)


func set_defaults(c_tl: Color, c_tr: Color, c_bl: Color, c_br: Color) -> void:
	"""Set default gradient colors (called by map/scene on load)

	These colors are used when effects clear or restore palette.
	"""
	default_tl = c_tl
	default_tr = c_tr
	default_bl = c_bl
	default_br = c_br
	# Also apply immediately if no effect is active
	if current_owner_id == 0:
		set_corners(c_tl, c_tr, c_bl, c_br, 0)


func set_default_gradient(top: Color, bottom: Color) -> void:
	"""Set default as a simple vertical gradient"""
	set_defaults(top, top, bottom, bottom)


func get_default_top() -> Color:
	"""The default gradient TOP baseline (average of the two top corners) — the
	baseline the screen ColorStack folds the top gradient endpoint over."""
	return Color((default_tl.r + default_tr.r) * 0.5, (default_tl.g + default_tr.g) * 0.5,
		(default_tl.b + default_tr.b) * 0.5, 1.0)


func get_default_bottom() -> Color:
	"""The default gradient BOTTOM baseline (average of the two bottom corners)."""
	return Color((default_bl.r + default_br.r) * 0.5, (default_bl.g + default_br.g) * 0.5,
		(default_bl.b + default_br.b) * 0.5, 1.0)

# Cached references
var _material: ShaderMaterial = null
var _initialized: bool = false


func _ready() -> void:
	# Material will be found when first effect tries to set color
	pass


func _find_background_material() -> void:
	"""Find the ScreenBackground quad's material in the camera scene"""
	if _initialized:
		return

	var viewport = get_viewport()
	if not viewport:
		return

	var camera = viewport.get_camera_3d()
	if not camera:
		push_error("ScreenEffectOverlay: No camera found")
		return

	# Find the ScreenBackground node (child of camera)
	var bg_quad = camera.get_node_or_null("ScreenBackground")
	if not bg_quad:
		push_error("ScreenEffectOverlay: ScreenBackground node not found in camera")
		return

	_material = bg_quad.material_override as ShaderMaterial
	if not _material:
		push_error("ScreenEffectOverlay: ScreenBackground has no ShaderMaterial")
		return

	_initialized = true


func set_corners(c_tl: Color, c_tr: Color, c_bl: Color, c_br: Color, owner_id: int) -> void:
	"""Set the background with 4-corner Gouraud shading (PSX-style)

	Args:
		tl: Top-left corner color
		tr: Top-right corner color
		bl: Bottom-left corner color
		br: Bottom-right corner color
		owner_id: Unique ID of the calling effect (for tracking ownership)
	"""
	current_owner_id = owner_id

	# Ensure we have the material reference
	if not _initialized:
		_find_background_material()

	if _material:
		_material.set_shader_parameter("color_tl", Vector3(c_tl.r, c_tl.g, c_tl.b))
		_material.set_shader_parameter("color_tr", Vector3(c_tr.r, c_tr.g, c_tr.b))
		_material.set_shader_parameter("color_bl", Vector3(c_bl.r, c_bl.g, c_bl.b))
		_material.set_shader_parameter("color_br", Vector3(c_br.r, c_br.g, c_br.b))


func set_tint(tint: Color, owner_id: int) -> void:
	"""Set the additive tint color (TINT mode overlay)

	TINT is ADDITIVE - it adds to the base gradient, not replaces it.
	(0,0,0) = no tint = base gradient shows through unchanged.

	Args:
		tint: Additive tint color
		owner_id: Unique ID of the calling effect (for tracking ownership)
	"""
	current_owner_id = owner_id

	if not _initialized:
		_find_background_material()

	if _material:
		_push_color_stack(Vector3(tint.r, tint.g, tint.b))


## ADR-0067: push the additive TINT into the color-stack uniforms so screen_background
## folds it via color_apply. The summed per-owner delta is ONE scale=1 affine layer
## (bias = the tint) — byte-exact vs the old `base + tint_color` per ColorStack.fold's
## additive-combat parity oracle.
func _push_color_stack(tint: Vector3) -> void:
	if _material == null:
		return
	var stack := ColorStack.new()
	stack.push_fixed_layer(ColorRecipe.affine(Vector3.ONE, tint), 1.0)
	stack.apply(_material, 0)


func clear_effect(owner_id: int) -> void:
	"""Clear the effect (return to default gradient, no tint)

	Only clears if caller is the current owner, or if owner_id is 0 (force clear).

	🔴 #1224 REMOVED THE `= 0` DEFAULT AND KEPT THE 0 SENTINEL, WHICH ARE TWO
	DIFFERENT THINGS. ADR-0288 dec. 7 cites *"an optional gate argument is a gate that
	never fires"* — true of the default, which let a caller opt out of ownership by
	saying nothing. It is NOT true of the VALUE: 0 is a documented force-clear here and
	`is_active()` reads `current_owner_id != 0`, so 0 means "unowned" throughout this
	file. Removing the sentinel would be a behaviour change; removing the default only
	makes every caller state which it wants. There were no callers of this verb to
	update.

	Args:
		owner_id: ID of the effect requesting clear
	"""
	if owner_id == 0 or owner_id == current_owner_id:
		# Return to default gradient
		set_corners(default_tl, default_tr, default_bl, default_br, 0)
		# Clear tint
		set_tint(Color.BLACK, 0)
		current_owner_id = 0


func is_active() -> bool:
	"""Check if an effect is currently controlling the background"""
	return current_owner_id != 0 or not active_layers.is_empty()


# === Multi-Effect Compositor ===

func update_layer_gradient(owner_id: int, top_delta: Color, bottom_delta: Color, tint: Color = Color.BLACK) -> void:
	"""Update an effect's contribution with independent TOP and BOTTOM gradient deltas
	(the screen ColorStack folds the map's top and bottom baselines separately —
	FUN_80090258 ramps each over its own baseline). top_delta lands on the top corners
	(tl, tr), bottom_delta on the bottom corners (bl, br)."""
	active_layers[owner_id] = {"top_delta": top_delta, "bottom_delta": bottom_delta, "tint": tint}
	_recomposite()


## Pure compositor: apply the summed TOP delta to the top corners (tl, tr) and the
## summed BOTTOM delta to the bottom corners (bl, br), clamped to [0,1]. Returns
## [tl, tr, bl, br]. Kept side-effect-free so it is unit-testable without a material.
static func compose_corners(def_tl: Color, def_tr: Color, def_bl: Color, def_br: Color, layers: Array) -> Array:
	var td := Vector3.ZERO
	var bd := Vector3.ZERO
	for l in layers:
		var t: Color = l.get("top_delta", Color.BLACK)
		var b: Color = l.get("bottom_delta", Color.BLACK)
		td += Vector3(t.r, t.g, t.b)
		bd += Vector3(b.r, b.g, b.b)
	return [
		_add_clamp(def_tl, td), _add_clamp(def_tr, td),
		_add_clamp(def_bl, bd), _add_clamp(def_br, bd)]


static func _add_clamp(c: Color, d: Vector3) -> Color:
	return Color(clampf(c.r + d.x, 0, 1), clampf(c.g + d.y, 0, 1), clampf(c.b + d.z, 0, 1), 1.0)


func remove_layer(owner_id: int) -> void:
	"""Remove an effect's contribution from the composite

	Called when an effect ends or is removed from the scene.

	Args:
		owner_id: Unique ID of the effect to remove
	"""
	if active_layers.has(owner_id):
		active_layers.erase(owner_id)
		_recomposite()


func _recomposite() -> void:
	"""Sum all active deltas and apply to default gradient"""
	if active_layers.is_empty():
		# No active effects - restore default gradient
		set_corners(default_tl, default_tr, default_bl, default_br, 0)
		set_tint(Color.BLACK, 0)
		current_owner_id = 0
		return

	# Composite TOP deltas onto the top corners and BOTTOM deltas onto the bottom
	# corners (pure, testable).
	var corners := compose_corners(default_tl, default_tr, default_bl, default_br, active_layers.values())
	set_corners(corners[0], corners[1], corners[2], corners[3], 0)

	# Sum + clamp the additive tints (defensive .get — symmetric with compose_corners).
	var total_tint := Vector3.ZERO
	for layer in active_layers.values():
		var tint: Color = layer.get("tint", Color.BLACK)
		total_tint += Vector3(tint.r, tint.g, tint.b)
	set_tint(Color(clampf(total_tint.x, 0.0, 1.0), clampf(total_tint.y, 0.0, 1.0), clampf(total_tint.z, 0.0, 1.0), 1.0), 0)
