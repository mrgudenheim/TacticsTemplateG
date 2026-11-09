class_name Scenario
extends Resource

const SAVE_FOLDER: String = "scenarios/"
const FILE_SUFFIX: String = ".scenario.tres"
@export var unique_name: String = "unique_name"
@export var display_name: String = "display_name" # TODO add ui to set scenario name
@export var description: String = "description"

var is_loaded: bool = false

@export var background_gradient_top: Color = Color.LIGHT_GRAY
@export var background_gradient_bottom: Color = Color.DARK_BLUE
@export var map_chunks: Array[MapChunk] = []
@export var deployment_zones: Array[PackedVector2Array] = [] # TODO what about locations with tiles at different hights?
@export var global_passive_effect_names: PackedStringArray = [] #  TODO add ui to add global passive effects

@export var units_data: Array[UnitData] = []
# TODO scenario victory conditions


static func lazy_init(new_unique_name: String) -> Scenario:
	var new_scenario: Scenario = Scenario.new()
	new_scenario.unique_name = new_unique_name

	return new_scenario


static func transform_units_data_tile_location(
	local_units_data: Array[UnitData], 
	terrain_tiles: Array[TerrainTile],
	scale: Vector2 = Vector2.ONE, 
	translation: Vector2 = Vector2.ZERO, 
	rotation_degrees: float = 0.0
) -> Array[UnitData]:
	var transformed_units_data: Array[UnitData] = local_units_data.duplicate_deep()

	var tiles_center: Vector2 = MapData.get_tiles_center(terrain_tiles)
	var tile_transform: Transform2D = MapData.get_transform2d(
		tiles_center, 
		scale,
		translation,
		rotation_degrees,
	)

	for unit_data: UnitData in transformed_units_data:
		var total_location: Vector2 = tile_transform * Vector2(unit_data.tile_position.x, unit_data.tile_position.z)
		unit_data.tile_position = Vector3i(roundi(total_location.x), unit_data.tile_position.y, roundi(total_location.y))

		# TODO fix unit facing?
	
	return transformed_units_data


func export(save_path: String = "") -> Error:
	if save_path == "":
		save_path = GameData.external_data_paths["EXPORT_PATH"]
	var scenario_dir: String = save_path.path_join(SAVE_FOLDER)
	DirAccess.make_dir_recursive_absolute(scenario_dir)
	var scenario_file_path: String = scenario_dir.path_join(unique_name + FILE_SUFFIX)
	var error: Error = ResourceSaver.save(self, scenario_file_path)
	if error != OK:
		push_error("Error saving scenario: " + error_string(error))
	return error