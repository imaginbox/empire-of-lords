extends SceneTree
## Matchmaking driver: connects to the WebSocket server, creates a named match
## and (optionally) starts it when asked, then verifies game start + snapshot.

var server_url := "ws://127.0.0.1:9080"
var auto_start := false
var do_join := false
var do_tournament := false
var start_delay := 0.0
var want_start := false
var started := false
var created := false
var started_game := false
var _reported := false
var t := 0.0
var lan: Node = null


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--server-url="):
			server_url = a.trim_prefix("--server-url=")
		elif a == "--auto-start":
			auto_start = true
		elif a == "--join":
			do_join = true
		elif a == "--tournament":
			do_tournament = true
		elif a.begins_with("--start-delay="):
			start_delay = float(a.trim_prefix("--start-delay="))


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
		lan.connect("match_list_changed", Callable(self, "_on_list"))
		lan.connect("game_started", Callable(self, "_on_game_start"))
		lan.connect("connection_failed", Callable(self, "_on_fail"))
		var err: int = int(lan.call("connect_to_server"))
		print("DRIVER connect err=", err)
		return false
	if started_game and t > 14.0:
		_report_snap()
		print("DRIVER END")
		quit(0)
		return true
	if want_start and t >= start_delay:
		want_start = false
		lan.call("start_match")
		print("DRIVER start sent at t=", t)
	if started_game and t >= 4.0 and not _reported:
		_reported = true
		_report_snap()
	return false


func _report_snap() -> void:
	var cur: Node = current_scene
	if cur == null:
		print("DRIVER scene=null")
		return
	var sp: String = ""
	if cur.get_script() != null:
		sp = cur.get_script().resource_path
	if sp.ends_with("multiplayer_main.gd"):
		var cns: Dictionary = cur.get("_city_nodes")
		print("DRIVER is_host=", bool(cur.get("_is_host")),
			" has_snap=", bool(cur.get("_has_snap")),
			" city_nodes=", cns.size())


func _on_connected() -> void:
	print("DRIVER connected id=", int(lan.call("my_id")))
	if do_tournament:
		if not created:
			created = true
			lan.call("join_tournament")
			print("DRIVER joined tournament (req sent)")
		return
	if do_join:
		return  # wait for the list, then join
	if not created:
		created = true
		lan.call("create_match", "Partie de %d" % int(lan.call("my_id")), "vs")
		print("DRIVER match created (req sent)")


func _on_list(list: Array) -> void:
	var brief: Array = []
	for m in list:
		brief.append({"id": m.get("id"), "name": m.get("name"), "mode": m.get("mode"),
			"n": (m.get("players") as Array).size(), "status": m.get("status")})
	print("DRIVER list=", str(brief))
	if do_join:
		if not created:
			for m in list:
				if m.get("status") == "waiting":
					lan.call("join_match", int(m.get("id")))
					created = true
					print("DRIVER join sent for match ", m.get("id"))
					return
		return
	if auto_start:
		for m in list:
			if m.get("host") == int(lan.call("my_id")) and m.get("status") == "waiting":
				want_start = true
				auto_start = false


func _on_game_start(m: String) -> void:
	print("DRIVER game_started mode=", m)
	started_game = true
	change_scene_to_file("res://scenes/Multiplayer.tscn")


func _on_fail() -> void:
	print("DRIVER connection_failed")
