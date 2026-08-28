extends SceneTree
## Zone-UI driver: loads the REAL lobby, connects to a LOCAL server, joins the
## Tournoi, and when the zone-choice modal appears, presses the first zone button
## to verify the full UI -> pick_zone -> server -> game_started chain.

var server_url := "ws://127.0.0.1:9080"
var started := false
var t := 0.0
var lan: Node = null
var lobby: Node = null
var joined := false
var pressed := false
var world_loaded := false

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
			print("ZUI no LanNet")
			quit(1)
			return true
		lobby = load("res://scenes/Lobby.tscn").instantiate()
		root.add_child(lobby)
		return false
	# Press the "Rejoindre" button (world official) once connected.
	if not joined and t > 3.5:
		var all_btns: Array = _collect_buttons(lobby)
		for b in all_btns:
			if b.text.contains("Rejoindre"):
				print("ZUI pressing Rejoindre")
				b.pressed.emit()
				joined = true
				break
	# Wait for the modal, then press the first visible zone button.
	if not pressed and joined and t > 6.0:
		var zl: CanvasLayer = lobby.get_node_or_null("ZonePicker") as CanvasLayer
		var btns: Array = []
		if zl != null and zl.visible:
			btns = _collect_buttons(zl)
		if not btns.is_empty():
			var b: Button = btns[0]
			print("ZUI modal open, pressing zone: '", b.text, "'")
			b.pressed.emit()
			pressed = true
		else:
			print("ZUI no zone button in modal yet (t=", t, ", zl=", zl, ")")
	# Detect the world scene (Multiplayer) loading.
	var cur := current_scene
	if cur != null and cur.get_script() != null:
		var sp: String = cur.get_script().resource_path
		if sp.ends_with("multiplayer_main.gd") and not world_loaded:
			world_loaded = true
			print("ZUI WORLD LOADED")
			print("ZUI END")
			quit(0)
			return true
	if t > 20.0:
		print("ZUI TIMEOUT (world not loaded, modal pressed=", pressed, ")")
		quit(1)
		return true
	return false


## Collect all visible Button nodes under the lobby (the zone-choice buttons).
func _collect_buttons(node: Node) -> Array:
	var out: Array = []
	for ch in node.get_children():
		if ch is Button and ch.visible:
			out.append(ch)
		out.append_array(_collect_buttons(ch))
	return out
