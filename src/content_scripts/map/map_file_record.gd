class_name MapFileRecord
extends Resource
	
@export var record_data: PackedByteArray = []
var arrangement: int = 0
var time_weather: int = 0
var file_type_indicator: int = 0
var file_sector: int = 0
@export var file_name: String

func _init(record_bytes: PackedByteArray = [], rom_reader: RomReader = null) -> void:
	if record_bytes.is_empty():
		return
	
	record_data = record_bytes
	arrangement = record_bytes.decode_u8(2)
	time_weather = record_bytes.decode_u8(3)
	file_type_indicator = record_bytes.decode_u16(4)
	file_sector = record_bytes.decode_u32(8)
	file_name = rom_reader.lba_to_file_name[file_sector]
