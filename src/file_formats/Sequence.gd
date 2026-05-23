class_name Sequence

var seq_parts: Array[SeqPart] = []
var seq_name: String = ""

var length: int = 0 # num bytes

func duplicate() -> Sequence:
	var new_sequence: Sequence = Sequence.new()
	new_sequence.seq_name = seq_name
	new_sequence.seq_parts = seq_parts.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	return new_sequence


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
