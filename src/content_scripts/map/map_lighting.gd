class_name MapLighting
extends Resource
## The three directional lights + ambient colour FFT stores in every map's mesh resource,
## at pointer 0x64 — whose last six bytes already feed the background gradient.
##
## Three traps here give a plausible-but-wrong picture rather than an error: the colours
## are a 3x3 MATRIX not three triples, a light colour is a GAIN that exceeds 1.0, and the
## directions stay in the mesh's own ROM space. See `from_lighting_bytes` and `colors`.
##
## No lighting is not an error: see `unlit()`.

## Start of the lighting block to the end of the ambient colour; the six
## background-gradient bytes after it are `FftMapData`'s.
const LIGHTING_BYTES: int = 18 + 18 + 3

const NUM_LIGHTS: int = 3

## Gains in 0-1 texture-multiply space (the ROM's `int16 / 8` over 255), NOT a displayable
## colour — components above 1.0 are the point, and MAP062's key light is (604, 528, 476).
## The PSX clamps only the final pixel, so `map_shader.gdshader` clamps at the end.
## Always `NUM_LIGHTS` long.
@export var light_gains: PackedVector3Array = []

## Unit direction TOWARDS each light, in the mesh's own space — the one
## `FftMapData.get_normals` leaves its normals in. Always `NUM_LIGHTS` long.
@export var light_directions: PackedVector3Array = []

## Ambient term, 0-1, added to the diffuse sum before the texture multiply with NO scale
## factor — a `x 1.5` fudge only compensates for clamping the gains to white.
@export var ambient: Vector3 = Vector3.ZERO


## Decode the block `FftMapData` slices at the lighting pointer. `bytes` must be at least
## `LIGHTING_BYTES` long. Returns `unlit()` for a map with no lighting block.
##
## Do not negate any component of the light direction. `FftMapData.get_normals` does not
## negate either, and shading only needs the two to agree; negating one side flips the
## lighting in Y and leaves floors on ambient alone.
static func from_lighting_bytes(bytes: PackedByteArray) -> MapLighting:
	if bytes.size() < LIGHTING_BYTES:
		push_warning("MapLighting: lighting block is %d bytes, need %d" % [bytes.size(), LIGHTING_BYTES])
		return unlit()

	var new_lighting: MapLighting = MapLighting.new()
	new_lighting.light_gains.resize(NUM_LIGHTS)
	new_lighting.light_directions.resize(NUM_LIGHTS)

	for light_index: int in NUM_LIGHTS:
		# A 3x3 matrix: red_i at 0 + 2i, green_i at 6 + 2i, blue_i at 12 + 2i — NOT three
		# consecutive triples. Floor at 0, never cap.
		new_lighting.light_gains[light_index] = Vector3(
			maxf(0.0, float(bytes.decode_s16(light_index * 2)) / 8.0),
			maxf(0.0, float(bytes.decode_s16(6 + light_index * 2)) / 8.0),
			maxf(0.0, float(bytes.decode_s16(12 + light_index * 2)) / 8.0),
		) / 255.0

		var direction_offset: int = 18 + light_index * 6
		var direction: Vector3 = Vector3(
			float(bytes.decode_s16(direction_offset)),
			float(bytes.decode_s16(direction_offset + 2)),
			float(bytes.decode_s16(direction_offset + 4)),
		)
		new_lighting.light_directions[light_index] = direction.normalized()

	new_lighting.ambient = Vector3(
		float(bytes.decode_u8(36)),
		float(bytes.decode_u8(37)),
		float(bytes.decode_u8(38)),
	) / 255.0

	return new_lighting


## Identity lighting: ambient 1.0 and no directional light, so
## `texture * (ambient + diffuse)` is `texture * 1.0`.
static func unlit() -> MapLighting:
	var new_lighting: MapLighting = MapLighting.new()
	new_lighting.ambient = Vector3.ONE
	new_lighting.light_gains.resize(NUM_LIGHTS)
	new_lighting.light_directions.resize(NUM_LIGHTS)
	for light_index: int in NUM_LIGHTS:
		new_lighting.light_directions[light_index] = Vector3.UP
	return new_lighting


## True when at least one light has a non-zero gain; all three at zero is ambient only.
func has_directional_light() -> bool:
	for gain: Vector3 in light_gains:
		if gain.length_squared() > 0.0:
			return true
	return false


## Push the uniforms `map_shader.gdshader` reads. Godot drops unknown parameters, so on
## any other material this is harmless and does nothing.
func apply_to_material(material: ShaderMaterial) -> void:
	if material == null:
		return
	var gains: PackedVector3Array = light_gains.duplicate()
	var directions: PackedVector3Array = light_directions.duplicate()
	gains.resize(NUM_LIGHTS)
	directions.resize(NUM_LIGHTS)
	material.set_shader_parameter("light_gains", gains)
	material.set_shader_parameter("light_directions", directions)
	material.set_shader_parameter("ambient_light", ambient)
	material.set_shader_parameter("lighting_enabled", true)
	# Set explicitly: `get_shader_parameter` answers null for a uniform the MATERIAL never
	# stored, leaving "is this map on the faithful path?" unanswerable.
	material.set_shader_parameter("lighting_per_vertex", true)
