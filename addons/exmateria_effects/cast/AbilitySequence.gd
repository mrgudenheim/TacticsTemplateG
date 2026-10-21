extends RefCounted
## The ability SEQUENCE PLAN: given what an ability looks like (`AbilityVisual`) and
## where its caster and target stand, which parts play and in what order — the
## routing PSX spreads over the battle states 0x2A-0x2E (ITEM_USE_EXECUTION.md §3,
## §5.1, §6, §7.1). It composes E###.BIN documents; it never becomes one: the anim,
## the throw and the hold/release have no E-form data on PSX, so they live here as
## rules, and the E### stays the unit for "the part after release".
##
## Pure: no nodes, no database. A host (the battle loop, the Effect Viewer's ability
## stage) executes the plan.

const AbilityVisual = preload("res://addons/exmateria_effects/cast/AbilityVisual.gd")

## `anim_id` 1 is the Chemist selector (`FUN_80082A44`): hand over or throw.
const ANIM_CHEMIST_SELECTOR := 1
const ANIM_HAND_OVER := 0x39
const ANIM_THROW := 0x4C

## When the held effect is released (`FUN_801A1880`).
const RELEASE_NONE := "none"            # no effect file
const RELEASE_AT_START := "at_start"    # state 0x2C, as the action anim starts
const RELEASE_ON_IMPACT := "on_impact"  # projectile handler 20 lands (deferred word)

## Who drives the camera while the action executes (state 0x2D) — decided for EVERY
## ability by one bit, the effect word's sign (`ability_has_no_effect_file` 0x801A1814):
## with an E###.BIN its camera tables run and the engine follow is off [S]; without one
## `battle_camera_update_cursor_tile_vector` steps the pivot toward the target tile
## (THROW_STONE_ORCHESTRATION.md §3, [S·D]). ADR-0372.
const CAMERA_EFFECT := "effect"
const CAMERA_ENGINE_FOLLOW := "engine_follow"
## No follow and no effect camera: Accumulate. `battle_state_update_action_execute_mode`
## (0x800773F8) follows iff `battle_effect_load_ability(id) != 0` or id is Charge+N, and
## the loader answers 0 ("has an effect") for Accumulate 0x92 although it has no file
## (WEAPON_STRIKE_AND_CLASS_E.md §5 [S·D-seed]: 0 follow calls in 0x2D).
const CAMERA_NONE := "none"

## Charging poses the ROM gives a charge animation (`DAT_801B84AC[pose]` != 0, BATTLE.BIN
## 0x1514AC: `00 02 05 00 …`): 1 = spell charge lines (handler 4), 2 = summon orbs
## (handler 22). Every other pose — items' 9 included — has none on PSX.
const CHARGE_POSES_WITH_ANIM: Array[int] = [1, 2]
## The TRAP handler each of those poses plays, lifted as a document (ADR-0369).
const CHARGE_HANDLER_BY_POSE := {1: "h04", 2: "h22"}
## The charge's clock, in vsyncs (one handler tick each), from the effect loader
## `battle_effect_init_data` 0x801a13bc (SPELL_CHARGE_LINES.md §8, SUMMON_CHARGE_ORBS.md §4,
## branch research/spell-charge-lines [S·D]): the charge is started at CAST time — not
## across the unit's CT charge — and held until the effect file has loaded AND a 60-vsync
## countdown has run out, `max(60, load)`; then finalized. Lines drain (each runs out its
## own life, ≤ 38 ticks), orbs play a fixed 61-tick finale, and the effect proper (phase
## 1→2) starts 2 vsyncs after the charge's last tick (Fire vs152→154, Moogle vs187→189).
const CHARGE_HOLD_MIN := 60
const CHARGE_LINE_MAX_DRAIN := 38
const CHARGE_ORB_FINALE := 61
const CHARGE_TO_HANDOFF := 2

## The PRE-ABILITY beat, between "ability confirmed" and the effect (PRE_ABILITY_SEQUENCE.md
## §Spec for the port; [S·D], identical on Night Sword / Yell / Thunder Soul / Bolt / Mog):
##   * the START pose `set[0]` (state 0x1C, an immediate cast only) until its SEQ halts, capped
##     at 0x3D loops (`battle_state_handle_pre_attack_animation_state` 0x80076F14);
##   * the ANNOUNCE (state 0x29): 67 vsyncs every time — ~6 of thread lead-in, then the name
##     plate's 61 visible vsyncs (its 60-tick budget, `battle_menu_icon_timed_thread` 0x8013B00C),
##     or the flavor-text quote instead (§5);
##   * then state 0x2B: with a charge secondary the 60-vsync minimum + its drain (CHARGE_HOLD_MIN,
##     above — Bolt 96, Mog 122); without one only the E### file LOAD, 36–40 vsyncs in the
##     emulator (CD-bound). The port loads at once, so it holds the measured 40
##     (LOAD_HOLD_VSYNCS); an ability with no file has no load (Accumulate's 0x2B is one loop).
## The caster holds `set[1]`, the sustain, from the end of the start pose until the attack anim.
const START_POSE_CAP := 0x3D
const ANNOUNCE_VSYNCS := 67
const ANNOUNCE_PLATE_LEAD := 6
const LOAD_HOLD_VSYNCS := 40

## Wind-up lanes (engine phases before the hand-off; ADR-0373).
const LANE_CHARGE := "charge"  # the charge visual: init + hold + drain/finale, then the hand-off
const LANE_ANIM := "anim"      # the execution anim (cast / throw / hand-over SEQ)
const LANE_FLIGHT := "flight"  # projectile handler 20: DUR loops of the line of fire
const LANE_HOLD := "hold"      # the effect loaded and HELD (effect_system_state 1)
## The released DOCUMENT the action AWAITS (`sequence_lanes`' `payload_ticks`): state 0x2D
## (`FUN_800773F8`) waits for `effect_system_state` 0 before 0x2E — Potion: released f93,
## effect list empty f153, 0x2E f154 (ITEM_USE_EXECUTION.md §3, §6: both item routes).
const LANE_EFFECT := "effect"

## An engine payload hands off at handler 20's countdown 2 (the impact event); the
## handler runs two more loops to countdown 0 (Throw Stone, PCSX — see wind_up).
const ENGINE_HANDOFF_BEFORE_HANDLER_END := 2

## Payload kinds — what plays from the hand-off (t = 0).
const PAYLOAD_DOCUMENT := "document"  # an E### file (or a TRAP-lifted document)
const PAYLOAD_ENGINE := "engine"      # engine code with no document (an impact event)

## The engine payload of an engine-driven ability (class D / E, ADR-0372): handler 20's
## countdown-2 `projectile_impact_event`, or a swing's SEQ 0xDE — the TRAP hit cloud, the
## target's reaction, the damage number and the hit SFX.
const ENGINE_IMPACT := "engine_impact"
## The engine payload of an ability whose only particle is an engine secondary started at
## 0x2B (Accumulate's red orbs): it plays from its own init, and the anim follows.
const ENGINE_SECONDARY := "engine_secondary"

## --- Class E (WEAPON_STRIKE_AND_CLASS_E.md; ADR-0372 dec. 14) ---------------------
## The mechanism an ability executes, from ROM data and its id (an id range is a ROM fact:
## the dispatcher and the loader test these ranges). "" = no class-E mechanism of its own.
const FAMILY_NONE := ""
const FAMILY_SWING := "swing"            # anim table value 0: the weapon-swing selector (§2.2)
const FAMILY_JUMP := "jump"              # every Jump executes as 0x18A, anim 0x76 (§6)
const FAMILY_ACCUMULATE := "accumulate"  # red orbs + held crouch 0x16, no hit (§7)
const FAMILY_REACTION := "reaction"      # 0x1A6..0x1C5: not ported, needs RE (§8)
const FAMILY_PASSIVE := "passive"        # support / movement 0x1C6..: never an action
## The Chemist selector's (anim table value 1, `FUN_80082A44`): hand the item over to a
## neighbour (0x39) or throw it (0x4C) — the 14 items (ITEM_USE_EXECUTION.md §5.1).
const FAMILY_ITEM := "item"

const ABILITY_ATTACK := 0x16F
const ABILITY_ACCUMULATE := 0x92
const FIRST_JUMP := 0x18A
const LAST_JUMP := 0x195
const FIRST_CHARGE := 0x196
const LAST_CHARGE := 0x19D
const FIRST_REACTION := 0x1A6
const LAST_REACTION := 0x1C5
const FIRST_PASSIVE := 0x1C6
## `battle_action_prepare_attack` (0x8017C45C) JUMP case: ability id := 0x18A whichever
## Jump was chosen — so the port plans every Jump as Level Jump 2 (§6.1, §6.3).
const JUMP_EXECUTES_AS := 0x18A

## The action weapon (misc+0x1AB): the weapon the swing draws and whose hit SFX plays.
## 0x8018B34C keeps the equipped weapon iff flags1 & (0x20 | 0x04), menu Attack/Charge
## always keeps it, menu Jump always zeroes it (item 0: the FISTS row, `hit_tbl[0]`).
const WEAPON_EQUIPPED := "equipped"
const WEAPON_FISTS := "fists"

## vsyncs from the 0x2C loop (loop pacing 1: a tick is a vsync), §3 / §6.2 / §7 captures.
const SWING_SFX_AT := 13      # `battle_sound_select_weapon_hit` mode 0 (Head Break, Charge+1)
const HIT_AT_SWING := 17      # SEQ 0xDE of the melee / fist LEVEL swing (0x41, 0x3E)
const HIT_AT_JUMP := 95       # anim 0x76's 0xDE
const EXIT_SWING := 56        # 0x2E, Head Break
const EXIT_CHARGE := 58       # 0x2E, Charge+1
const EXIT_JUMP := 130        # 0x2E, Jump 0x18A
const EXIT_ACCUMULATE := 22   # 0x2D's length, Accumulate
## Engine secondary 0x11 (handler 6, red orbs, SFX 8): init at 0x2B, 22 loops, not
## awaited. 0x2B lasts one loop: 5 vsyncs before 0x2C for Charge+1, 1 for Accumulate.
const SECONDARY_RED_ORBS := "red_orbs"
const RED_ORBS_TICKS := 22
const RED_ORBS_LEAD_CHARGE := 5
const RED_ORBS_LEAD_ACCUMULATE := 1
## The TRAP hit cloud 0x801ADFEC picks: anim 7 (handler 2) on a hit, 0x12 (handler 21,
## the white break triangles) only when the target's `special_effect & BREAK_EQUIPMENT`
## — a break that LANDED, not "a break formula" (§4 [S·D-seed]).
const CLOUD_HIT := 7
const CLOUD_BREAK := 0x12
## Jump landing lanes, [start, end] vsyncs after 0x2C (§6.2, `r1_jump18a_seed`): distortion
## 0x11 rise with SFX 0x27, 0x08 one-frame snap over the target, 0x0D fall with SFX 0x1C,
## the 0xDE hit at +95, 0x10 arc back to the own tile with a palette fade.
const JUMP_RISE := [21, 56]
const JUMP_SNAP := [56, 57]
const JUMP_FALL := [57, 92]
const JUMP_RETURN := [96, 116]
## The class-E lanes (`class_e_lanes`).
const LANE_SWING_SFX := "swing_sfx"
const LANE_SECONDARY := "engine_secondary"
const LANE_JUMP_RISE := "jump_rise"
const LANE_JUMP_SNAP := "jump_snap"
const LANE_JUMP_FALL := "jump_fall"
const LANE_JUMP_RETURN := "jump_return"

## Sequence events (`sequence_events`): the payload's pseudo-lane, and a lane event's edge.
const LANE_PAYLOAD := "payload"
const EDGE_START := "start"
const EDGE_END := "end"
## Play order inside one tick (`sequence_events`).
const EVENT_RANK_END := 0
const EVENT_RANK_START := 1
const EVENT_RANK_PAYLOAD := 2
const EVENT_RANK_POINT_END := 3

## Engine lanes (ADR-0372) the Studio draws beside the wind-up — they are not all before
## the hand-off: the engine impact runs from it, and the camera is its own clock (§4.1).
const LANE_CAMERA := "camera"            # the engine cursor-follow toward the target (0x2D)
const LANE_IMPACT := "impact"            # the engine impact, hand-off -> the 0x2D exit
const LANE_CAMERA_BACK := "camera_back"  # 0x2F: the cursor on the actor, the follow pans back
## Ticks from the hand-off to the 0x2D exit: MEASURED for Throw Stone (sstate6, framed and
## far: f98 / f104 = impact + 35). The exit waits on the target's knockback and the damage
## number, which the port does not model per ability — so the lane is NOMINAL elsewhere.
const ENGINE_EXIT_TICKS := 35
## The one engine throw whose exit was captured (ENGINE_EXIT_TICKS): Throw Stone.
const ABILITY_THROW_STONE := 0x94
## 0x2E's recovery (5 loops) + the 0x2F loop that moves the cursor onto the actor.
const ENGINE_EXIT_TO_BACK_AIM := 6


## `(|dx|, |dz|)` in {(0,0), (1,0), (0,1)} on tile X/Z, no height — the self or
## orthogonal-neighbour test the Chemist selector and the resolver both make.
static func is_hand_over_distance(caster_tile: Vector2i, target_tile: Vector2i) -> bool:
	var dx := absi(target_tile.x - caster_tile.x)
	var dz := absi(target_tile.y - caster_tile.y)
	return (dx < 1 and dz < 1) or (dx < 2 and dz == 0) or (dx == 0 and dz < 2)


## The §7.1 class this ability belongs to, from data alone (no geometry): "C" thrown
## payload, "D" engine-only projectile, "E" engine-only swing, "A/B" an effect-file
## ability (Pattern 1 vs 2 is the FILE's script — op 41 vs 40 — so a host that loads
## the file refines it), "" for an absent visual. A UI grouping, not an input.
static func classify(visual: AbilityVisual) -> String:
	if visual == null or visual.is_empty():
		return ""
	if visual.deferred:
		return "C"
	if visual.effect_index < 0:
		return "D" if visual.projectile_type >= 0 else "E"
	return "A/B"


## The plan: {visual_class, anim_id, release, projectile, effect_index, camera, ...}.
## `anim_id` is the execution anim — the table value, with the Chemist selector resolved
## (0x39 / 0x4C); a table value 0 stays 0 and `swing` says the weapon-swing selector picks
## the row (a host resolves it through its rig: weapon type x `swing_band`). `projectile`
## = SEQ opcode 0xD9 launches handler 20; `release` = when the held effect starts.
##
## The class-E keys (ADR-0372 dec. 14; all additive, all on the 0x2C clock in vsyncs):
##   family            FAMILY_* — the mechanism (swing / jump / accumulate / reaction / passive)
##   swing             the caster swings its weapon (anim table value 0, not a Jump)
##   weapon            WEAPON_EQUIPPED / WEAPON_FISTS / "" — the action weapon (swing + hit SFX)
##   executes_as       the id the ROM executes (0x18A for every Jump)
##   hit_at            0x2C -> SEQ 0xDE (the engine impact); -1 = no hit. A host that reads
##                     the SEQ passes its own tick to `wind_up`
##   exit              0x2C -> the 0x2D exit, MEASURED for the family; -1 = not measured
##   engine_secondary  "" / SECONDARY_RED_ORBS (0x11, from 0x2B)
##   breaks            a landed hit shows the break cloud 0x12 (`impact_cloud`)
##   pacing            vsyncs per loop in 0x2D: 2 when a file plays, else 1
##   not_ported        "" or why the port cannot play this ability at all (never a dummy)
##   partial           [why] for parts of a ported ability the port does not play
static func plan(visual: AbilityVisual, caster_tile: Vector2i, target_tile: Vector2i) -> Dictionary:
	var cls := classify(visual)
	var anim := visual.anim_id if visual != null else -1
	var handed := false
	if anim == ANIM_CHEMIST_SELECTOR:
		handed = is_hand_over_distance(caster_tile, target_tile)
		anim = ANIM_HAND_OVER if handed else ANIM_THROW
	var projectile: bool = visual != null and visual.projectile_type >= 0 and not handed
	var release := RELEASE_NONE
	if visual != null and visual.effect_index >= 0:
		release = RELEASE_ON_IMPACT if (visual.deferred and projectile) else RELEASE_AT_START
	if cls == "C" and handed:
		cls = "C'"
	var effect_index: int = visual.effect_index if visual != null else -1
	var engine := is_engine_driven(visual)
	var fam := family(visual)
	var p := {
		"visual_class": cls,
		"anim_id": anim,
		"release": release,
		"projectile": projectile,
		"effect_index": effect_index,
		"charge": visual != null and visual.charging_pose_id in CHARGE_POSES_WITH_ANIM,
		# What plays from the hand-off. An engine payload's `id` is filled by the class
		# that owns it (Throw Stone's impact event and friends); "" = not described yet.
		"payload": {"kind": PAYLOAD_DOCUMENT, "id": "E%03d" % effect_index} if effect_index >= 0
			else {"kind": PAYLOAD_ENGINE, "id": ENGINE_IMPACT if engine else ""},
		"camera": CAMERA_ENGINE_FOLLOW if engine else CAMERA_EFFECT,
		"family": fam,
		"swing": fam == FAMILY_SWING,
		"weapon": "",
		"executes_as": visual.ability_id if visual != null else -1,
		"hit_at": -1,
		"exit": -1,
		"engine_secondary": "",
		"breaks": false,
		"pacing": 2 if release != RELEASE_NONE else 1,
		"not_ported": "",
		"partial": [],
	}
	match fam:
		FAMILY_SWING:
			p.weapon = WEAPON_EQUIPPED if _keeps_weapon(visual) else WEAPON_FISTS
			p.hit_at = HIT_AT_SWING
			p.breaks = visual.plays_break_visual()
			if engine:
				p.exit = EXIT_SWING
			if _is_charge(visual.ability_id):
				p.exit = EXIT_CHARGE
				p.engine_secondary = SECONDARY_RED_ORBS
		FAMILY_JUMP:
			p.weapon = WEAPON_FISTS
			p.executes_as = JUMP_EXECUTES_AS
			p.hit_at = HIT_AT_JUMP
			p.exit = EXIT_JUMP
			p.partial = ["the commit turn (anim 0x75 rise, sprite off, CT 50/Speed) — static only (WEAPON_STRIKE_AND_CLASS_E.md §6.1, open question 1)",
				"after-images and the return's palette fade"]
		FAMILY_ACCUMULATE:
			p.exit = EXIT_ACCUMULATE
			p.engine_secondary = SECONDARY_RED_ORBS
			p.camera = CAMERA_NONE
			p.payload = {"kind": PAYLOAD_ENGINE, "id": ENGINE_SECONDARY}
		FAMILY_REACTION:
			p.payload = {"kind": PAYLOAD_ENGINE, "id": ""}
			p.not_ported = "a reaction: it plays another action or modifies the incoming hit, and has no genuine dynamic capture yet (WEAPON_STRIKE_AND_CLASS_E.md §8, open question 2)"
		FAMILY_PASSIVE:
			p.payload = {"kind": PAYLOAD_ENGINE, "id": ""}
			p.not_ported = "a support / movement ability: it never executes as an action"
	return p


## The class-E family of `visual` (FAMILY_*), from its ability id and anim table value.
static func family(visual: AbilityVisual) -> String:
	if visual == null or visual.is_empty():
		return FAMILY_NONE
	var id := visual.ability_id
	if id >= FIRST_PASSIVE:
		return FAMILY_PASSIVE
	if id >= FIRST_REACTION and id <= LAST_REACTION:
		return FAMILY_REACTION
	if id >= FIRST_JUMP and id <= LAST_JUMP:
		return FAMILY_JUMP
	if id == ABILITY_ACCUMULATE:
		return FAMILY_ACCUMULATE
	if visual.anim_id == ANIM_CHEMIST_SELECTOR:
		return FAMILY_ITEM
	if visual.anim_id == 0 and id >= 0:
		return FAMILY_SWING
	return FAMILY_NONE


static func _is_charge(ability_id: int) -> bool:
	return ability_id >= FIRST_CHARGE and ability_id <= LAST_CHARGE


## 0x8018B34C / 0x8018B274: the equipped weapon stays the action weapon iff flags1 & 0x24,
## or the menu is Attack / Charge.
static func _keeps_weapon(visual: AbilityVisual) -> bool:
	return visual.weapon_strike or visual.weapon_range or visual.ability_id in [0, ABILITY_ATTACK] \
		or _is_charge(visual.ability_id)


## The swing row's height column (`battle_unit_select_weapon_attack_animation` 0x8008288C):
## `dy` = target minus caster sprite-centre height in PSX units (up is negative), < -11 ->
## 0 high, >= 12 -> 2 low, else 1 level — the `vertical` `Unit.attack` takes.
static func swing_band(dy: int) -> int:
	if dy < -11:
		return 0
	return 2 if dy >= 12 else 1


## The TRAP hit-cloud animation the engine impact spawns: CLOUD_BREAK when `landed` and the
## ability breaks, CLOUD_HIT otherwise, -1 when there is no engine hit (an effect file owns
## the impact — Stasis Sword's swing spawned none — or the ability never hits).
static func impact_cloud(p: Dictionary, landed: bool) -> int:
	if p.get("payload", {}).get("id", "") != ENGINE_IMPACT:
		return -1
	return CLOUD_BREAK if landed and p.get("breaks", false) else CLOUD_HIT


## The charge visual charging pose `pose` plays on PSX, as a lifted TRAP variant ("h04"
## lines, "h22" orbs); "" for every pose the ROM gives none.
static func charge_variant(pose: int) -> String:
	return CHARGE_HANDLER_BY_POSE.get(pose, "")


## How long the loader holds a charge before finalizing it, in vsyncs: the 60-vsync
## countdown or the effect file's load, whichever is longer. A host whose load is
## immediate holds 60.
static func charge_hold(load_vsyncs: int = 0) -> int:
	return maxi(CHARGE_HOLD_MIN, load_vsyncs)


## The vsyncs the cast holds after its announce when it has NO charge secondary (a charge
## runs its own hold, `charge_hold`): the E### load, LOAD_HOLD_VSYNCS, for a plan whose payload
## is a document; 0 for an engine payload — there is no file to load.
static func load_hold(p: Dictionary) -> int:
	if p.get("charge", false):
		return 0
	return LOAD_HOLD_VSYNCS if String(p.get("payload", {}).get("kind", "")) == PAYLOAD_DOCUMENT else 0


## The taxonomy's top split (ADR-0372): no E###.BIN, so the ENGINE drives the camera
## (cursor follow) and plays the hit. Classes D and E; A/B and C are effect-driven.
static func is_engine_driven(visual: AbilityVisual) -> bool:
	return visual != null and not visual.is_empty() and visual.effect_index < 0


## The WIND-UP: the engine phases before the hand-off, in ticks (one handler-20 loop /
## one SEQ tick each), placed relative to t = 0. A host supplies the measured parts:
## `anim_to_launch` = ticks from anim start to SEQ opcode 0xD9, `flight_loops` = the
## line-of-fire DUR, `anim_ticks` = the SEQ's own length, `charge_ticks` = the loader's HOLD
## (`charge_hold`) and `charge_drain` = the ticks the charge runs after it is finalized
## (the lines' drain, measured off the instance; the orbs' CHARGE_ORB_FINALE). Derived
## from ROM data and PCSX measurements; nothing here is E-form. Returns
## `[{lane, start, end, nominal}]`, in charge / hold / anim / flight order.
##
## The charge lane is the charge visual's whole life, [init tick, last tick + 1): the init,
## the hold, then the drain or finale; its last tick is CHARGE_TO_HANDOFF vsyncs before the
## anim — the effect proper WAITS for it. Its `finalize` key is the first tick after the hold.
##
## Where t = 0 falls, and so where the flight sits, depends on what hands off:
##   * a thrown DOCUMENT (class C) hands off when handler 20 reaches countdown 0 and
##     releases the held effect: 0xD9 at f83 -> release at f93 = DUR loops later, the
##     handler ending at the hand-off (ITEM_USE_EXECUTION.md §3, §5.5). Flight [-DUR, 0].
##   * a thrown ENGINE payload (class D) hands off at countdown 2, the impact event; the
##     handler runs on to countdown 0 = +2. Launch -> impact is DUR - 1 (Throw Stone,
##     PCSX sstate6, framed and far — THROW_STONE_ORCHESTRATION.md round 5). Flight
##     [-(DUR - 1), +2].
## The thrower's anim does not have a fixed length: it runs its SEQ and then HOLDS until
## handler 20 ends — measured for Throw Stone (framed: SEQ 31, ends +5; far: ends +2 after
## 34 loops), so end = max(start + SEQ length, handler end). For items that rule is an
## INFERENCE from Throw Stone (the same anim 0x4C and the same handler 20); no item
## anim end has been measured.
##
## A class-E ability hands off at its engine hit, SEQ opcode 0xDE (a swing's, a Jump's):
## the anim starts `anim_to_hit` ticks before t = 0 — the host's reading of the SEQ, or
## the plan's captured `hit_at` when it passes -1 — and holds its last frame to the
## family's measured 0x2D exit (§3). Accumulate hands off at its red orbs' init (0x2B),
## one loop before its anim.
static func wind_up(p: Dictionary, anim_to_launch: int, flight_loops: int, anim_ticks: int,
		charge_ticks: int, anim_to_hit: int = -1, charge_drain: int = 0) -> Array:
	var phases := []
	var thrown: bool = p.projectile
	var document_payload: bool = p.get("payload", {}).get("kind", "") == PAYLOAD_DOCUMENT
	# Launch tick and the tick handler 20 ends, relative to the hand-off.
	var launch := 0
	var handler_end := 0
	if thrown:
		if document_payload:
			launch = -flight_loops
			handler_end = 0
		else:
			launch = -(flight_loops - 1)
			handler_end = ENGINE_HANDOFF_BEFORE_HANDLER_END
	var anim_start: int = launch - anim_to_launch if thrown else 0
	var anim_end: int = maxi(anim_start + anim_ticks, handler_end) if thrown else anim_start + anim_ticks
	if not thrown:
		if p.get("payload", {}).get("id", "") == ENGINE_IMPACT and int(p.get("hit_at", -1)) >= 0:
			anim_start = -(anim_to_hit if anim_to_hit >= 0 else int(p.hit_at))
		elif p.get("family", "") == FAMILY_ACCUMULATE:
			anim_start = RED_ORBS_LEAD_ACCUMULATE
		var exit: int = int(p.get("exit", -1))
		anim_end = anim_start + (maxi(anim_ticks, exit) if exit >= 0 else anim_ticks)
	if p.get("charge", false):
		var last_tick := anim_start - CHARGE_TO_HANDOFF
		var first_tick := last_tick - charge_drain - charge_ticks
		phases.append({"lane": LANE_CHARGE, "start": first_tick, "end": last_tick + 1,
			"finalize": first_tick + charge_ticks + 1, "nominal": false})
	if p.release == RELEASE_ON_IMPACT:
		phases.append({"lane": LANE_HOLD, "start": anim_start, "end": 0, "nominal": false})
	phases.append({"lane": LANE_ANIM, "start": anim_start, "end": anim_end, "nominal": false})
	if thrown:
		phases.append({"lane": LANE_FLIGHT, "start": launch, "end": handler_end, "nominal": false})
	return phases


## The SEQUENCE's lanes on one axis (t = 0 the hand-off): `wind_up`, then `class_e_lanes`
## placed from its anim lane — what the Effect Studio draws and poses and what the battle
## plays (ADR-0372 dec. 15). The ONE composition: a host that re-assembles the two itself
## is a second implementation that can drift. Engine CAMERA lanes (`engine_lanes`) need
## the host's camera replay and are appended by it. A thrown ENGINE payload (`is_engine_throw`,
## Throw Stone) also carries `engine_lanes`' IMPACT lane [0, the 0x2D exit]: its action ends
## there, not at its anim, so the window must reach it.
##
## `payload_ticks` > 0 is a DOCUMENT payload the action AWAITS, that many ticks long from the
## hand-off: lane LANE_EFFECT [0, payload_ticks] (0x2D waits for the effect list to empty,
## ITEM_USE_EXECUTION.md §3 / §6). A zero-length anim lane — a hold-forever SEQ (duration 0,
## the hand-over's SEQ 114: `AnimationFrameCalculator.is_hold_forever`) — then holds to the
## effect's end: nothing but the next anim ends such a pose, and the next anim is 0x2E's.
## 0 = no awaited document (the host decides which plans await one: CombatCastHost).
static func sequence_lanes(p: Dictionary, anim_to_launch: int, flight_loops: int,
		anim_ticks: int, charge_ticks: int, anim_to_hit: int = -1, charge_drain: int = 0,
		payload_ticks: int = 0) -> Array:
	var lanes := wind_up(p, anim_to_launch, flight_loops, anim_ticks, charge_ticks, anim_to_hit,
		charge_drain)
	var anim_start := 0
	var awaits: bool = payload_ticks > 0 \
		and String(p.get("payload", {}).get("kind", "")) == PAYLOAD_DOCUMENT
	for ph in lanes:
		if ph.lane == LANE_ANIM:
			anim_start = int(ph.start)
			if awaits and int(ph.end) == int(ph.start):
				ph.end = maxi(int(ph.end), payload_ticks)
	lanes.append_array(class_e_lanes(p, anim_start))
	if awaits:
		lanes.append({"lane": LANE_EFFECT, "start": 0, "end": payload_ticks, "nominal": false})
	if is_engine_throw(p):
		# A thrown ENGINE payload's action ends at the 0x2D exit, not at its anim: the throw
		# anim holds only to handler 20's end (+2 / +5), then 0x2D waits on the target's
		# knockback and damage number to impact + ENGINE_EXIT_TICKS (THROW_STONE_ORCHESTRATION.md
		# §4.2). That is `engine_lanes`' impact lane — the same lane, so the window the battle
		# freezes and the lane the Studio draws are one.
		for ph in engine_lanes(p, anim_start, 0, 0, ENGINE_EXIT_TICKS,
				int(p.get("executes_as", -1)) == ABILITY_THROW_STONE):
			if ph.lane == LANE_IMPACT:
				lanes.append(ph)
	return lanes


## A THROWN ENGINE payload (class D, ADR-0372): handler 20 flies a projectile and its
## countdown-2 impact event is the payload — Throw Stone, and the Throw command's weapons.
static func is_engine_throw(p: Dictionary) -> bool:
	return bool(p.get("projectile", false)) \
		and String(p.get("payload", {}).get("id", "")) == ENGINE_IMPACT


## The FREEZE window of a sequence (ADR-0372 dec. 15): the world freezes at the START of
## the first lane event and unfreezes at the END of the last one — `{start, end}` in the
## lanes' ticks, `end - start` the freeze's length. The CHARGE lane is not in it: in battle
## a charge lasts the ability's CT, gameplay time the world keeps running through (the
## Studio plays one fixed hold), so the sequence proper opens when the charge completes.
## {start 0, end 0} for no lanes.
static func freeze_window(lanes: Array) -> Dictionary:
	var first := 0
	var last := 0
	var any := false
	for ph in lanes:
		if ph.lane == LANE_CHARGE:
			continue
		if not any:
			first = int(ph.start)
			last = int(ph.end)
			any = true
			continue
		first = mini(first, int(ph.start))
		last = maxi(last, int(ph.end))
	return {"start": first, "end": last}


## The EVENTS of a sequence (ADR-0372 dec. 15): what a player fires as the playhead crosses
## the lanes — every lane's START and END, and the payload's start — as
## `[{lane, edge, at}]` in lane ticks, in play order. THE list: the battle plays exactly it
## (CinematicManager) and the Studio exposes it for the same lanes (`studio_sequence_events`),
## so a host that builds its own list is a second implementation that can drift.
##   * The CHARGE lane has none: it is CT time outside the window (`freeze_window`), played
##     by the charge path, not the sequence.
##   * The payload (lane `LANE_PAYLOAD`, edge start) starts at `payload_at`.
##   * At one tick, a lane's end plays before another's start (the jump's snap -> fall), a
##     point lane (start == end: the swing SFX) plays its start then its end, and the payload
##     plays after the starts of its tick (Accumulate: the orbs' lane opens, then the orbs).
static func sequence_events(p: Dictionary, lanes: Array) -> Array:
	var keyed := []
	var i := 0
	for ph in lanes:
		if ph.lane == LANE_CHARGE:
			continue
		var s := int(ph.start)
		var e := int(ph.end)
		keyed.append([s, EVENT_RANK_START, i, {"lane": String(ph.lane), "edge": EDGE_START, "at": s}])
		keyed.append([e, EVENT_RANK_POINT_END if e == s else EVENT_RANK_END, i,
			{"lane": String(ph.lane), "edge": EDGE_END, "at": e}])
		i += 1
	if not String(p.get("payload", {}).get("kind", "")).is_empty():
		var at := payload_at(p, lanes)
		keyed.append([at, EVENT_RANK_PAYLOAD, i, {"lane": LANE_PAYLOAD, "edge": EDGE_START, "at": at}])
	keyed.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and (a[1] < b[1]
		or (a[1] == b[1] and a[2] < b[2]))))
	var out := []
	for k in keyed:
		out.append(k[3])
	return out


## The lane tick the payload starts on: the hand-off (t = 0), except an ENGINE SECONDARY
## payload (Accumulate's red orbs), which plays from its own lane's init (0x2B).
static func payload_at(p: Dictionary, lanes: Array) -> int:
	if String(p.get("payload", {}).get("id", "")) == ENGINE_SECONDARY:
		for ph in lanes:
			if ph.lane == LANE_SECONDARY:
				return int(ph.start)
	return 0


## THE CAST HOLDS (U21 / Q1): the caster keeps its execution anim past the SEQ — a cast (a
## DOCUMENT its own anim hands off to) — until the ROM lets it go (its own 0x10 keyframe, or
## the battle leaving 0x2D at the document's end). A swing, a hand-over, a throw and an
## engine payload release it at the anim lane's end. research/working_documents/self_react_captures/.
static func cast_holds(p: Dictionary) -> bool:
	return not p.get("swing", false) \
		and String(p.get("payload", {}).get("kind", "")) == PAYLOAD_DOCUMENT \
		and not (int(p.get("anim_id", -1)) in [ANIM_HAND_OVER, ANIM_THROW])


## The TRAP handler an ENGINE payload plays from the hand-off (the Studio opens it as its
## document; the battle spawns it): the hit cloud `impact_cloud` picks — "h02" (anim 7) or
## "h21" (the break cloud 0x12) — for an engine impact, "h06" (the red orbs, secondary
## 0x11) for an engine secondary (Accumulate). "" for anything else.
static func engine_payload_handler(p: Dictionary, landed: bool) -> String:
	match String(p.get("payload", {}).get("id", "")):
		ENGINE_IMPACT:
			return "h21" if impact_cloud(p, landed) == CLOUD_BREAK else "h02"
		ENGINE_SECONDARY:
			return "h06"
	return ""


## The ENGINE lanes of an engine-driven ability (camera == engine_follow, an engine
## payload), in engine ticks relative to the hand-off — appended to `wind_up`'s phases:
##   * camera: the follow aims as the throw anim starts (`anim_start`, PSX 0x2C/0x2D) and
##     moves for `follow_loops` (a replay of the ROM rule; 0 = the target was framed);
##   * impact: the engine impact, from the hand-off to the 0x2D exit;
##   * camera_back: 0x2F puts the cursor on the actor `ENGINE_EXIT_TO_BACK_AIM` after the
##     exit, and the same rule pans back for `back_loops` — 0 when the actor is still in
##     the window, which the ROM holds too (WEAPON_STRIKE_AND_CLASS_E.md §5.1, U25);
## Nothing gates anything (THROW_STONE_ORCHESTRATION.md §4.1): the camera can finish before
## the hand-off, or not move at all. Returns [] for an effect-driven ability.
## `exit_measured`: true only where the exit was captured (Throw Stone); else the lane
## is drawn NOMINAL.
##
## A plan whose family carries a measured `exit` (class E) overrides `exit_ticks`: the exit
## is `exit` vsyncs after the anim start, and MEASURED.
static func engine_lanes(p: Dictionary, anim_start: int, follow_loops: int, back_loops: int,
		exit_ticks: int = ENGINE_EXIT_TICKS, exit_measured: bool = false) -> Array:
	if p.get("camera", "") != CAMERA_ENGINE_FOLLOW:
		return []
	if int(p.get("exit", -1)) >= 0:
		exit_ticks = anim_start + int(p.exit)
		exit_measured = true
	var back_aim := exit_ticks + ENGINE_EXIT_TO_BACK_AIM
	return [
		{"lane": LANE_CAMERA, "start": anim_start, "end": anim_start + follow_loops, "nominal": false},
		{"lane": LANE_IMPACT, "start": 0, "end": exit_ticks, "nominal": not exit_measured},
		{"lane": LANE_CAMERA_BACK, "start": back_aim, "end": back_aim + back_loops, "nominal": false},
	]


## The CLASS-E lanes (ADR-0372 dec. 14), on the same axis as `wind_up` and
## `engine_lanes`, from the anim's start (0x2C) `anim_start`:
##   * swing_sfx: the weapon's swing sound, a point at +13 (`select_weapon_hit` mode 0);
##   * engine_secondary: the red orbs (0x11) from 0x2B, one loop before the anim, for 22;
##   * jump_rise / jump_snap / jump_fall / jump_return: anim 0x76's distortions (§6.2).
## [] for an ability with none of them. None is NOMINAL: each is a §3/§6/§7 capture.
static func class_e_lanes(p: Dictionary, anim_start: int) -> Array:
	var lanes := []
	if p.get("swing", false):
		lanes.append({"lane": LANE_SWING_SFX, "start": anim_start + SWING_SFX_AT,
			"end": anim_start + SWING_SFX_AT, "nominal": false})
	if p.get("engine_secondary", "") == SECONDARY_RED_ORBS:
		var lead := RED_ORBS_LEAD_ACCUMULATE if p.get("family", "") == FAMILY_ACCUMULATE \
			else RED_ORBS_LEAD_CHARGE
		lanes.append({"lane": LANE_SECONDARY, "start": anim_start - lead,
			"end": anim_start - lead + RED_ORBS_TICKS, "nominal": false})
	if p.get("family", "") == FAMILY_JUMP:
		for pair in [[LANE_JUMP_RISE, JUMP_RISE], [LANE_JUMP_SNAP, JUMP_SNAP],
				[LANE_JUMP_FALL, JUMP_FALL], [LANE_JUMP_RETURN, JUMP_RETURN]]:
			lanes.append({"lane": pair[0], "start": anim_start + int(pair[1][0]),
				"end": anim_start + int(pair[1][1]), "nominal": false})
	return lanes
