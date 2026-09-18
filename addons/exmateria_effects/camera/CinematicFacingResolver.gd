extends RefCounted
## Resolves the effect camera's base YAW so the focused unit isn't hidden.
##
## Godot heir to the ROM's `calc_facing_angles` (0x801aac28). See
## docs/context/15-effect-orchestration.md ([Cinematic facing resolution]) and ADR-0039. Layered rule:
##
##   1. Candidates: the 4 fixed yaws — the snapped base yaw plus +90 / -90 / 180
##      (PSX 0x400 = 90 deg). Pitch and zoom are NOT touched (the effect owns
##      them); only yaw is chosen.
##   2. Terrain-visibility GATE (the one behaviour the ROM models): a yaw is
##      eligible only if the focused unit's silhouette is not hidden behind map
##      geometry from that angle.
##   3. Foreground-composition TIE-BREAK (our addition): among eligible yaws,
##      fewest other UNITS occluding the silhouette (mask 4), then the yaw that
##      puts the unit most in the foreground relative to its neighbours, then
##      the ROM's minimal-rotation-from-current order (encoded by candidate
##      order + strict-improvement replacement).
##   4. All-blocked fallback (ROM-faithful): if NO yaw clears the terrain gate,
##      keep the current/base yaw.
##
## TERRAIN gate uses an ANALYTIC height march, NOT a physics raycast: the map's
## only terrain colliders are the flat tile-top convex quads (`DynamicTerrain‌-
## Builder._create_collision_shape`); the vertical cliff faces that actually
## block a low-angle view have NO collider, so a camera ray threads between the
## flat quads and never reports occlusion. Instead we step along the sightline
## and compare each column's tile-top world-Y against the ray height — the same
## thing the ROM precomputed into per-tile bits. UNIT occlusion (the tie-break)
## DOES use physics rays: units are Area3D boxes with real volume.
##
## Camera is orthographic, so occlusion depends only on the view DIRECTION — we
## probe from the subject backward along the camera-forward axis.
## Vault: [[Embedded MIPS Effect Code]]

## ADR-0212 dec. 1 — `addons/exmateria_platform` publishes one global,
## `ExMateriaPlatform`; aliasing a member back keeps every use site below
## spelled the way it was (ADR-0211 dec. 4). The PSX trio arrived at
## extraction #7 (#1220) and lost its three bare `class_name`s on the way.
const PsxChirality = ExMateriaPlatform.PsxChirality


# This file used to hold a local `PSXConvert` constant that preloaded the old
# `src/effects/PSXCameraConvert.gd` address — a SECOND spelling for the same script, by
# path. The sign axis now lives at `ExMateriaPlatform.PsxChirality` and is aliased above
# (#1220); the local alias went with it, because an addon member reachable two ways is how
# a path reference into an addon survives a rename meant to be total (ADR-0212 dec. 4).
#
# 🔴 THE FIRST DRAFT OF THIS PARAGRAPH QUOTED THE DELETED LINE VERBATIM, AND ARM 6 COUNTED
# IT. `membership_arms.py`'s shape scan reads a preload-of-a-path wherever the form appears,
# comment or not, so arm 6 went 2 -> 3 and the third line was this note describing its own
# removal. The arm is right to be literal — a commented-out reach is still a reader's map to
# a dead address — so this is prose, and arm 6 reads 2 again: the two `TRAP1` content-pack
# lines in `TrapEffect.gd`, which ADR-0142 makes permanent rather than payable.

const QUARTER_TURN := 1024.0   # PSX 0x400 = 90 deg
const HALF_TURN := 2048.0      # 180 deg

# Collision layers (godot-learning/CLAUDE.md): tiles = 2, units = 4.
const MASK_UNITS := 4

# Silhouette sample heights (Godot units above the unit origin / feet). The
# SelectionArea hitbox spans y in [0,1]; sprites read taller, so we probe up to
# ~head height. A yaw clears the gate if at least GATE_VISIBLE_FRACTION of these
# reach the camera without terrain rising into the sightline.
const SILHOUETTE_HEIGHTS := [0.1, 0.5, 1.0, 1.5]
const GATE_VISIBLE_FRACTION := 0.5

# Terrain march (Godot units). Step < 1 tile so a one-tile-wide cliff column is
# never skipped; MAX_DIST bounds the walk; once the rising ray clears MAX_RELIEF
# above the start it can't be occluded by any FFT-height terrain, so we stop.
const MARCH_STEP := 0.5
const MARCH_MAX_DIST := 48.0
const MARCH_MAX_RELIEF := 16.0
const TERRAIN_EPS := 0.05      # ignore same-height self/neighbour tiles

# How far back along the view ray to probe for unit occluders (Godot units).
const PROBE_DISTANCE := 80.0
# Radius (Godot units, ~tiles) for the "adjacent units" foreground query.
const NEIGHBOUR_RADIUS := 2.5
const NEIGHBOUR_MAX := 16

var _world: Node3D   # in-tree Node3D, for get_world_3d().direct_space_state (units)
## Host query (grid_x: int, grid_z: int) -> {exists: bool, world_y: float}.
## Coordinates are floored world X/Z, including negatives. Sample the column's
## ground, not its highest level; world_y is the rendered tile-top world height.
## Missing columns return {"exists": false, "world_y": 0.0}; zero is NOT absence.
## An invalid Callable means no terrain provider: keep the base yaw (as for the
## former null map). Unit physics still uses layer 4 Area3Ds and SelectionArea.
var _terrain_column: Callable


func _init(world_node: Node3D, terrain_column: Callable) -> void:
	_world = world_node
	_terrain_column = terrain_column


## Return the chosen base yaw in PSX units (4096 = 360). `base_yaw_12bit` is the
## snapped "where it would normally go" yaw; `pitch_12bit` is the authored pitch.
## The returned yaw is base + {0, +90, -90, +180} (never wrapped), so the
## downstream lerp from the current yaw takes the minimal-rotation path.
func resolve_facing_yaw(base_yaw_12bit: float, pitch_12bit: float, focused_unit) -> float:
	if not is_instance_valid(focused_unit) or not _terrain_column.is_valid():
		return base_yaw_12bit

	var subject: Vector3 = focused_unit.global_position
	var exclude := _unit_exclude(focused_unit)
	var space := _unit_space()
	# Neighbour positions are yaw-independent — gather once, score per candidate.
	var neighbours := _gather_neighbours(space, subject, exclude)

	# ROM preference order: current, +90, -90, 180.
	var candidates := [
		base_yaw_12bit,
		base_yaw_12bit + QUARTER_TURN,
		base_yaw_12bit - QUARTER_TURN,
		base_yaw_12bit + HALF_TURN,
	]

	var found := false
	var best_yaw := base_yaw_12bit
	var best_occluders := 0x7fffffff
	var best_in_front := 0x7fffffff

	for yaw in candidates:
		# 2. Terrain gate (analytic).
		if terrain_visible_fraction(subject, pitch_12bit, yaw) < GATE_VISIBLE_FRACTION:
			continue
		found = true

		var forward := _view_forward(pitch_12bit, yaw)   # eye -> subject
		var to_cam := -forward                          # subject -> eye

		# 3a. Fewest occluding units (physics — units have volume).
		var occ := _occluder_count(space, subject, to_cam, exclude)
		# 3b. Foreground: neighbours nearer the camera than the subject.
		var in_front := 0
		for n in neighbours:
			if (n - subject).dot(forward) < 0.0:
				in_front += 1

		# Strict improvement only -> an equally-good later (less preferred)
		# candidate never displaces an earlier one. That encodes tie-break 3c.
		if occ < best_occluders or (occ == best_occluders and in_front < best_in_front):
			best_occluders = occ
			best_in_front = in_front
			best_yaw = yaw

	if not found:
		return base_yaw_12bit   # ROM all-blocked branch: keep current yaw.
	return best_yaw


## Fraction of silhouette samples with a clear line to the camera, by analytic
## terrain height (no physics). Public so tests can exercise the gate directly.
func terrain_visible_fraction(subject: Vector3, pitch_12bit: float, yaw_12bit: float) -> float:
	if not _terrain_column.is_valid():
		return 1.0
	var to_cam := -_view_forward(pitch_12bit, yaw_12bit)
	var visible := 0
	for h in SILHOUETTE_HEIGHTS:
		if _sample_visible(subject + Vector3(0, h, 0), to_cam):
			visible += 1
	return float(visible) / float(SILHOUETTE_HEIGHTS.size())


# --- helpers -----------------------------------------------------------------

func _view_forward(pitch_12bit: float, yaw_12bit: float) -> Vector3:
	"""Godot world direction the camera looks (eye -> subject) for a pose."""
	var rot := PsxChirality.psx_angles_to_godot_rotation(pitch_12bit, yaw_12bit, 0.0)
	var basis := Basis.from_euler(rot)
	return (basis * Vector3(0, 0, -1)).normalized()


func _sample_visible(origin: Vector3, to_cam: Vector3) -> bool:
	"""March the sightline from a silhouette point toward the camera; occluded
	the moment a tile-top rises above the ray's height at that column."""
	var t := MARCH_STEP
	while t <= MARCH_MAX_DIST:
		var p := origin + to_cam * t
		var gx := int(floor(p.x))
		var gz := int(floor(p.z))
		var column: Dictionary = _terrain_column.call(gx, gz)
		if column["exists"] and float(column["world_y"]) > p.y + TERRAIN_EPS:
			return false
		if p.y > origin.y + MARCH_MAX_RELIEF:
			break   # ray has climbed above any terrain — rest of the line is clear
		t += MARCH_STEP
	return true


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
		var origin := subject + Vector3(0, h, 0)
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
