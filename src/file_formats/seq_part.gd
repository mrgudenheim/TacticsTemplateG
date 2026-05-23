class_name SeqPart

var opcode: String = "LoadFrameAndWait"
var opcode_name: String = "LoadFrameAndWait"
var parameters: Array[int] = []

var isOpcode: bool = false:
	get:
		return opcode != "LoadFrameAndWait"

var length: int = 0:
	get:
		var length_temp: int = parameters.size()
		if isOpcode:
			length_temp += 2
		return length_temp

func _to_string() -> String:
	var total_string: String = opcode_name + "("
	var parameters_string: PackedStringArray = []
	for parameter: int in parameters:
		parameters_string.append(str(parameter))
	return total_string + ",".join(parameters_string) + ")"


func to_string_hex() -> String:
	var total_string: String = opcode_name + "("
	var parameters_string: PackedStringArray = []
	for parameter: int in parameters:
		parameters_string.append("0x%02x" % [parameter if parameter >=0 else parameter + 256])
	return total_string + ",".join(parameters_string) + ")"
