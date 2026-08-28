extends SceneTree
## VS peace driver (headless): verifies the peace-time rules.
##   1) capitals are spread (not adjacent) with neutrals between
##   2) during peace, attacking the OPPONENT is blocked (no army)
##   3) during peace, attacking a NEUTRAL city is accepted (army appears)
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
# machine a etats du test
var test_step := 0
var test_done := false
var step_time := 0.0
var opp_attacked := false
var neutral_attacked := false


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
	if started_game and role == "create" and not test_done:
		_tick_test()
	if not reported and t >= 15.0:
		reported = true
		_report()
	if started_game and t >= 19.0:
		_report()
		print("DRIVER(%s) END" % role)
		quit(0); return true
	if t > 28.0:
		print("DRIVER(%s) TIMEOUT" % role)
		quit(1); return true
	return false


func _on_connected() -> void:
	if role == "create":
		lan.call("create_match", "PeaceTest", "vs", false)
		created = true
	elif role == "join":
		lan.call("join_match", join_id)
		joined = true


func _on_game_start(m: String) -> void:
	started_game = true
	print("DRIVER(%s) GAME STARTED mode=%s at t=%.1f" % [role, m, t])
	if not went_room and (created or joined):
		change_scene_to_file("res://scenes/Multiplayer.tscn")


func _my_capital() -> Dictionary:
	var me: int = lan.my_id()
	for e in current_scene.get("_snap")["cities"]:
		if int(e.get("owner", 0)) == 1 and int(e.get("controller", 0)) == me:
			return e
	return {}


func _tick_test() -> void:
	var cur: Node = current_scene
	if cur == null or cur.get("_snap") == null:
		return
	var snap: Dictionary = cur.get("_snap")
	var me: int = lan.my_id()
	if test_step == 0:
		# 1) trouve capitales + cite neutre la plus proche
		var my_cap := {}
		var opp_cap := {}
		var neutrals: Array = []
		for e in snap["cities"]:
			var own: int = int(e.get("owner", 0))
			if own == 1:
				if int(e.get("controller", 0)) == me:
					my_cap = e
				else:
					opp_cap = e
			elif own == 0:
				neutrals.append(e)
		if my_cap.is_empty() or opp_cap.is_empty() or neutrals.is_empty():
			return
		var dcap: float = Vector2(my_cap["x"], my_cap["y"]).distance_to(Vector2(opp_cap["x"], opp_cap["y"]))
		print("DRIVER(create) capital distance = %d px (attendu ~1900, neutres entre)" % int(dcap))
		print("DRIVER(create) neutrals disponibles = %d" % neutrals.size())
		var neutral := {}
		var best_d := INF
		for e in neutrals:
			var d: float = Vector2(my_cap["x"], my_cap["y"]).distance_to(Vector2(e["x"], e["y"]))
			if d < best_d:
				best_d = d
				neutral = e
		# 2) attaque de l'adversaire pendant la paix -> doit etre BLOQUEE
		cur.set("source_id", int(my_cap["id"]))
		cur.set("target_id", int(opp_cap["id"]))
		cur.call("_send_launch", 100)
		test_step = 1
		step_time = t
		print("DRIVER(create) attaque adverse envoyee (attendu: bloquee)")
	elif test_step == 1:
		if t < step_time + 2.0:
			return   # laisse le snapshot se diffuser
		var before: int = int(snap["armies"].size())
		print("DRIVER(create) armies apres attaque adverse = %d (attendu 0 = bloque)" % before)
		# 3) attaque d'une cite neutre pendant la paix -> doit etre ACCEPTEE
		var my_cap2 := {}
		var neutrals2: Array = []
		for e in snap["cities"]:
			var own: int = int(e.get("owner", 0))
			if own == 1 and int(e.get("controller", 0)) == me:
				my_cap2 = e
			elif own == 0:
				neutrals2.append(e)
		var neutral2 := {}
		var best_d2 := INF
		for e in neutrals2:
			var d: float = Vector2(my_cap2["x"], my_cap2["y"]).distance_to(Vector2(e["x"], e["y"]))
			if d < best_d2:
				best_d2 = d
				neutral2 = e
		cur.set("source_id", int(my_cap2["id"]))
		cur.set("target_id", int(neutral2["id"]))
		cur.call("_send_launch", 100)
		test_step = 2
		step_time = t
		print("DRIVER(create) attaque neutre envoyee (attendu: acceptee)")
	elif test_step == 2:
		if t < step_time + 2.0:
			return
		var n2: int = int(snap["armies"].size())
		print("DRIVER(create) armies apres attaque neutre = %d (attendu >0 = accepte)" % n2)
		test_done = true


func _report() -> void:
	var cur: Node = current_scene
	if cur == null or cur.get("_snap") == null:
		print("DRIVER(%s) scene/snap null" % role)
		return
	var snap: Dictionary = cur.get("_snap")
	print("DRIVER(%s) peace_left=%.1f war=%s armies=%d" % [role,
		float(snap.get("peace_left", 0.0)), bool(snap.get("war_declared", false)),
		int(snap.get("armies", []).size())])
