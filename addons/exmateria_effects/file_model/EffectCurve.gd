extends RefCounted
## FFT curve data (160 samples, 0-1 normalized)
## Vault: [[Particle Curve Indices]]

const _Self = preload("res://addons/exmateria_effects/file_model/EffectCurve.gd")

var samples: Array[float] = []
var index: int = 0


static func from_array(data: Array, idx: int = 0) -> _Self:
	var curve = _Self.new()
	curve.index = idx
	curve.samples.resize(data.size())
	for i in range(data.size()):
		curve.samples[i] = float(data[i])
	return curve


func sample_by_frame(frame: int) -> float:
	if samples.is_empty():
		return 0.0
	var idx: int = frame % samples.size()
	return samples[idx]


static func sample_rgb(cr: _Self, cg: _Self, cb: _Self, frame: int) -> Color:
	"""Per-frame colour resolve shared by the particle renderer and the
	Effect Studio Colour ribbon, so the preview can't drift from the render path.
	Alpha is 0.0: the renderer sets it per-frame from semi_trans_on; the ribbon ignores alpha."""
	return Color(cr.sample_by_frame(frame), cg.sample_by_frame(frame), cb.sample_by_frame(frame), 0.0)
