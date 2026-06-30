class_name JobSelectControl
extends Container

@export var job_select_button_container: Container
@export var job_select_button_scene: PackedScene
var job_select_buttons: Array[JobSelectButton]


func populate_list() -> void:
	for job_name: String in GameData.job_paths.keys():
		var job_data: JobData = GameData.get_job(job_name)
		var job_select_button: JobSelectButton = job_select_button_scene.instantiate()
		job_select_button.job_data = job_data
		job_select_button_container.add_child(job_select_button)
	
	job_select_buttons.assign(job_select_button_container.get_children())


func filter_list(jobs_to_show: Array[JobData]) -> void:
	for job_select_button: JobSelectButton in job_select_buttons:
		if jobs_to_show.has(job_select_button.job_data):
			job_select_button.visible = true
		else:
			job_select_button.visible = false
