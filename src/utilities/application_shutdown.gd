extends Node
## Normal quit boundary. Never force exit while stopped audio is still owned.

signal shutdown_failed(message: String)
var shutting_down: bool = false
const DRAIN_TIMEOUT_MS: int = 5000

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().auto_accept_quit = false

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		request_quit()

func request_quit(exit_code: int = 0) -> void:
	if shutting_down:
		return
	shutting_down = true
	call_deferred("_shutdown", exit_code)

func _shutdown(exit_code: int) -> void:
	get_tree().paused = true
	var playbacks: Array[WeakRef] = []
	var players: Array[Node] = []
	_collect_players(get_tree().root, players)
	for player: Node in players:
		if player.has_stream_playback():
			playbacks.append(weakref(player.get_stream_playback()))
	# Free the effects sound autoload before its players: its own exit path joins the
	# audio scheduler and detaches native mixers under the audio lock, which it cannot do
	# once the players are already gone.
	var sfx: Node = get_node_or_null("/root/ExMateriaEffectSfx")
	if sfx != null:
		sfx.queue_free()
		await get_tree().process_frame
	for player in players:
		if is_instance_valid(player):
			player.stop()
			player.queue_free()
	players.clear()
	var deadline: int = Time.get_ticks_msec() + DRAIN_TIMEOUT_MS
	while _has_live_playback(playbacks):
		if Time.get_ticks_msec() >= deadline:
			var message: String = "Shutdown blocked: audio playback still retained after cleanup"
			push_error(message)
			shutdown_failed.emit(message)
			return
		await get_tree().process_frame
	print("APPLICATION_SHUTDOWN: drained")
	get_tree().quit(exit_code)

func _collect_players(node: Node, players: Array[Node]) -> void:
	if node is AudioStreamPlayer or node is AudioStreamPlayer2D or node is AudioStreamPlayer3D:
		players.append(node)
	for child: Node in node.get_children():
		_collect_players(child, players)

func _has_live_playback(playbacks: Array[WeakRef]) -> bool:
	for playback: WeakRef in playbacks:
		if playback.get_ref() != null:
			return true
	return false
