@tool
extends RefCounted
## The tunable registry's PORT SIGNATURE — the six verbs a portable addon may name.
##
## `src/core/Tune.gd` is a HOST autoload, and an `[autoload]` line can only be
## written by the consuming game's `project.godot`: an install step, not an
## interface, which is why naming the singleton directly fails goal #5 and why
## `check_addon_portability.py` arm 2 counted every such line as standalone-parse
## debt. This class converts that **host-project-configuration** dependency into
## an **addon-presence** dependency — the shape ADR-0175 dec. 2 chose and
## ADR-0139 dec. 12 already named, *"a schema whose realisation is a port's
## signature"*. A signature is a `class_name` with methods; a bare autoload
## identifier is not one.
##
## The binding is a NODE-PATH soft-bind resolved at call time, not a compile-time
## edge, and that is load-bearing twice over:
##
##  - It dissolves ADR-0159's amendment's *"hard bound on the fix"*. The registry
##    is the FIRST autoload, so a compile-time `class_name` edge FROM it would
##    eager-load every owner during its own boot, against a Nil singleton. This
##    edge runs the other way and touches nothing until a call happens.
##  - It gives the port a defined ABSENT behaviour, which is what makes the addon
##    installable somewhere the host script does not exist at all.
##
## 🔴 **Absent is not the same answer for every verb**, and the difference is
## whether the call carries a literal:
##
## | verb | with the port | without it |
## |---|---|---|
## | `bind` | registers; returns the coalesced value | returns `literal`, and registers it WHEN A PORT APPEARS (`_deferred`) |
## | `bind_update` | registers + subscribes + applies now | applies `literal` ONCE |
## | `on_update` | subscribes + applies now | **no-op** |
## | `get_value` | the coalesced value | `fallback` |
## | `set_value` | writes the override + emits | no-op |
## | `on_any_change` | connects to `value_changed` | no-op |
##
## `on_update` carries no literal — it reads the registered default the matching
## `bind` declared — so with no registry there is nothing it could apply, and
## applying `null` is exactly the failure the absent path exists to avoid. Its
## owners each declare the same default on their member (`var deadzone_width:
## float = DEADZONE_WIDTH_DEFAULT`), so the no-op leaves the code default
## standing. `bind_update` DOES carry the literal, so it applies it.
##
## `bind` is the one verb whose absent answer is not the whole story: the
## declaration it could not deliver is QUEUED and replayed the moment a port
## resolves (`_deferred` below). Without that, an owner that registers at CLASS
## LOAD — which every ADR-0068 R2 owner does — loses its slugs outright whenever the
## engine loads its script during the autoload pass, when no autoload is in the tree
## yet.
##
## Registration through this port stays visible to ADR-0068 R6's codemod:
## `tools/materialize_tunables.py`'s `CALLS` table recognises `TunePort.bind` and
## `TunePort.bind_update` beside the direct spellings. That table is a hardcoded
## list of call names, so a façade it has not been taught goes QUIET rather than
## red — the companion-change rule ADR-0151 set.

## Resolved singleton, or `null`. Cached because `get_value` is called from hot
## getters and a per-call `get_node_or_null` + `has_method` is not free. Never
## caches a NEGATIVE result: the port can appear later (the autoload is added
## after this class is first touched by a `_static_init`), and it can be replaced
## between tests.
static var _port: Node = null


## The live registry node, or `null` when this addon is installed somewhere the
## host script is not registered.
##
## Two rejections, not one. `null` is the ordinary absent case. A node that
## resolves but has no `get_value` is the EDITOR case: a non-`@tool` autoload is
## instantiated in the editor as a placeholder that answers to the name and
## carries none of the script's methods, so a bare null-check would sail past it
## and call into nothing. `has_method` is the test that separates them, and it is
## why every consumer's `Engine.is_editor_hint()` guard is now belt-and-braces
## rather than the only thing standing between a `@tool` script and a crash.
static func _resolve() -> Node:
	if _port != null and is_instance_valid(_port):
		return _port
	var loop := Engine.get_main_loop()
	if loop == null or not (loop is SceneTree):
		return null
	var root: Window = (loop as SceneTree).root
	if root == null:
		return null
	var n := root.get_node_or_null(^"Tune")
	if n == null or not n.has_method(&"get_value"):
		return null
	_port = n
	# Cached FIRST, so the replay below (which calls back into the registry, not
	# through this port) cannot re-enter this function.
	_flush_deferred(n)
	return n


## Declarations the port could not deliver because it had not resolved yet,
## replayed in arrival order the instant it does (`_resolve`). Slug -> the four
## `bind` arguments, first-write-wins, which is the registry's own rule for a
## slug bound twice.
##
## 🔴 **THIS IS THE ENGINE'S BOOT ORDER, NOT A RACE.** Godot builds every autoload
## in one pass and adds them to the tree in a SECOND one (`main.cpp`,
## *"//defer so references are all valid on _ready()"*). Loading an autoload's
## script loads everything that script's dependency chain names — for this project
## that chain reaches `ExMateriaBattlefield`, whose 20 `preload`s pull in eight
## owners that register at class load (ADR-0068 R2). Every one of those
## `_static_init`s therefore runs while `/root` still has NO CHILDREN: `_resolve()`
## answers null (correctly — the node is not in the tree), and before this queue
## existed the declaration was simply DROPPED. It is silent by construction, because
## an absent port is a supported state and `bind` has to keep answering with the
## caller's literal.
##
## What it cost, measured on `GambitBattle.tscn`: **78 slugs across 8 owners** —
## every `camera.*`, `cursor.*`, `tile.*`, `map.water_waves` and the sprite-rig debug
## knobs — never registered at all, so the dashboard could not enumerate them, a
## scrub reached nothing, and each owner's own `_ready` then tripped the R3/R5
## asserts against its own slugs (`get_value(camera.free_camera_enabled)` fired
## 8,888 times in one 60-second run).
##
## Deferring is the ONE fix that does not make an owner care when it was loaded:
## registration stays at class load, `_resolve` stays a tree lookup, and the
## declaration lands the moment there is somewhere to put it. It is the same
## order-independence the registry already grants the other half of a slug — an
## override may legitimately precede its declaration, and `bind` coalesces
## whichever arrives second.
static var _deferred: Array[Dictionary] = []


## Remember a declaration for replay. Only `bind` defers: it is the verb a
## `_static_init` can call (it needs no instance), and it is the whole declaration.
## `bind_update` and `on_update` take an OWNER NODE, so they cannot run before the
## tree exists — and a subscription is not replayable anyway, because the owner it
## is scoped to may be gone by the time the port appears.
static func _defer(slug: String, literal: Variant, meta: Dictionary, persist: int) -> void:
	for d in _deferred:
		if d["slug"] == slug:
			return
	_deferred.append({"slug": slug, "literal": literal, "meta": meta, "persist": persist})


## Replay every deferred declaration onto the registry, once. Cleared BEFORE the
## replay so a `bind` re-entered from inside it cannot double-register.
static func _flush_deferred(p: Node) -> void:
	if _deferred.is_empty():
		return
	var pending := _deferred
	_deferred = []
	for d in pending:
		p.bind(d["slug"], d["literal"], d["meta"], d["persist"])


## Test seam: how many declarations are still waiting for a port. A test that
## manufactures the absent state reads this to prove the drop was RECORDED rather
## than swallowed — 0 here and 0 in the registry are the same picture otherwise.
static func deferred_count() -> int:
	return _deferred.size()


## Test seam: forget the cached resolution so the next call re-resolves.
##
## The cache is keyed on `is_instance_valid`, which is a question about the OBJECT
## and not about the LOOKUP — so a node that has been renamed, reparented, or
## queued for free is still "valid" and the cache still answers with it. Every one
## of those is a state in which `_resolve()` would now fail, and a test that wants
## to observe the absent path has to say so.
static func _forget_port() -> void:
	_port = null


## Attach `slug` to exactly one `literal` (ADR-0068 R2). Returns the coalesced
## value, which is `literal` itself when the port is absent — a caller seeding a
## static-var home gets a usable number either way. An absent call is not a lost
## one: the declaration is queued (`_deferred`) and lands as soon as a port
## resolves, so a `_static_init` that ran before the registry was in the tree still
## ends up registered.
##
## ⚠️ `persist: int = -1` MIRRORS the registry's own `_PERSIST_UNSPEC`, which is
## private to it and so cannot be named from here. An addon cannot reach a host
## script's constants, which is the same wall this whole class exists because of;
## what it costs is that a change to that sentinel makes this default mean
## something else, silently. No call site in the tree passes it — it is here so
## the signature forwards rather than truncates.
static func bind(slug: String, literal: Variant, meta: Dictionary = {},
		persist: int = -1) -> Variant:
	var p := _resolve()
	if p == null:
		_defer(slug, literal, meta, persist)
		return literal
	return p.bind(slug, literal, meta, persist)


## Whether `slug` has been declared on the live registry — `false` when no port resolves.
##
## 🔴 THIS EXISTS BECAUSE A REGISTRY CAN BE WIPED MID-SESSION AND `get_value` ASSERTS.
## `Tune.reset()` does `_registry.clear()`, which drops the DECLARATIONS, and R5's
## pull-read asserts a prior `bind`. An owner whose `_static_init` bound at class load is
## therefore not safe for the rest of the process: anything that resets the registry
## un-declares its slugs and the next read throws `get_value(...) before its bind`
## followed by `Invalid call. Nonexistent 'bool' constructor` — the type default of a
## failed read being constructed from `null`.
##
## `src/debug/DebugConfig.gd`'s `_dbg_get` has always guarded against exactly this
## (`if not Tune.is_registered(slug): Tune.bind(...)`), and `Tune.is_registered`'s own
## docstring names the shape: *"For a use-site that must register-once then `get_value` (a
## hot getter whose default lives at the call …): guard the one-time `bind` with this so
## the get_stack cost is paid once, not per read."* An addon reading through this port
## could not express that guard until now, and #1218 shipped a static-only owner without
## it — 20+ tunable tests went THREW on `debug.particle_debug_enabled`, found by the first
## full-suite run of the sequence and fixed at #658's commit.
static func is_registered(slug: String) -> bool:
	var p := _resolve()
	if p == null:
		return false
	return bool(p.is_registered(slug))


## The PULL-read (ADR-0068 R5). `fallback` is the arity this port adds over the
## singleton's own signature and it is not optional: without the registry there
## is no default to coalesce, and every call site in the tree already holds the
## same constant it passed to the matching `bind`.
static func get_value(slug: String, fallback: Variant) -> Variant:
	var p := _resolve()
	if p == null:
		return fallback
	return p.get_value(slug)


## Subscribe `owner` to `slug`: apply now and on every change (ADR-0068 R3).
## A no-op without the port — see the class docstring's table.
static func on_update(owner: Node, slug: String, apply: Callable) -> void:
	var p := _resolve()
	if p == null:
		return
	p.on_update(owner, slug, apply)


## `bind` + one paired `on_update` (ADR-0068 R3.5). Without the port it still
## applies `literal` once, because the literal is right here at the call.
static func bind_update(owner: Node, slug: String, literal: Variant, apply: Callable,
		meta: Dictionary = {}, persist: int = -1) -> void:
	var p := _resolve()
	if p == null:
		apply.call(literal)
		return
	p.bind_update(owner, slug, literal, apply, meta, persist)


## Write an override for `slug` and notify its subscribers. No-op without the
## port: nothing is listening and there is nowhere to persist it.
static func set_value(slug: String, value: Variant) -> void:
	var p := _resolve()
	if p == null:
		return
	p.set_value(slug, value)


## Connect `handler(slug, value)` to EVERY registry write — the whole-signal
## subscription, for a consumer that fans one change out to many live objects.
## The one member a static façade cannot forward as a property, so it is a verb
## (ADR-0175 dec. 2 named this shape). Returns whether it connected, so a caller
## can tell "bridged" from "no registry" without re-resolving.
static func on_any_change(handler: Callable) -> bool:
	var p := _resolve()
	if p == null:
		return false
	p.value_changed.connect(handler)
	return true
