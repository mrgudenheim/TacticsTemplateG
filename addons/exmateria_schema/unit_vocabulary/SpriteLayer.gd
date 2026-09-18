extends RefCounted

## **Which of a unit sprite's three composed layers** — the body, the weapon, the
## effect.
##
## Part of ADR-0118 dec. 1's **tenth** schema row — the unit-sprite vocabulary —
## admitted by
## [ADR-0215](../../../docs/adr/0215-the-sprite-rig-seam-is-a-scene-a-vocabulary-and-a-content-port-and-two-thirds-of-its-interface-belongs-to-two-adapters.md)
## dec. 2 and named by ADR-0217 dec. 7. A unit sprite is one mesh with three
## sampled layers composed on it (ADR-0019); this is the selector every producer
## and every consumer of a layer has to spell, 50 uses, and it used to be nested
## in an 888-line Node (`SpriteLayerManager`). The manager keeps its class name
## and all of its behaviour — the shader parameter pushes, the frame loads, the
## reversion flag; only the value set moved.
##
## 🔴 `SpriteLayer`, NOT THE BARE WORD `Layer`, AND THE COLLISION IS NOT
## HYPOTHETICAL. `colour_model/ColorStack.gd` in this same addon declares
## `class Layer extends RefCounted`, so the bare spelling would have collided
## inside the destination. ADR-0212's whole argument is that generic English is
## the hazard, and `ExMateriaSchema.Layer` tells a stranger nothing about which
## kind of layer it means.

## The three composed sprite layers. 🔴 THE INTEGER VALUES ARE WRITTEN OUT:
## `tools/parse_weapon_wep1_anim_ids.py` hardcodes `WEP1_LAYER = 1` against this
## ordering from Python, where no import can follow a rename, so a silent
## renumbering here is a wrong-layer bug over there with nothing red in between.
enum Kind {
	TYPE1 = 0,  ## The base character body.
	WEP1 = 1,   ## The weapon.
	EFF1 = 2,   ## The effect overlay.
}
