class_name VfxCurve
extends RefCounted
## Curve sampler — thin wrapper around VisualEffectData.curves
## 160 samples, 0.0-1.0 normalized

var samples: PackedFloat64Array = PackedFloat64Array()
var index: int = 0


func _init(curve_samples: PackedFloat64Array = PackedFloat64Array(), curve_index: int = 0) -> void:
	samples = curve_samples
	index = curve_index


static func from_visual_effect_data(vfx_data: VisualEffectData, curve_index: int) -> VfxCurve:
	if curve_index < 0 or curve_index >= vfx_data.curves.size():
		return null
	return VfxCurve.new(vfx_data.curves[curve_index], curve_index)


func sample_by_frame(frame: int) -> float:
	if samples.is_empty():
		return 0.0
	var idx: int = frame % samples.size()
	return samples[idx]


func sample_normalized(t: float) -> float:
	if samples.is_empty():
		return 0.0
	var idx: int = int(t * (samples.size() - 1))
	idx = clampi(idx, 0, samples.size() - 1)
	return samples[idx]
