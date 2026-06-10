class_name SharedLfoStepCalc
## Pure-math helpers extracted from dispatcher.gd (refactor Pass 2).
##
## FFT analog: pitch_lfo_step_calc @ 0x80016BF8
## Shared by 0xD8 / 0xD9 / 0xE4 / 0xE5 / 0xEC / 0xED / 0xF1 / 0xF2 plus
## _advance_lfo's per-tick output stage.
##
## No side effects, no state, no probes — pure functions only. Safe to
## call from any layer without breaking preload cycles.


static func step_calc(a0: int, a1: int, a2: int) -> int:
	## FFT pitch_lfo_step_calc at PC 0x80016BF8. Used by every LFO-arm
	## opcode to derive the per-tick step source from the operand
	## triple (param[1]<<24 [possibly negated], param[0], param[2]&0xF).
	##
	##   if a0 == 0: return 0
	##   a1 = sign-extend low16 of a1
	##   if a1 == 0: return 0
	##   v1 = sign-extend low16 of a2
	##   if v1 < 2: return a0
	##   if v1 < 4 (= 2 or 3): return a0 / a1
	##   if v1 == 4: return a0 if a1 == 1 else a0 / (a1 - 1)
	##   else (v1 > 4): return a0
	##
	## For cure_4's 0xE5 (params 4, 42, 3): wf_idx 3 → a0 / a1 =
	## -(42 << 24) / 4 = -176160768, >>16 = -2688 → chan_88 stride
	## -2688/tick (matches PCSX voice 19 descent before the triangle
	## reversal).
	## For cure_4's 0xED (params 20, 110, 19): wf_idx 3 → a0 / a1 =
	## (110 << 24) / 20 = 92274688, >>16 = +1408 → chan_8a stride
	## +1408/tick (matches PCSX voice 21 exactly).
	if a0 == 0:
		return 0
	var a1_s16: int = a1 & 0xFFFF
	if a1_s16 >= 0x8000: a1_s16 -= 0x10000
	if a1_s16 == 0:
		return 0
	var v1_s16: int = a2 & 0xFFFF
	if v1_s16 >= 0x8000: v1_s16 -= 0x10000
	if v1_s16 < 2:
		return a0
	if v1_s16 < 4:
		return div_s32_trunc(a0, a1_s16)
	if v1_s16 == 4:
		if a1_s16 == 1:
			return a0
		return div_s32_trunc(a0, a1_s16 - 1)
	return a0


static func div_s32_trunc(num: int, den: int) -> int:
	## Mirror MIPS signed div (truncate-toward-zero, not GDScript's
	## floor-division). MIPS `div` rounds the quotient toward zero;
	## GDScript's `/` rounds toward negative infinity for negative
	## numerators. Match MIPS so -704643072 / 4 = -176160768
	## (not -176160768 which happens to be the same here, but for
	## non-divisible cases the two diverge).
	if den == 0:
		return 0
	var q: int = int(num / den)
	if (q * den) != num and ((num < 0) != (den < 0)):
		q += 1
	return q


static func sra_s32(value: int, shift: int) -> int:
	## Sign-preserving arithmetic right shift by `shift` bits within
	## a 32-bit signed range. GDScript ints are 64-bit, but the FFT
	## values we care about live in s32; coerce into s32 first so
	## `>> 16` produces the same result as MIPS `sra`.
	var v: int = value & 0xFFFFFFFF
	if v >= 0x80000000:
		v -= 0x100000000
	return v >> shift
