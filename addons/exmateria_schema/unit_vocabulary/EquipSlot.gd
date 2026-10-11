extends RefCounted

## **Which of a unit's five equipment slots** — right hand, left hand, head,
## body, accessory. The LAYOUT a unit's equipment dictionary is keyed by, and
## nothing about what fills it.
##
## ADR-0118 dec. 1's **twelfth** schema row, admitted by
## [ADR-0294](../../../docs/adr/0294-the-catalogues-progression-debt-is-a-vocabulary-and-the-kernel-is-where-a-value-set-lives.md)
## dec. 2. The row's producer is the `rules` tier (`UnitProgression` holds the
## dictionary this keys, `items/EquipCandidates.gd` matches on the slot names),
## and its consumers are `Character Catalogue`
## (`addons/exmateria_catalogue/identity/Character.gd` seeds all five from an ENTD
## slot and reads them back for the save form), `UI`
## (`src/ui3/detail/`, `src/ui3/formation/`) and `Battle` (`src/units/Unit.gd`,
## `src/gpu/`).
##
## 🔴 THE OBJECTION IN THIS FILE'S OWN PREVIOUS DOCSTRING WAS ABOUT A DIFFERENT
## DESTINATION, AND IT IS STILL GOOD ABOUT THAT ONE. #1123 lifted this enum out
## of `UnitProgression` and deliberately LEFT IT IN THE ALMANAC, because
## `exmateria_catalogue/plugin.cfg` declares `deps="exmateria_almanac …"` and
## carrying the vocabulary out WITH the state would have made
## `EquipCandidates`' four-arm match a reach INTO the catalogue — almanac →
## catalogue → almanac. That argument prices a move UP into a consumer. This is a
## move DOWN into the kernel, which every one of those packages already depends
## on, so it inverts nothing: `EquipCandidates` now reaches the kernel, which is
## ADR-0202 dec. 2's free direction, and the catalogue reaches the kernel too.
##
## 🔴 `abilities/AbilitySlot.gd` DID NOT COME, AND THE MEASUREMENT IS WHY.
## Outside `addons/exmateria_almanac` and `tests/`, **zero** files name it. It
## crosses no boundary, so it realises no schema row and ADR-0139 dec. 3's
## admission gate refuses it. It is the almanac's and stays there — the two files
## were lifted together by #1123 and they are not one decision.
##
## THE CALL SITES DID NOT MOVE. `UnitProgression` re-exports this as
## `const EquipSlot = EquipSlotVocab.Slot`, so every `UnitProgression.EquipSlot.*`
## site in `src/` is untouched and the re-export is usable as a TYPE annotation
## exactly as the inline enum was — which is why the five `slot: EquipSlot`
## signatures and the `equipment_changed` signal still compile. Probed on the fork
## before #1123's refactor, and unchanged by crossing a root.

enum Slot { RIGHT_HAND, LEFT_HAND, HEAD, BODY, ACCESSORY }
