// NDC depth -> the value `DEPTH` expects. One place, for every shader that writes DEPTH.
//
// Under Compatibility, NDC z spans [-1, 1] with near POSITIVE, while a fragment's DEPTH is
// a WINDOW depth in [0, 1] — so writing raw NDC loses half the range and clamps everything
// past the mid-plane. Forward+ already hands over [0, 1], hence the guard.
//
// A RANGE conversion, not a reversed-Z inversion: near stays high. Apply AFTER any depth
// bias. Absolute depth-buffer slots are already [0, 1] and must NOT pass through here.

float psx_window_depth(float ndc_z) {
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	return ndc_z * 0.5 + 0.5;
#else
	return ndc_z;
#endif
}
