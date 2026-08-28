extends SceneTree
## VS dedicated waiting-room driver (headless).
## Reproduit le flux du lobby : créer/joindre une partie puis BASCULER vers
## Room.tscn. Vérifie que la salle affiche le roster et que le démarrage auto
## fait passer à Multiplayer.
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
var reported := false
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
			print("DRIVER no LanNet")
			quit(1)
			return true
		lan.connect("connected", Callable(self, "_on_connected"))
		lan.connect("game_started", Callable(self, "_on_game_start"))
		lan.call("connect_to_server")
		return false
	if role == "create" and created and not went_room and t >= 1.2:
		went_room = true
		change_scene_to_file("res://scenes/Room.tscn")
		print("DRIVER(create) -> Room.tscn")
	if role == "join" and joined and not went_room and t >= 1.2:
		went_room = true
		change_scene_to_file("res://scenes/Room.tscn")
		print("DRIVER(join) -> Room.tscn")
	if role == "create" and created and not set_ready_done and t >= 2.0:
		set_ready_done = true
		lan.call("set_ready", true)
		print("DRIVER(create) ready at t=%.1f" % t)
	if role == "join" and joined and not set_ready_done and t >= 2.8:
		set_ready_done = true
		lan.call("set_ready", true)
		print("DRIVER(join) ready at t=%.1f" % t)
	if not reported and t >= 8.0:
		reported = true
		_report()
	if started_game and t >= 12.0:
		_report()
		print("DRIVER(%s) END" % role)
		quit(0)
		return true
	if t > 18.0:
		print("DRIVER(%s) TIMEOUT" % role)
		quit(1)
		return true
	return false


func _on_connected() -> void:
	print("DRIVER(%s) connected" % role)
	if role == "create":
		lan.call("create_match", "RoomTest", "vs", false)
		created = true
	elif role == "join":
		lan.call("join_match", join_id)
		joined = true


func _on_game_start(m: String) -> void:
	started_game = true
	print("DRIVER(%s) GAME STARTED mode=%s at t=%.1f" % [role, m, t])


func _report() -> void:
	var cur: Node = current_scene
	if cur == null:
		print("DRIVER(%s) scene=null" % role)
		return
	var sp: String = cur.get_script().resource_path if cur.get_script() != null else "?"
	print("DRIVER(%s) scene=%s" % [role, sp])
	if sp.ends_with("room.gd"):
		print("DRIVER(%s) room title='%s'" % [role, str(cur.get("_title").text if cur.get("_title") else "?" )])
		print("DRIVER(%s) room roster:\n%s" % [role, str(cur.get("_roster").text if cur.get("_roster") else "?")])
		print("DRIVER(%s) room in_match=%s" % [role, bool(cur.get("_in_match"))])
