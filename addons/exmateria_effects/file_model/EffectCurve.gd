extends RefCounted
## FFT curve data (160 samples, 0-1 normalized)
## Vault: [[Particle Curve Indices]]

const _Self = preload("res://addons/exmateria_effects/file_model/EffectCurve.gd")

var samples: Array[float] = []
var index: int = 0


static func from_array(data: Array, idx: int = 0) -> _Self:
	"""Create curve from array of 0-1 float values"""
	var curve = _Self.new()
	curve.index = idx
	curve.samples.resize(data.size())
	for i in range(data.size()):
		curve.samples[i] = float(data[i])
	return curve


func sample_by_frame(frame: int) -> float:
	"""Sample curve at frame (wraps at 160)"""
	if samples.is_empty():
		return 0.0
	var idx: int = frame % samples.size()
	return samples[idx]


static func sample_rgb(cr: _Self, cg: _Self, cb: _Self, frame: int) -> Color:
	"""The SINGLE per-frame colour resolve. The particle renderer paints with this
	(EffectParticleRenderer._compute_color_modulate) and the Effect Studio Colour ribbon
	reads with it, so the read-only preview can never drift from the render path. Alpha is
	0.0 — the renderer sets it per-frame from the semi_trans_on flag; the ribbon ignores
	alpha and draws opaque."""
	return Color(cr.sample_by_frame(frame), cg.sample_by_frame(frame), cb.sample_by_frame(frame), 0.0)
