class_name FftEntd
extends Resource

# https://ffhacktics.com/wiki/ENTD

@export var entd_units: Array[FftEntdUnit] = []
var unit_data_length: int = 40

func _init(bytes: PackedByteArray) -> void:
	for idx: int in 16:
		var unit_bytes: PackedByteArray = bytes.slice(idx * unit_data_length, (idx + 1) * unit_data_length)
		if unit_bytes[0] != 0: # sprite_id = 0 are empty entries
			var new_entd_unit: FftEntdUnit = FftEntdUnit.new(unit_bytes)
			entd_units.append(new_entd_unit)


func get_units_data(rom_reader: RomReader) -> Array[UnitData]:
	var units_data: Array[UnitData] = []

	for entd_unit: FftEntdUnit in entd_units:
		units_data.append(entd_unit.get_unit_data(rom_reader))

	return units_data
