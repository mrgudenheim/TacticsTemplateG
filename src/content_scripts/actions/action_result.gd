class_name ActionResult
extends RefCounted

# stored for each target (and user) of an action

@export var animation_id: int # take damage, heal, evade, shield, etc.
@export var vfx_id: int
@export var stat_change: int
@export var stat_change_overflow: int # ex. hp gained above hp_max
@export var stat_change_underflow: int # ex. hp lost below hp_min
@export var status_change: PackedStringArray # unique names of statuses? add and remove?
@export var text_popup: PackedStringArray # damage number, +1 PA, Guarded, Broken, Miss, etc. TODO should this just be calculated based on the other data stored in this instance?
# TODO should there just be an EffectResult structure?

# used for debugging?
var unit: Unit
var action_instance: ActionInstance


# https://ffhacktics.com/wiki/Battle_Stats#Battle_Action_Data
# -Hit/Miss Type
#	-Hit
#	-Critical Hit
# 	-Catch
# 	-Miss
# 	-Nullified (element)
# 	-Guarded
# -Item Lost--Potions/Break/Steal/Draw Out
# -HP Damage Halfword
# -HP Healing Halfword
# -MP Damage Halfword
# -MP Healing Halfword
# -Gil Stolen/Lost
# -Reaction ID
# -Special Effect
# 	-+/-1 Level
# 	-Switch Team
# 	-Poached
# 	-Steal Item
# 	-Break Item
# 	-Malboro (moldball virus)
# 	-Golem
# 	-Knockback?
# -SP Change Byte
# -CT Change Byte
# -PA Change Byte
# -MA Change Byte
# -Br Change Byte
# -Fa Change Byte
# -Status Change?
# -Equipment Destroyed Slot
# 	-Remove Helmet
# 	-Remove Armor
# 	-Remove Accessory
# 	-Remove Right Hand Weapon
# 	-Remove Right Hand Shield
# 	-Remove Left Hand Weapon
# 	-Remove Left Hand Shield
# -Stolen Item ID (Used for inventory increment?)
# -Attack's Statuses Add
# -Attack's Statuses Removal
# -Attack Type: damage/recovery, mp/hp - used for setting text color?
# -Last Received Attack [for Counter Magic] or weapon [for Catch] Halfword - Data for reactions, varies with Ability ID (could be MP to absorb, Excendent heal to distribute etc...
# -EXP Change from Steal EXP
# -Move-JP Up amount/JP Stolen?