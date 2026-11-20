class_name PopupTextContainer
extends Control

@export var popup_text: PackedScene
@export var fade_time: float = 2.0


func show_popup_text(text: String, color: Color = Color.WHITE) -> void:
	var new_text: Label = popup_text.instantiate()
	new_text.text = text
	if new_text.label_settings != null:
		var custom_label_settings: LabelSettings = new_text.label_settings.duplicate()
		custom_label_settings.font_color = color
		new_text.label_settings = custom_label_settings
	else:
		new_text.modulate = color
	add_child(new_text)
	
	get_tree().create_timer(fade_time).timeout.connect(func() -> void: 
			if is_instance_valid(new_text):
				new_text.queue_free()
	)
