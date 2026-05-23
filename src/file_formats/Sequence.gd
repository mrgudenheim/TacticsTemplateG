class_name Sequence
extends Resource

@export var seq_parts: Array[SeqPart] = []
@export var seq_name: String = ""
@export var length: int = 0 # num bytes


func update_length() -> void:
	var sum: int = 0
	for seq_part: SeqPart in seq_parts:
		sum += seq_part.length
	length = sum # num bytes


func _to_string() -> String:
	var string_list:PackedStringArray = []
	for part: SeqPart in seq_parts:
		string_list.append(part.to_string())
	
	return ", ".join(string_list)


func to_string_hex(delimiter: String) -> String:
	var string_list: PackedStringArray = []
	for part: SeqPart in seq_parts:
		string_list.append(part.to_string_hex())
	
	return delimiter.join(string_list)
