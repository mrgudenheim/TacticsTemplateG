extends RefCounted
## Factory for creating callback instances by ID.
## Vault: [[Embedded MIPS Effect Code]]

const EffectCallback = preload("res://addons/exmateria_effects/callbacks/EffectCallback.gd")

const ZodiacGridCallbackClass = preload("res://addons/exmateria_effects/callbacks/ZodiacGridCallback.gd")
const ZodiacCylinderCallbackClass = preload("res://addons/exmateria_effects/callbacks/ZodiacCylinderCallback.gd")
const FairyTubeCallbackClass = preload("res://addons/exmateria_effects/callbacks/FairyTubeCallback.gd")
const FairyRingCallbackClass = preload("res://addons/exmateria_effects/callbacks/FairyRingCallback.gd")
const FairyProjectileCallbackClass = preload("res://addons/exmateria_effects/callbacks/FairyProjectileCallback.gd")
const E071CallbackClass = preload("res://addons/exmateria_effects/callbacks/E071Callback.gd")
const ScreenGridCallbackClass = preload("res://addons/exmateria_effects/callbacks/ScreenGridCallback.gd")
const SpiralMeshCallbackClass = preload("res://addons/exmateria_effects/callbacks/SpiralMeshCallback.gd")
const TrailProjectileCallbackClass = preload("res://addons/exmateria_effects/callbacks/TrailProjectileCallback.gd")
const TubeMeshCallbackClass = preload("res://addons/exmateria_effects/callbacks/TubeMeshCallback.gd")
const RadialRingCallbackClass = preload("res://addons/exmateria_effects/callbacks/RadialRingCallback.gd")
const RotatingTubeCallbackClass = preload("res://addons/exmateria_effects/callbacks/RotatingTubeCallback.gd")
const WarpedGridCallbackClass = preload("res://addons/exmateria_effects/callbacks/WarpedGridCallback.gd")
const WorldTubeCallbackClass = preload("res://addons/exmateria_effects/callbacks/WorldTubeCallback.gd")
const TrapChargeLineCallbackClass = preload("res://addons/exmateria_effects/callbacks/TrapChargeLineCallback.gd")
const TrapOrbitalCallbackClass = preload("res://addons/exmateria_effects/callbacks/TrapOrbitalCallback.gd")

## Godot-only callback ids for TRAP handlers lifted into E### form (ADR-0369). ROM ids
## stop at 197 (see create()), so 1000 + handler function id cannot collide with one.
const TRAP_CALLBACK_BASE := 1000
const CB_TRAP_CHARGE_LINES := TRAP_CALLBACK_BASE + 4
const CB_TRAP_ORBITAL := TRAP_CALLBACK_BASE + 22


static func create(cb_id: int) -> EffectCallback:
	"""Create a callback instance for the given callback ID.
	Returns null for unimplemented callbacks."""
	# 4/5/6/7 stay mapped even though `MIPS_CALLBACK_SYSTEM.md` and the vault say a value
	# of the load base 0x801C2500 means "no callback": the live-PCSX-read table
	# @0x801B50D0 (~198 entries) shows E005/E006/E007/E015/E035/E041/E047/E067 all
	# compile a real function at file offset 0. Ids are also effect-private — over
	# assets/effects every id 2..197 is claimed by exactly one effect (only 88 shared:
	# E259 + E457), so an id IS an (effect, offset) pair.
	#
	# 🔴 A MAPPED ID IS NOT A CORRECT ID, and cb2/cb3 are the proof. Both belong to
	# E004 "Cure 4"; the routines in E004.BIN say cb2 has WorldTube's shape and cb3 has
	# RadialRing's, which is the opposite of what this table used to say — cb3 was mapped
	# to WorldTube and cb2 was not mapped at all, so two of E004's three callback-owned
	# emitters drew nothing and the third drew the wrong shape off the wrong field. What
	# decides it is read off the instruction stream, not off a class name or a
	# fingerprint:
	#
	#            row index      stride         last column      -> shape
	#   cb2   lh  emitter+0x3C  x9 = 0x24      base+0x20 (8)       9 wide, WorldTube
	#   cb3   lh  emitter+0x4E  x6 = 0x18      base+0x14 (5)       6 wide, RadialRing
	#
	# The two routines read DISJOINT row fields, and the check is exact. Off the emitter
	# pointer (cb3's is t2 from `lw t2,0x18(sp)`; cb2's is s3), cb3 reads 19 fields
	# including +0x3A and +0x3E but SKIPS +0x3C, while cb2 reads +0x3C and never reads
	# +0x4E at all. So WorldTubeCallback — which reads its row at +0x3C
	# (WorldTubeCallback.gd:86) and is 9/3 sections wide — could not have been right for
	# cb3 on either axis.
	#
	# ⚠️ Say "off the emitter pointer", not "nowhere in the routine". cb3 DOES contain a
	# +0x3C load, `lw v0,0x3c(s6)` at byte 0x0150 — but s6 is the callback's own scratch
	# struct, which the routine writes at 0x00/0x04/0x4C/0x5C and into which it copies the
	# emitter's +0x4E. A plain scan for the immediate 0x3C hits it, so the loose phrasing
	# reads as false to the next person who checks.
	#
	# Driven over E004's emitter idx2 in one process, varying only the class: WorldTube
	# lands on row 0 across 25 radii with a non-monotone profile, while RadialRing lands
	# on row 1 across exactly 6 and reproduces the ROM's [4096, 3277, 2458, 1638, 819, 0]
	# to the unorm8 truncation floor.
	#
	# ⚠️ Sharing a SEQUENCE does not pick the class either. Taxonomy §6 is titled "one
	# routine wears four class names", but what it measures is a sequence: ccc8509bbb1c
	# is claimed by WorldTube, RotatingTube, SpiralMesh and WarpedGrid at once. cb2 sits
	# in it, and its routine differs from E015 cb7's (WorldTube) by 3 words in 1342, all
	# three the table pointer — but also from E041 cb14's (RotatingTube) and E077 cb36's
	# (WarpedGrid) by the same kind of nothing. The row FIELD and the table WIDTH are
	# what separate the classes inside one sequence.
	match cb_id:
		40, 42:
			# E080 live linked packets: open 9x9 warped grid / fixed 5x5 grid.
			return ZodiacGridCallbackClass.new()
		41:
			# E080 live scratch/packets: 3 rings, two 32-face bands, not 9x8.
			return ZodiacCylinderCallbackClass.new()
		35:
			# 0x801C2500, 80 live GT4s; integer screen-space rings, not a tube.
			return FairyRingCallbackClass.new()
		36:
			# WorldTube subclass preserves integer bank timing and cursor anchoring.
			return FairyTubeCallbackClass.new()
		37:
			# 0x801C5174 emits children from four projectiles; no GPU mesh.
			return FairyProjectileCallbackClass.new()
		# cb55 (E174 Dark Holy, slot 0) is DERIVED here, not chosen. Its routine
		# 8f955bfedfe3 is BYTE-IDENTICAL to E015 cb7, which routes to this class; its
		# table is 6x9 against SECTIONS_BALL = 9; its row field is emitter+0x3C, which
		# is what this class reads; and `shape_for("E174", 55)` returns BALL because
		# CYLINDER_SHAPE_EFFECTS lists only cb56 for E174. Five things agree.
		#
		# 🔴 IT WAS MISSING, AND THE SYMPTOM WAS "DARK HOLY'S BEAM DOES NOT PLAY".
		# create(55) returned null, so CallbackManager._slots[0] never populated and no
		# mesh was ever built for emitter idx4 — while cb56 and cb57 were mapped and
		# rendered fine. Dispatch was never at fault: the spawn request arrived,
		# `action_flags & 7` was 1, and `invoke(0, 4, ...)` ran and found an empty slot.
		# 29 and 38 are E073/E079's closed 9-ring x 8-side tube, measured on
		# leviathan.sstate and cyclops.sstate: 64 quads / 72 verts / degrees
		# {2:16, 4:56} per instance, no degree-1 vertex. SECTIONS_BALL 9 x
		# SIDES_BALL 8 is exactly that, so they belong here.
		# 🔴 30 and 39 LEFT this group — see the WarpedGrid case below.
		# cb32 (E074 Salamander) is DERIVED here, one step removed from a ROM referee.
		# Its routine differs from E073 cb29's — already in this group — by 20 words in
		# 1342: 17 `j` targets offset by exactly the load delta plus the 3 table-pointer
		# words, ZERO structural and ZERO behavioural immediates. cb29 is BYTE-IDENTICAL
		# to E079 cb38, and both were measured on the ROM as a closed 9x8 tube (64 quads,
		# 72 verts, no degree-1). So the shape reaches cb32 through a measurement rather
		# than through a family, and it joins the siblings it is byte-equivalent to.
		#
		# ⚠️ A SEQUENCE MATCH ALONE WOULD NOT HAVE BEEN ENOUGH, and the near-miss belongs
		# here: comparing cb32's loop-bound and shift immediates against cb29's matches
		# exactly, with a negative control (E015 cb8, the cylinder) that differs — but ALL
		# 31 members of ccc8509bbb1c share ONE signature, so that test only restates
		# sequence membership. What carries it is the UNMASKED word diff, because §8's
		# warning is exactly that the mask hides behavioural immediates.
		# E069 Golem cb22 is exact-byte routine 47b0cd6aae58, the same routine as
		# mapped WorldTube ids 4/5/6. It joins that default ball/tube route rather
		# than the cb14 Reflect rotating-tube shape.
		# E076 Silf cb34: exact-byte routine 47b0cd6aae58 (same as cb4/5/6).
		# Live silf.sstate, 0x801C2500 slot1/emitter9 frame10: 64 GT4s,
		# 72 vertices, incidence {2:16,4:56}; closed 9x8 tube, not a sheet.
		# This restores dispatch; the shared material still does not honor ABR3.
		2, 4, 5, 6, 7, 8, 22, 29, 32, 34, 38, 55, 56:
			return WorldTubeCallbackClass.new()
		# 26 is E071's, and it is NOT an E071Callback dome. Its routine is
		# byte-identical to E015 cb9 apart from one immediate — the table pointer —
		# and the ROM draws it on bahamut.sstate as a 4x4 axis-aligned screen grid of
		# 64x64 quads, 16 prims double-buffered, against cb27's 128-quad projected
		# mesh in the neighbouring bank. Its table is 5-wide, which is GRID_ROWS + 1
		# and fails E071Callback's ROWS = 9 gate.
		# E070 Carbuncle cb25 is the 5-wide screen-grid routine: alloc 0x6e4,
		# row field emitter+0x4E, table stride 0x14 at DAT_801c6614, matching
		# this class's 4x4 grid/5-edge brightness model.
		# E072 Odin cb28 is byte-identical to E047 cb15: alloc 0x6e4, 4x4
		# screen grid, row from emitter+0x4E, and a 5-wide brightness table at
		# file+0x774 bounded by the header. The other exact-byte siblings ride
		# the same routine/table shape.
		9, 15, 16, 20, 25, 26, 28, 31, 57, 60, 68, 110, 149:
			return ScreenGridCallbackClass.new()
		17, 24:
			# E070 Carbuncle cb24 joins cb17's 6-ring spiral/strip shape by routine
			# evidence, not sequence alone: alloc 0x20fc, row field emitter+0x4E,
			# and table stride 0x18 (six int32 edge values) at DAT_801c656c.
			#
			# cb17 ALONE, and the purity is the point. cb32 used to sit here: it is a
			# 5368-byte ccc8509bbb1c routine while cb17 is 6012-byte 3f900aae701c — a
			# different length AND a different sequence. This class's constants
			# (RINGS = 6, VERTS_PER_RING = 5, param_4E) fit cb17's family exactly and
			# cb32's not at all, so cb32 was reading this class's constants instead of its
			# own routine's: a 9-wide table consumed 6 wide, indexed off emitter+0x4E where
			# the routine reads +0x3C. Measured before the move — it rendered BLACK.
			return SpiralMeshCallbackClass.new()
		18:
			return WorldTubeCallbackClass.new()
		# E074 Salamander cb33 allocates 0x341c: two 128-prim buffers, built as
		# 8 row-gaps × 16 columns from a 9×17 scratch grid. That is the dome
		# topology this class implements, not WorldTube's 64-prim 9×8 tube.
		27, 33:
			return E071CallbackClass.new()
		# E070 Carbuncle cb23 has the same trail-projectile instruction sequence
		# as cb91 and the same 8096-byte sub-projectile/trail routine shape.
		23, 91:
			return TrailProjectileCallbackClass.new()
		# E068 Titan cb21 is the same instruction sequence as E317 cb92 and exact-byte
		# identical to E341 cb95 (KnifeHand/DamageSplit), so the existing bicone mesh
		# callback is the measured analogue rather than a new class guess.
		21, 92:
			return TubeMeshCallbackClass.new()
		3, 10, 12:
			# cb3 joins cb10/cb12 because it is the same SEQUENCE as them — 3f900aae701c,
			# relocated, differing only in its table pointers — not because it looks like
			# a ring: 20 differing words against E033 cb10 over 1503, 17 of them `j`
			# targets offset by exactly the load delta and the other 3 the table pointer.
			# Zero structural differences, zero behavioural immediates.
			#
			# ⚠️ SEQUENCE, not ROUTINE, and the distinction is the one ROUTINE_TABLES is
			# built on. Taxonomy §8 keeps the two columns apart: `routine` means same code
			# AND same constants, `sequence` only same code. cb3 is b9c4e75c7c7e
			# (shared_by 1); cb10/cb12 are a5f18ad31f80. Calling them one routine would
			# contradict `parse_effect_callbacks.py`, which keys on routine precisely
			# BECAUSE these three share a sequence and do not share a table address.
			return RadialRingCallbackClass.new()
		14, 19:
			return RotatingTubeCallbackClass.new()
		# 🔴 30 and 39 MOVED HERE FROM WorldTubeCallback. Their routine
		# 73a07ffee609 draws an OPEN 9x9 sheet, not a tube: 64 quads / 81 verts /
		# degrees {1:4, 2:28, 4:49} per instance — FOUR degree-1 corners — measured
		# on both leviathan.sstate and cyclops.sstate. GRID_SIZE 9 gives 8x8 = 64
		# quads and 9x9 = 81 vertices, exactly.
		# ⚠️ This also fixes a field bug WITHOUT a special case: the routine reads
		# its brightness row from emitter+0x4E, which is what this class already
		# reads (`param_4E`); WorldTubeCallback hardcodes +0x3C, which is correct
		# for the other eight ids it serves and wrong only for these two.
		# E077 CB36 is NOT this sheet: 0x801C4C5C reads emitter+0x3C;
		# age10/20/30 live banks have 64 GT4s / 72 vertices, closed 9x8.
		11, 13, 30, 39:
			return WarpedGridCallbackClass.new()
		CB_TRAP_CHARGE_LINES:
			return TrapChargeLineCallbackClass.new()
		CB_TRAP_ORBITAL:
			return TrapOrbitalCallbackClass.new()
		_:
			push_warning("CallbackRegistry: Unknown callback ID %d" % cb_id)
			return null
