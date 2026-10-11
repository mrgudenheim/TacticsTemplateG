extends RefCounted
## Factory for creating callback instances by ID.
## Vault: [[Embedded MIPS Effect Code]]

const EffectCallback = preload("res://addons/exmateria_effects/callbacks/EffectCallback.gd")

const E071CallbackClass = preload("res://addons/exmateria_effects/callbacks/E071Callback.gd")
const ScreenGridCallbackClass = preload("res://addons/exmateria_effects/callbacks/ScreenGridCallback.gd")
const SpiralMeshCallbackClass = preload("res://addons/exmateria_effects/callbacks/SpiralMeshCallback.gd")
const TrailProjectileCallbackClass = preload("res://addons/exmateria_effects/callbacks/TrailProjectileCallback.gd")
const TubeMeshCallbackClass = preload("res://addons/exmateria_effects/callbacks/TubeMeshCallback.gd")
const RadialRingCallbackClass = preload("res://addons/exmateria_effects/callbacks/RadialRingCallback.gd")
const RotatingTubeCallbackClass = preload("res://addons/exmateria_effects/callbacks/RotatingTubeCallback.gd")
const WarpedGridCallbackClass = preload("res://addons/exmateria_effects/callbacks/WarpedGridCallback.gd")
const WorldTubeCallbackClass = preload("res://addons/exmateria_effects/callbacks/WorldTubeCallback.gd")


static func create(cb_id: int) -> EffectCallback:
	"""Create a callback instance for the given callback ID.
	Returns null for unimplemented callbacks."""
	match cb_id:
		3, 4, 5, 6, 7, 8, 30, 39, 56:
			return WorldTubeCallbackClass.new()
		9, 15, 16, 20, 57:
			return ScreenGridCallbackClass.new()
		17, 32:
			return SpiralMeshCallbackClass.new()
		18:
			return WorldTubeCallbackClass.new()
		26, 27:
			return E071CallbackClass.new()
		91:
			return TrailProjectileCallbackClass.new()
		92:
			return TubeMeshCallbackClass.new()
		10, 12:
			return RadialRingCallbackClass.new()
		14, 19:
			return RotatingTubeCallbackClass.new()
		11, 13, 36:
			return WarpedGridCallbackClass.new()
		_:
			push_warning("CallbackRegistry: Unknown callback ID %d" % cb_id)
			return null
