extends SceneTree
## VS leave driver: verifies that after a match the server stops sending game
## RPCs to /root/Main once the client returns to the Lobby (no "Main not found").
##   A: --create  ;  B: --join=ID

var server_url := "ws://127.0.0.1:9080"
var role := ""
var join_id := -1
var started := false
var created := false
var joined := false
var set_ready_done := false
var went_room := false
var started_game := false
var left := false
var t := 0.0
var lan: Node = null


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--server-url="):
			server_url = a.trim_prefix("--server-url=")
		elif a == "--create":
			role = "create"
		elif a.begins_with("--join="):
			join_id = int(a.split("=", false)[1])
			role = "join"


func _process(delta: float) -> bool:
	t += delta
	if not started:
		started = true
		lan = root.get_node_or_null("LanNet")
		if lan == null:
			print("DRIVER no LanNet"); quit(1); return true
		lan.connect("connected", Callable(self, "_on_connected"))
		lan.connect("game_started", Callable(self, "_on_game_start"))
		lan.call("connect_to_server")
		return false
	if role == "create" and created and not went_room and t >= 1.2:
		went_room = true
		change_scene_to_file("res://scenes/Room.tscn")
	if role == "join" and joined and not went_room and t >= 1.2:
		went_room = true
		change_scene_to_file("res://scenes/Room.tscn")
	if role == "create" and created and not set_ready_done and t >= 2.0:
		set_ready_done = true
		lan.call("set_ready", true)
	if role == "join" and joined and not set_ready_done and t >= 2.8:
		set_ready_done = true
		lan.call("set_ready", true)
	# apres le debut de partie, le create retourne au lobby apres ~5s
	if started_game and role == "create" and not left and t >= 5.5:
		left = true
		var cur: Node = current_scene
		if cur != null and cur.has_method("_leave_game"):
			print("DRIVER(create) retour au lobby via _leave_game")
			cur.call("_leave_game")
		else:
			print("DRIVER(create) pas de _leave_game sur %s" % str(cur))
	if t >= 11.0:
		print("DRIVER(%s) END" % role)
		quit(0); return true
	if t > 16.0:
		print("DRIVER(%s) TIMEOUT" % role)
		quit(1); return true
	return false


func _on_connected() -> void:
	if role == "create":
		lan.call("create_match", "LeaveTest", "vs", false)
		created = true
	elif role == "join":
		lan.call("join_match", join_id)
		joined = true


func _on_game_start(m: String) -> void:
	started_game = true
	print("DRIVER(%s) GAME STARTED mode=%s at t=%.1f" % [role, m, t])
	if not went_room and (created or joined):
		change_scene_to_file("res://scenes/Multiplayer.tscn")
