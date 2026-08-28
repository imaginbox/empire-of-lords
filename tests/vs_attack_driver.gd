extends SceneTree
## VS attack driver (headless): verifies that one player CAN attack another
## player's capital (free-for-all). After the match auto-starts, the create
## client selects its own capital as source and the opponent's capital as
## target, launches troops, and checks that the server ACCEPTS the army
## (no "friendly city" rejection).
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
var attacked := false
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
	if started_game and role == "create" and not attacked and t >= 6.0:
		if _do_attack():
			attacked = true
	if not reported and t >= 12.0:
		reported = true
		_report()
	if started_game and t >= 16.0:
		_report()
		print("DRIVER(%s) END" % role)
		quit(0); return true
	if t > 22.0:
		print("DRIVER(%s) TIMEOUT" % role)
		quit(1); return true
	return false


func _on_connected() -> void:
	if role == "create":
		lan.call("create_match", "AttackTest", "vs", false)
		created = true
	elif role == "join":
		lan.call("join_match", join_id)
		joined = true


func _on_game_start(m: String) -> void:
	started_game = true
	print("DRIVER(%s) GAME STARTED mode=%s at t=%.1f" % [role, m, t])
	if not went_room and (created or joined):
		change_scene_to_file("res://scenes/Multiplayer.tscn")


func _do_attack() -> bool:
	var cur: Node = current_scene
	if cur == null or cur.get("_snap") == null:
		return false
	var me: int = lan.my_id()
	var snap: Dictionary = cur.get("_snap")
	var my_city := -1
	var opp_city := -1
	var opp_name := "?"
	for e in snap.get("cities", []):
		if int(e.get("owner", 0)) == 1:   # OWNER_PLAYER
			if int(e.get("controller", 0)) == me:
				my_city = int(e.get("id", -1))
			else:
				opp_city = int(e.get("id", -1))
				opp_name = str(e.get("name", "?"))
	if my_city < 0 or opp_city < 0:
		return false
	cur.set("source_id", my_city)
	cur.set("target_id", opp_city)
	print("DRIVER(create) attacking '%s' (id=%d) from my city id=%d" % [opp_name, opp_city, my_city])
	cur.call("_send_launch", 300)
	print("DRIVER(create) launch sent")
	return true


func _report() -> void:
	var cur: Node = current_scene
	if cur == null or cur.get("_snap") == null:
		print("DRIVER(%s) scene/snap null" % role)
		return
	var snap: Dictionary = cur.get("_snap")
	var armies: Array = snap.get("armies", [])
	var me: int = lan.my_id()
	var my_cities := 0
	for e in snap.get("cities", []):
		if int(e.get("owner", 0)) == 1 and int(e.get("controller", 0)) == me:
			my_cities += 1
	print("DRIVER(%s) armies=%d my_cities=%d" % [role, armies.size(), my_cities])
