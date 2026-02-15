class_name EquipmentSlot
extends Resource

@export var equipment_slot_name: String = "[Equipment Slot]"
@export var slot_types: Array[ItemData.SlotType] = []
@export var item_unique_name: String
var item: ItemData:
	get: return RomReader.items[item_unique_name]


static func create_from_dictionary(property_dict: Dictionary) -> EquipmentSlot:
	var new_equipment_slot: EquipmentSlot = EquipmentSlot.new()
	for property_name: String in property_dict.keys():
		if property_name == "slot_types":
			var array: Array = property_dict[property_name]
			var new_slot_types: Array[ItemData.SlotType] = []
			for type: String in array:
				new_slot_types.append(ItemData.SlotType[type])
			new_equipment_slot.set(property_name, new_slot_types)
		else:
			new_equipment_slot.set(property_name, property_dict[property_name])

	new_equipment_slot.emit_changed()
	return new_equipment_slot


func _init(new_name: String = "", new_slot_types: Array[ItemData.SlotType] = [], new_item_unique_name: String = "") -> void:
	equipment_slot_name = new_name
	slot_types = new_slot_types
	item_unique_name = new_item_unique_name


func _to_string() -> String:
	return equipment_slot_name + ": " + item.display_name


func to_dictionary() -> Dictionary:
	var properties_to_exclude: PackedStringArray = [
		"RefCounted",
		"Resource",
		"resource_local_to_scene",
		"resource_path",
		"resource_name",
		"resource_scene_unique_id",
		"script",
	]
	
	return Utilities.object_properties_to_dictionary(self, properties_to_exclude)
