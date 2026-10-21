extends RefCounted
## Picks the camera YAW that keeps a focused unit in view (gl-ADR-0410, amending ADR-0039).
##
## Godot heir to `battle_camera_choose_unblocked_rotation_for_tile` 0x801AAC28 (the effect
## camera's TARGET / CASTER / CURSOR angle sources) and, through the host, to
## `battle_camera_rotate_when_unit_tile_not_visible` 0x80070820 (the battle camera). Only yaw
## is chosen; pitch and zoom are the caller's. Candidates are the ROM's, in the ROM's order:
## the snapped base yaw, +90, -90, +180 (PSX 0x400 = 90 deg).
##
## Two rules, picked per call by the host's `occlusion_mode` (Battlefield's
## `camera.occlusion_mode` tunable):
##
##   * ROM — byte +7 of the unit's tile, exactly as 0x801AAC28 reads it: keep the base if its
##     quadrant bit is clear OR all four are set (0xF); else +0x400, else -0x400, else
##     `(yaw + 0x800) & 0xFFF`. Other units never count. The battle camera passes
##     `steep` = pitch >= 0x178 for the high nibble; the effect camera always reads the flat one.
##   * LIVE (default) — the rendered map: the MOST VISIBLE candidate, i.e. the largest fraction of
##     the unit's SPRITE drawn in front of the map at the candidate's SETTLED pose (the pitch and
##     yaw the camera ends the keyframe at, so the view tested is the view the player sees). The
##     current yaw is kept only when nothing beats it. Among equally visible candidates,
##     ADR-0039's composition: fewest other UNITS in the way (physics, mask 4), then fewest
##     neighbours in front (skipped with `count_units` false — the battle camera's map-only
##     rule), then ROM order.
##
## The resolver owns the choice; the terrain question is the host's, injected as Callables so
## this addon reaches no battlefield type (#1193):
##   sightline(unit, pitch12: float, psx_yaw: int) -> float     fraction of its sprite drawn
##   rom_mask(feet: Vector3, steep: bool) -> int                        the byte +7 nibble there
##   occlusion_mode() -> int                                            MODE_ROM or MODE_LIVE
## An invalid `sightline` means no terrain: LIVE keeps the base yaw (the standalone viewer).
## Vault: [[Embedded MIPS Effect Code]]

## ADR-0212 dec. 1 — alias the published `ExMateriaPlatform` global; the PSX
## trio has no bare `class_name` since extraction #7 (#1220) (ADR-0211 dec. 4),
## so this alias is the only spelling of the sign axis below.
const PsxChirality = ExMateriaPlatform.PsxChirality


# Do not reintroduce a preload-of-a-path spelling of the sign axis here — not
# even in a comment: `membership_arms.py`'s arm-6 shape scan counts a
# preload-of-a-path wherever the form appears, and a commented-out reach is
# still a reader's map to a dead address (ADR-0212 dec. 4). The old local
# `PSXConvert` alias pointed at `src/effects/PSXCameraConvert.gd`.

## Mirrors Battlefield's `Sightline.Mode` (an addon cannot name another's enum).
const MODE_ROM := 0
const MODE_LIVE := 1

const QUARTER_TURN := 1024.0   # PSX 0x400 = 90 deg
const HALF_TURN := 2048.0      # 180 deg
## 0x801B69D8, indexed by `(yaw & 0xFFF) >> 10`.
const QUADRANT_BITS := [0x08, 0x04, 0x02, 0x01]

# Collision layers: tiles = 2, units = 4.
const MASK_UNITS := 4

# Unit-occluder ray heights (Godot units above the feet) for the composition tie-break. The
# SelectionArea hitbox spans y in [0,1]; sprites read taller, so the rays go to ~head height.
const SILHOUETTE_HEIGHTS := [0.1, 0.5, 1.0, 1.5]
## A view showing less than this fraction of a sprite counts as HIDDEN when the camera is
## measured (tests, `CameraOcclusionRenderTest`). It is not a gate: LIVE always takes the most visible.
const HIDDEN_BELOW := 0.5

# How far back along the view ray the eye sits (Godot units): past any map's relief.
const PROBE_DISTANCE := 80.0
# Radius (Godot units, ~tiles) for the "adjacent units" foreground query.
const NEIGHBOUR_RADIUS := 2.5
const NEIGHBOUR_MAX := 16

var _world: Node3D   # in-tree Node3D, for get_world_3d().direct_space_state (units)
var _sightline: Callable
var _rom_mask: Callable
var _occlusion_mode: Callable


func _init(world_node: Node3D, sightline: Callable, rom_mask: Callable = Callable(),
		occlusion_mode: Callable = Callable()) -> void:
	_world = world_node
	_sightline = sightline
	_rom_mask = rom_mask
	_occlusion_mode = occlusion_mode


func mode() -> int:
	return int(_occlusion_mode.call()) if _occlusion_mode.is_valid() else MODE_LIVE


## The chosen base yaw in PSX units (4096 = 360), base + {0, +90, -90, +180} in the caller's
## winding so the downstream lerp takes the ROM's path. `base_yaw_12bit` is the snapped yaw
## (`& 0xE00`); `pitch_12bit` and `view_yaw_offset` are the pose the keyframe SETTLES at
## (LIVE tests pitch `pitch_12bit`, yaw `candidate + view_yaw_offset`). `steep` selects byte
## +7's high nibble (ROM only).
func resolve_facing_yaw(base_yaw_12bit: float, pitch_12bit: float, focused_unit,
		view_yaw_offset: float = 0.0, steep: bool = false, count_units: bool = true) -> float:
	if not is_instance_valid(focused_unit):
		return base_yaw_12bit
	if mode() == MODE_ROM:
		return _rom_choice(base_yaw_12bit, focused_unit, steep)
	if not _sightline.is_valid():
		return base_yaw_12bit
	return _live_choice(base_yaw_12bit, pitch_12bit, focused_unit, view_yaw_offset, count_units)


## 0x801AAC28 over `mask` (byte +7's nibble), in the caller's winding. Public for tests: the
## four branches are a pure function of the base yaw and the nibble.
static func rom_rule(base_yaw_12bit: float, mask: int) -> float:
	var raw := int(base_yaw_12bit)
	var rom_yaw := raw & 0xE00
	var winding := float(raw - (raw & 0xFFF))   # whole turns of the caller's winding
	var q := (raw & 0xFFF) >> 10
	mask &= 0x0F
	if (QUADRANT_BITS[q] & mask) == 0 or mask == 0x0F:
		return winding + rom_yaw
	if (QUADRANT_BITS[(q + 1) & 3] & mask) == 0:
		return winding + rom_yaw + 0x400
	if (QUADRANT_BITS[(q - 1) & 3] & mask) == 0:
		return winding + rom_yaw - 0x400
	return winding + ((rom_yaw + 0x800) & 0xFFF)


func _rom_choice(base_yaw_12bit: float, unit, steep: bool) -> float:
	var mask := 0
	if _rom_mask.is_valid():
		mask = int(_rom_mask.call(unit.global_position, steep))
	return rom_rule(base_yaw_12bit, mask)


func _live_choice(base_yaw_12bit: float, pitch_12bit: float, focused_unit, view_yaw_offset: float,
		count_units: bool = true) -> float:
	var subject: Vector3 = focused_unit.global_position
	var exclude := _unit_exclude(focused_unit)
	var space := _unit_space() if count_units else null
	# Neighbour positions are yaw-independent — gather once, score per candidate.
	var neighbours := _gather_neighbours(space, subject, exclude)

	var candidates := [
		base_yaw_12bit,
		base_yaw_12bit + QUARTER_TURN,
		base_yaw_12bit - QUARTER_TURN,
		base_yaw_12bit + HALF_TURN,
	]

	# The MOST VISIBLE candidate (gl-ADR-0410 dec. 2): the largest drawn fraction wins. Among
	# equally visible ones, ADR-0039's composition (fewest other units in the way, then fewest
	# neighbours in front) when units count, then the ROM's order — so the current yaw is kept
	# only when nothing is more visible. Strict improvement only: an equal later candidate never
	# displaces an earlier one.
	var best_yaw := base_yaw_12bit
	var best_fraction := -1.0
	var best_occluders := 0x7fffffff
	var best_in_front := 0x7fffffff
	for yaw in candidates:
		var view_yaw: float = yaw + view_yaw_offset
		var fraction := terrain_visible_fraction(focused_unit, pitch_12bit, view_yaw)
		var forward := _view_forward(pitch_12bit, view_yaw)   # eye -> subject
		var occ := _occluder_count(space, subject, -forward, exclude)
		var in_front := 0
		for n in neighbours:
			if (n - subject).dot(forward) < 0.0:
				in_front += 1
		if fraction > best_fraction or (fraction == best_fraction and (occ < best_occluders
				or (occ == best_occluders and in_front < best_in_front))):
			best_fraction = fraction
			best_occluders = occ
			best_in_front = in_front
			best_yaw = yaw
	return best_yaw


## Fraction of `unit`'s sprite the player sees from a camera at (`pitch_12bit`, `yaw_12bit`),
## the map only (other units are the tie-break). The host answers it from the frame the renderer
## would draw (Battlefield's `Sightline.drawn_fraction`). Public so tests can exercise the gate.
func terrain_visible_fraction(unit, pitch_12bit: float, yaw_12bit: float) -> float:
	if not _sightline.is_valid() or not is_instance_valid(unit):
		return 1.0
	return float(_sightline.call(unit, pitch_12bit, posmod(roundi(yaw_12bit), 4096)))


# --- helpers -----------------------------------------------------------------

func _view_forward(pitch_12bit: float, yaw_12bit: float) -> Vector3:
	"""Godot world direction the camera looks (eye -> subject) for a pose."""
	var rot := PsxChirality.psx_angles_to_godot_rotation(pitch_12bit, yaw_12bit, 0.0)
	var basis := Basis.from_euler(rot)
	return (basis * Vector3(0, 0, -1)).normalized()


func _unit_space() -> PhysicsDirectSpaceState3D:
	if _world == null or not _world.is_inside_tree():
		return null
	return _world.get_world_3d().direct_space_state


func _unit_exclude(unit) -> Array:
	"""RID of the focused unit's own SelectionArea, so its body never counts as
	an occluder of itself."""
	if not (unit is Node):
		return []
	var area = unit.get_node_or_null("SelectionArea")
	if area:
		return [area.get_rid()]
	return []


func _occluder_count(space: PhysicsDirectSpaceState3D, subject: Vector3, to_cam: Vector3, exclude: Array) -> int:
	"""Distinct OTHER units whose body lies between the silhouette and the camera."""
	if space == null:
		return 0
	var seen := {}
	for h in SILHOUETTE_HEIGHTS:
		var origin: Vector3 = subject + Vector3(0, h, 0)
		var q := PhysicsRayQueryParameters3D.create(
			origin, origin + to_cam * PROBE_DISTANCE, MASK_UNITS)
		q.exclude = exclude
		q.collide_with_areas = true    # units are Area3D
		q.collide_with_bodies = false
		var hit := space.intersect_ray(q)
		if hit.has("collider") and hit.collider != null:
			seen[hit.collider.get_instance_id()] = true
	return seen.size()


func _gather_neighbours(space: PhysicsDirectSpaceState3D, subject: Vector3, exclude: Array) -> Array:
	"""World positions of nearby units (for the foreground tie-break)."""
	if space == null:
		return []
	var sphere := SphereShape3D.new()
	sphere.radius = NEIGHBOUR_RADIUS
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = sphere
	q.transform = Transform3D(Basis(), subject)
	q.collision_mask = MASK_UNITS
	q.exclude = exclude
	q.collide_with_areas = true
	q.collide_with_bodies = false
	var positions := []
	for hit in space.intersect_shape(q, NEIGHBOUR_MAX):
		var c = hit.get("collider")
		if c != null and c is Node3D:
			positions.append((c as Node3D).global_position)
	return positions
