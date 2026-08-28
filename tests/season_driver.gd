extends SceneTree
## Season-winner driver: connect, join the tournament, and STAY connected long
## enough for a short season to end, so the server announces the winner.

var server_url := "ws://127.0.0.1:9080"
var started := false
var t := 0.0
var lan: Node = null


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--server-url="):
			server_url = a.trim_prefix("--server-url=")


func _process(delta: float) -> bool:
	t += delta
	if not started:
		started = true
		lan = root.get_node_or_null("LanNet")
		if lan == null:
			print("WAIT no LanNet")
			quit(1)
			return true
		lan.connect("connected", Callable(self, "_on_connected"))
		lan.set_player_name("VainqueurTest")
		lan.call("connect_to_server")
		return false
	if t > 20.0:
		print("WAIT_END")
		quit(0)
		return true
	return false


func _on_connected() -> void:
	print("WAIT connected")
	lan.call("join_tournament")
