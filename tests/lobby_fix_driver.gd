extends SceneTree
## Lobby-fix driver: loads the REAL lobby, connects to a LOCAL server, creates
## a VS match, and checks that the CREATOR is placed in their own waiting room
## (in_match set, am_host true, start/chat visible, "vous êtes ici" shown)
## instead of a "Rejoindre" button on their own party.

var started := false
var t := 0.0
var lan: Node = null
var lobby: Node = null
var created := false


func _process(delta: float) -> bool:
	t += delta
	if not started:
		started = true
		lan = root.get_node_or_null("LanNet")
		if lan == null:
			print("LFIX no LanNet")
			quit(1)
			return true
		lobby = load("res://scenes/Lobby.tscn").instantiate()
		root.add_child(lobby)
		return false
	if not created and t > 4.0:
		created = true
		lan.call("create_match", "PartieTest", "vs")
		print("LFIX create_match sent")
	if t > 9.0:
		var in_match: int = lobby.get("_in_match_id")
		var am_host: bool = lobby.get("_am_host")
		var start_btn: Node = lobby.get("_start_btn")
		var start_vis: bool = start_btn != null and start_btn.visible
		var here: Node = _find_label(lobby, "vous êtes ici")
		print("LFIX in_match=", in_match, " am_host=", am_host,
			" start_visible=", start_vis, " vous_etes_ici=", here != null)
		if in_match > 0 and am_host and start_vis and here != null:
			print("LFIX OK: le createur est dans sa salle d'attente")
			quit(0)
			return true
		print("LFIX FAIL")
		quit(1)
		return true
	return false


func _find_label(node: Node, text: String) -> Node:
	for ch in node.get_children():
		if ch is Label and ch.text.contains(text):
			return ch
		var r: Node = _find_label(ch, text)
		if r != null:
			return r
	return null
