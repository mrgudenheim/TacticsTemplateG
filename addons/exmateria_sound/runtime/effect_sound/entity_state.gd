class_name EffectEntityCatchupState
##
## Per-effect-entity catch-up sub-loop state. Mirrors FFT's slot+0x74/+0x78/
## +0x36/+0x3a fields used by the catch-up loop at LAB_80014ccc..LAB_80014df4.

# FFT PC 0x80014cc8 lui a0, 0x1 — per-sub-loop add committed at PC
# 0x80014cd8 (addu) + 0x80014ce8 (sw v1, 0x74(s0) in delay slot).
const ENTITY_QUANTUM: int = 0x10000

# FFT slot allocator FUN_800137d8 init values
# (PC 0x80013884..0x80013894 ori/sw/lui/sw/sh, plus PC 0x800137ec/0x80013814
#  for v1=1 → slot+0x32 pass / slot+0x36 subcounter).
const ENTITY_ACC_INIT: int = 0x10000        # slot+0x74
const ENTITY_BUDGET_INIT: int = 0x6600       # slot+0x78 (= 26112; effects)
const ENTITY_SUBCOUNTER_INIT: int = 1        # slot+0x36
const ENTITY_WRAP_RESET_DEFAULT: int = 48    # slot+0x3a (= 0x30 / slot+0x15;
                                             # slot+0x15 = 1 effect → 48,
                                             # slot+0x15 = 2 music → 24)

var entity_acc: int = ENTITY_ACC_INIT          # FFT slot+0x74 (s32 signed)
var entity_budget: int = ENTITY_BUDGET_INIT    # FFT slot+0x78 (s32; 0x6600 effect, 0x7700 music)
var entity_subcounter: int = ENTITY_SUBCOUNTER_INIT  # FFT slot+0x36 (u16, decrements per fire)
var entity_wrap_reset: int = ENTITY_WRAP_RESET_DEFAULT  # FFT slot+0x3a (u16)

# FFT slot+0x32 pass counter, slot+0x34 measure counter (advanced by the
# wraparound block at PC 0x80014cec..0x80014d20 when subcounter hits 0).
# Modeled here for completeness; not yet wired to probes.
var entity_pass: int = 1       # slot+0x32, init 1 at PC 0x8001380c
var entity_measure: int = 0    # slot+0x34, init 0 at PC 0x80013810

# FFT slot+0x10 gate halfword as captured from the savestate. Used by
# EffectPlaySound._promote_next_silent_entity to filter eligible candidates
# (FFT's stride-0x160 walk at FUN_80012D40 checks `*puVar3 & 1` — a
# non-zero gate means the entity slot is in use and can serve as the
# allocator target). channel_count > 2 entities (active) and channel_count
# <= 2 entities (silent drivers) both carry a non-zero gate at savestate
# capture time. Stored unsigned (u16); 0 here means "uninitialized" or
# "skip during promotion".
var entity_gate: int = 0


# Pass 8 phase 5 — backref to the owning EffectPlaySound. Runtime's
# _run_sfx_entity_iter reaches through this to call into the SFX
# pipeline (cadence_body fan-out + flush_kon_only_for_slot) without
# restructuring the legacy ownership model. The per-IRQ iter body
# stays on EffectPlaySound today; this backref lets the unified driver
# call into it. Variant-typed to avoid the EffectPlaySound ↔
# EffectEntityCatchupState preload cycle.
var owning_play_sound = null

# Pass 8 phase 5 — set true when the SFX spell has ended. The
# canonical end-of-spell signal is EffectPlaySound._cure_slot_10
# flipping non-negative (the post-cadence_body andi 0x7fff at
# _run_entity_catchup's slot+0x10 transition). Mirrored here so
# Runtime._entity_done can read it without reaching through
# owning_play_sound.
var is_done: bool = false


## Apply one outer-call decrement (FFT PC 0x80014cb8 `subu v0, v0, a1`).
## Returns true if the sub-loop should fire (entity_acc < 0 post-decrement).
func apply_outer_decrement() -> bool:
	entity_acc -= entity_budget
	# Clamp to s32 signed range to mirror MIPS lw/sw on slot+0x74.
	entity_acc = _to_s32(entity_acc)
	return entity_acc < 0


## Apply one sub-loop iter (FFT PC 0x80014cd8/ce8 `addu v1,v1,a0; sw v1,0x74(s0)`
## plus the subcounter decrement at PC 0x80014cd4/cdc).
## Returns true if the sub-loop should fire AGAIN
## (entity_acc still < 0 after the +ENTITY_QUANTUM add).
func apply_sub_loop_fire() -> bool:
	# Subcounter decrement (PC 0x80014cd4 addiu v0, v0, -0x1; PC 0x80014cdc
	# sh v0, 0x36(s0) — 16-bit halfword store).
	entity_subcounter = (entity_subcounter - 1) & 0xFFFF
	# Per-fire add (PC 0x80014cd8 addu + PC 0x80014ce8 sw delay-slot).
	entity_acc = _to_s32(entity_acc + ENTITY_QUANTUM)
	# Subcounter wraparound block at PC 0x80014cec..0x80014d20 — fires when
	# the post-decrement subcounter is 0. Resets subcounter from
	# entity_wrap_reset, advances slot+0x34 (measure), conditionally bumps
	# slot+0x32 (pass) when measure exceeds slot+0x38.
	if entity_subcounter == 0:
		entity_subcounter = entity_wrap_reset
		entity_measure = (entity_measure + 1) & 0xFFFF
		# slot+0x38 (max measures) modeling deferred — observed captures
		# show subcounter cycling 1..wrap_reset..1 without the slot+0x38
		# dependency mattering.
	return entity_acc < 0


## Re-init at slot allocation (FFT FUN_800137d8). `wrap_reset` defaults to
## the effect-side 48 (= 0x30/1); pass 24 (= 0x30/2) for music.
func reset(wrap_reset: int = ENTITY_WRAP_RESET_DEFAULT) -> void:
	entity_acc = ENTITY_ACC_INIT
	entity_budget = ENTITY_BUDGET_INIT
	entity_subcounter = ENTITY_SUBCOUNTER_INIT
	entity_wrap_reset = wrap_reset
	entity_pass = 1
	entity_measure = 0


static func _to_s32(v: int) -> int:
	v = v & 0xFFFFFFFF
	if v >= 0x80000000:
		v -= 0x100000000
	return v
