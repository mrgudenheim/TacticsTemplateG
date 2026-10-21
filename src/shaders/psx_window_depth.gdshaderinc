// NDC depth -> the window depth `DEPTH` expects, for every shader that writes DEPTH.
//
// Under Compatibility NDC z spans [-1, 1], so writing it raw clamps everything past the
// mid-plane; Forward+ already hands over [0, 1]. A range conversion, not a reversed-Z
// inversion: near stays high. Apply after any depth bias, never to values already in [0, 1].

float psx_window_depth(float ndc_z) {
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	return ndc_z * 0.5 + 0.5;
#else
	return ndc_z;
#endif
}
