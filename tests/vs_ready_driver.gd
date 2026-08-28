extends SceneTree
## VS ready-flow driver (headless).
## Usage (2 processes + a server on :9080):
##   A: --script res://tests/vs_ready_driver.gd -- --create --server-url=ws://127.0.0.1:9080
##   B: --script res://tests/vs_ready_driver.gd -- --join <ID> --server-url=ws://127.0.0.1:9080
## Both set "ready"; the server must auto-start the match, send snapshots,
## and the driver verifies the smaller VS map + near-center spawn.

var server_url := "ws://127.0.0.1:9080"
var role := ""            # "create" | "join"
var join_id := -1
var started := false
var created := false
var joined := false
var set_ready_done := false
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
		elif a.begins_with("--join"):
			var parts: PackedStringArray = a.split("=", false)
			join_id = int(parts[1])
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
		lan.connect("match_list_changed", Callable(self, "_on_list"))
		lan.connect("game_started", Callable(self, "_on_game_start"))
		lan.connect("vs_eliminated", Callable(self, "_on_eliminated"))
		lan.call("connect_to_server")
		print("DRIVER(%s) connecting to %s" % [role, server_url])
		return false
	if role == "create" and created and not set_ready_done and t >= 1.6:
		set_ready_done = true
		lan.call("set_ready", true)
		print("DRIVER(%s) set_ready at t=%.1f" % [role, t])
	if role == "join" and joined and not set_ready_done and t >= 2.4:
		set_ready_done = true
		lan.call("set_ready", true)
		print("DRIVER(%s) set_ready at t=%.1f" % [role, t])
	if started_game and not reported and t >= 9.0:
		reported = true
		_report()
		print("DRIVER(%s) END" % role)
		quit(0)
		return true
	if started_game and t > 16.0:
		print("DRIVER(%s) TIMEOUT no report" % role)
		quit(1)
		return true
	return false


func _on_connected() -> void:
	print("DRIVER(%s) connected" % role)
	if role == "create":
		lan.call("create_match", "TestVS", "vs", false)
		created = true
		print("DRIVER(create) create_match sent")
	elif role == "join":
		lan.call("join_match", join_id)
		joined = true
		print("DRIVER(join) join_match %d sent" % join_id)


func _on_list(list: Array) -> void:
	if role == "create" and created and not started_game:
		# Find our match and report its ready/roster fields.
		for m in list:
			if str(m.get("name", "")) == "TestVS":
				var ready: Dictionary = m.get("ready", {})
				print("DRIVER(create) match=%s players=%s with_ai=%s ready=%s" % [
					m.get("id"), str(m.get("players")), m.get("with_ai"), str(ready)])


func _on_game_start(m: String) -> void:
	if started_game:
		return
	started_game = true
	print("DRIVER(%s) GAME STARTED mode=%s at t=%.1f" % [role, m, t])
	change_scene_to_file("res://scenes/Multiplayer.tscn")


func _on_eliminated() -> void:
	print("DRIVER(%s) ELIMINATED" % role)


func _report() -> void:
	var cur: Node = current_scene
	if cur == null:
		print("DRIVER(%s) scene=null" % role)
		return
	var cns: Dictionary = cur.get("_city_nodes") if cur.get("_city_nodes") != null else {}
	var has_cap: bool = bool(cur.get("_has_capital"))
	var cap: Vector2 = cur.get("_my_capital")
	var cap_dist: float = cap.length()
	var snap: Dictionary = cur.get("_snap") if cur.get("_snap") != null else {}
	var vs_over: bool = bool(snap.get("vs_over", false))
	var enemies := 0
	var players := 0
	for e in snap.get("cities", []):
		if int(e.get("owner", 0)) == 2:   # CityNode.OWNER_ENEMY
			enemies += 1
		elif int(e.get("owner", 0)) == 1: # CityNode.OWNER_PLAYER
			players += 1
	print("DRIVER(%s) city_nodes=%d enemies=%d players=%d has_capital=%s cap_dist=%.0f vs_over=%s" % [
		role, cns.size(), enemies, players, has_cap, cap_dist, vs_over])
	for e in snap.get("cities", []):
		if int(e.get("owner", 0)) == 1:
			print("DRIVER(%s)   PLAYER city '%s' id=%d ctrl=%d" % [role, e.get("name", "?"), int(e.get("id", 0)), int(e.get("controller", 0))])
