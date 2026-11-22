class_name FftStatusImporter
extends RefCounted


static func create_from_bytes(status_effect_bytes: PackedByteArray, rom_reader: RomReader) -> StatusEffect:
	var status_effect: StatusEffect = StatusEffect.new()
	status_effect.byte_00 = status_effect_bytes.decode_u8(0)
	status_effect.byte_01 = status_effect_bytes.decode_u8(1)
	status_effect.order = status_effect_bytes.decode_u8(2)
	status_effect.duration = status_effect_bytes.decode_u8(3)
	status_effect.checks_01 = status_effect_bytes.decode_u8(4)
	status_effect.checks_02 = status_effect_bytes.decode_u8(5)
	status_effect.status_cancels_flags = status_effect_bytes.slice(6, 11)
	status_effect.status_cant_stack_flags = status_effect_bytes.slice(11, 16)
	status_effect.removed_on_damaged = status_effect.checks_01 & 0x08 == 0x08 # confusion, transparent, charm, sleep
	status_effect.duration_icons = rom_reader.battle_bin_data.status_counter_rects.duplicate()

	if status_effect.duration == 0:
		status_effect.duration_type = StatusEffect.DurationType.INDEFINITE

	return status_effect


# Called after all StatusEffects have been initialized since this indexes into the complete array.
static func resolve_status_flags(status_effect: StatusEffect, status_effects: Array[StatusEffect]) -> void:
	status_effect.status_cancels = decode_status_id_array(status_effect.status_cancels_flags, status_effects)
	status_effect.status_cant_stack = decode_status_id_array(status_effect.status_cant_stack_flags, status_effects)


static func decode_status_id_array(
	status_bitflags: PackedByteArray,
	status_effects: Array[StatusEffect]
) -> PackedStringArray:
	var status_array: PackedStringArray = []

	for byte_idx: int in status_bitflags.size():
		var byte_value: int = status_bitflags.decode_u8(byte_idx)
		for bit_idx: int in range(7, -1, -1):
			if (byte_value & (1 << bit_idx)) != 0:
				var status_index: int = (7 - bit_idx) + (byte_idx * 8)
				status_array.append(status_effects[status_index].unique_name)

	return status_array
