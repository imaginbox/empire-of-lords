extends SceneTree
## Chat driver: connect, create a VS match, send a chat message, verify the
## message comes back (server relays it to the party). Prints CHAT_OK on success.

var server_url := "ws://127.0.0.1:9080"
var started := false
var created := false
var sent := false
var received := false
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
			print("CHAT no LanNet")
			quit(1)
			return true
		lan.connect("connected", Callable(self, "_on_connected"))
		lan.connect("chat_message", Callable(self, "_on_chat"))
		lan.connect("match_list_changed", Callable(self, "_on_list"))
		lan.set_player_name("Testeur")
		var err: int = int(lan.call("connect_to_server"))
		print("CHAT connect err=", err)
		return false
	if received:
		print("CHAT_OK")
		quit(0)
		return true
	if t > 20.0:
		print("CHAT_TIMEOUT")
		quit(1)
		return true
	return false


func _on_connected() -> void:
	print("CHAT connected")
	if not created:
		created = true
		lan.call("create_match", "Partie chat", "vs")
		print("CHAT match created (req sent)")


func _on_list(list: Array) -> void:
	if not sent:
		for m in list:
			if m.get("host") == int(lan.call("my_id")) and m.get("status") == "waiting":
				sent = true
				lan.call("send_chat", "Bonjour tout le monde !")
				print("CHAT message sent")
				return


func _on_chat(sender: String, text: String) -> void:
	print("CHAT recv from=", sender, " text=", text)
	received = true
