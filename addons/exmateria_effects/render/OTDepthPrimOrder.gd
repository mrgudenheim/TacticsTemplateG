extends RefCounted
## Combat-compositor depth ordering (ADR-0009): farthest first, nearest last, so the
## transparent fold accumulates far -> near and the nearest prim wins where prims
## overlap. Runs are maximal adjacent same-DIRECTION spans: add {1,3} and sub {2}
## merge (per-prim level_scale at record [20] supplies each 1.0/0.25), mix {0}
## always solo. Byte-exact vs separate draws (proto_ordered_fold Q3, 200k trials).
## Ordering contract, the age tie-break, PSX double-head-insert, #212/#214, DEMI:
## vault: .vaults/comments/exmateria_effects/ot-depth-ordering.md
## Vault: [[Display Space Blend Fold]]

## ADR-0212 dec. 1 / ADR-0211 dec. 4 - the schema now declares only
## ExMateriaSchema; this alias keeps the use sites below spelled the way they were.
const DepthMode = ExMateriaSchema.DepthMode

## The PSX OT size (~383-bucket painter's table, ADR-0009: OTZ >> 2). Survives only
## as MAX_ORDER_SPAN's magnitude.
const BUCKET_COUNT := 384

## Per-frame NORMALIZED bucket-span cap for the counting sort: order() subtracts the
## frame's min bucket, so this bounds counts[] to O(PSX OT size); a stray far/near prim
## or fixed-mode sentinel pins to the near extreme. Battle-effect clouds never approach
## this span.
const MAX_ORDER_SPAN := BUCKET_COUNT - 1   # 383, the PSX OT bucket count

# Unified record: 24 floats/instance - [0..19] the MultiMesh-compatible
# ADR-0040 dec. 2 packing, [20] per-prim level_scale (1.0 modes 0/1/2, 0.25
# mode 3), [21..23] vec4 padding. The compositor reads level from the record
# (v_level varying) so a merged add run serves both mode1 and mode3.
const _FLOATS_PER_INSTANCE := 24

# Per-run stride the compositor/renderer pushes as the fp.w push-constant; kept
# explicit here so a drift is caught (UnifiedPrimStagerTest guards the layout).
const _UNIFIED_STRIDE := 24


## Direction class of a compositor blend mode. add/sub accumulate (runs may merge
## same-direction prims); mix rescales dst and is always its own run.
enum Direction { ADD, SUB, MIX }


static func _direction_of(mode: int) -> int:
	match mode:
		2: return Direction.SUB
		0: return Direction.MIX
		_: return Direction.ADD   # 1 (add) and 3 (add25) share the additive direction


## Representative mode for a direction's fold pipeline / is_mix selection.
static func _rep_mode_for(direction: int) -> int:
	match direction:
		Direction.SUB: return 2
		Direction.MIX: return 0
		_: return 1


## Order `records` (N*24 floats, submission order) by the parallel `depths` (N
## reversed-Z OT depths) into a depth-ordered unified buffer + run descriptors.
##
## ===== ORDERING CONTRACT (read before adding a new blended-prim source) =====
## Draw order = (1) depth bucket far->near, then (2) the within-bucket tie-break.
## The tie-break needs a per-prim key because equal-depth prims of OPPOSITE
## direction are non-commutative, and PSX resolves them newest-on-top.
##   * `ages` present (length N): ties by age, NEWEST (smallest elapsed age) on
##     top. REQUIRED when staging order != back-to-front order (particles).
##   * `ages` empty: submission order - correct ONLY if the caller already stages
##     back-to-front, or overlapping opposite-direction prims mis-order (#212).
## Runs: {"mode", "base", "count", "stride", "depth"} - adjacent same-direction
## spans; run.depth is the run's base ot_order_z, a consumer's fold-order key
## (ADR-0200 dec. 1: the descriptor writes five fields, not the four an old
## docstring listed).
static func order(records: PackedFloat32Array, modes: PackedInt32Array,
		depths: PackedFloat32Array, ages: PackedFloat32Array = PackedFloat32Array()) -> Dictionary:
	var n: int = modes.size()
	if n == 0:
		return {"unified": PackedFloat32Array(), "runs": []}

	# LSD radix of two STABLE counting sorts: secondary key (age) FIRST, primary
	# (depth bucket) LAST; each stable pass preserves the prior order among ties -
	# O(N + buckets), never a comparator sort (#219's bucket/radix-assign rule;
	# mechanics + DEMI record in the vault).
	var has_ages: bool = ages.size() == n
	var order_idx: Array = []
	order_idx.resize(n)
	for i in range(n):
		order_idx[i] = i

	# Age pass (secondary key) FIRST: key = maxAge - age, so older (larger age) sorts
	# earlier / folds behind and newest sorts LAST / on top. Skipped when ages are
	# absent - the bucket pass alone then yields the (bucket asc, submission asc)
	# fallback contract.
	if has_ages:
		var max_age: int = 0
		var age_keys := PackedInt32Array()
		age_keys.resize(n)
		for i in range(n):
			var a: int = int(ages[i])
			if a < 0:
				a = 0
			age_keys[i] = a
			if a > max_age:
				max_age = a
		for i in range(n):
			age_keys[i] = max_age - age_keys[i]   # descending -> ascending key
		order_idx = _stable_counting_sort(order_idx, age_keys, max_age)

	# Bucket pass (primary key) LAST. Raw view-Z buckets (round(view_z / 0.19), PSX's
	# SZ>>2, ADR-0009) are large and often negative, so subtract the frame's MIN
	# bucket: compact ascending key, 0 = farthest, near folds last/on top. key_max is
	# the ACTUAL prim span, clamped to MAX_ORDER_SPAN so a stray prim can't blow the
	# key range. Stable, so the age order is preserved within each depth bucket.
	var raw_buckets := PackedInt32Array()
	raw_buckets.resize(n)
	var min_bucket: int = _bucket_of(depths[0])
	for i in range(n):
		var b: int = _bucket_of(depths[i])
		raw_buckets[i] = b
		if b < min_bucket:
			min_bucket = b
	var bucket_keys := PackedInt32Array()
	bucket_keys.resize(n)
	var key_max: int = 0
	for i in range(n):
		var nb: int = raw_buckets[i] - min_bucket   # >= 0 (b >= min_bucket)
		if nb > MAX_ORDER_SPAN:
			nb = MAX_ORDER_SPAN
		bucket_keys[i] = nb
		if nb > key_max:
			key_max = nb
	order_idx = _stable_counting_sort(order_idx, bucket_keys, key_max)

	# --- Emit records in depth order + build maximal same-DIRECTION runs. A prim joins
	#     the current run iff same direction AND that direction is not MIX. ---
	var unified := PackedFloat32Array()
	unified.resize(n * _FLOATS_PER_INSTANCE)
	var runs: Array = []
	var run_dir: int = -1
	var run_base: int = 0
	var run_count: int = 0
	# `depth` = the ot_order_z of the run's BASE (farthest) prim, the EXACT per-prim
	# depth this ordering used, so a consumer bucketing with
	# DepthMode.UNITS_PER_OT_BUCKET gets a value comparable to a callback's own
	# ot_order_z.
	var run_base_depth: float = 0.0
	for out_i in range(n):
		var src: int = order_idx[out_i]
		var src_off: int = src * _FLOATS_PER_INSTANCE
		var dst_off: int = out_i * _FLOATS_PER_INSTANCE
		for f in range(_FLOATS_PER_INSTANCE):
			unified[dst_off + f] = records[src_off + f]

		var d: int = _direction_of(modes[src])
		if d == run_dir and d != Direction.MIX:
			run_count += 1
		else:
			if run_count > 0:
				runs.append({"mode": _rep_mode_for(run_dir), "base": run_base,
					"count": run_count, "stride": _UNIFIED_STRIDE, "depth": run_base_depth})
			run_dir = d
			run_base = out_i
			run_base_depth = depths[src]
			run_count = 1
	if run_count > 0:
		runs.append({"mode": _rep_mode_for(run_dir), "base": run_base,
			"count": run_count, "stride": _UNIFIED_STRIDE, "depth": run_base_depth})

	return {"unified": unified, "runs": runs}


## View-space-Z (DepthMode.ot_order_z, world units) -> a FIXED 0.19-u-wide bucket
## index (PSX's SZ>>2). NO frustum term, NO clamp - the clamp was the #212 collapse
## (the combat camera's key is ~-0.77; clamping it to 0 folded every combat prim into
## one bucket). Ascending in d: farther = smaller index.
static func _bucket_of(d: float) -> int:
	return int(round(d / DepthMode.UNITS_PER_OT_BUCKET))


## STABLE counting sort of `indices` ascending by `keys[index]`, every key in
## [0, key_max]. O(len(indices) + key_max). Stability is what lets order()'s LSD
## radix compose its primary/secondary/tertiary keys without a comparator.
static func _stable_counting_sort(indices: Array, keys: PackedInt32Array, key_max: int) -> Array:
	var counts := PackedInt32Array()
	counts.resize(key_max + 1)   # Packed resize zero-fills
	for idx in indices:
		counts[keys[idx]] += 1
	# Prefix sums -> the start offset of each key's run in the output.
	var start: int = 0
	for k in range(key_max + 1):
		var c: int = counts[k]
		counts[k] = start
		start += c
	var out: Array = indices.duplicate()
	for idx in indices:   # walk in current order -> stable
		var k: int = keys[idx]
		out[counts[k]] = idx
		counts[k] += 1
	return out
