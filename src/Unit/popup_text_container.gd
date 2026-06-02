class_name PopupTextContainer
extends Control

@export var popup_text: PackedScene
@export var fade_time: float = 2.0


func show_popup_text(text: String) -> void:
	var new_text: Label = popup_text.instantiate()
	new_text.text = text
	add_child(new_text)
	
	await get_tree().create_timer(fade_time).timeout.connect(func() -> void: 
			if new_text != null:
				new_text.queue_free())
