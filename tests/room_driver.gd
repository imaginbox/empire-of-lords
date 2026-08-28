extends SceneTree
## Two-process end-to-end driver: process A hosts, process B joins, both enter
## Room.tscn (the waiting room) through the real flow; when the client connects
## the host auto-starts a countdown and both transition to Multiplayer.tscn.

var mode := "host"
var port := 7792
var started := false
var t := 0.0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--mode="):
			mode = a.trim_prefix("--mode=")
		elif a.begins_with("--port="):
			port = int(a.trim_prefix("--port="))


func _process(delta: float) -> bool:
	t += delta
	if not started:
		started = true
		_go()
		return false
	if int(t) % 2 == 0 and int(t * 2.0) != int((t - delta) * 2.0):
		_report()
	if t > 20.0:
		_report()
		print("DRIVER END ", mode)
		quit(0)
		return true
	return false


func _go() -> void:
	var lan: Node = root.get_node_or_null("LanNet")
	if lan == null:
		print("DRIVER NO LANNET AUTOLOAD")
		return
	var err: int
	if mode == "host":
		err = int(lan.call("host_game", port))
		print("DRIVER host_game=", err)
	else:
		err = int(lan.call("join_game", "127.0.0.1", port))
		print("DRIVER join_game=", err)
	change_scene_to_file("res://scenes/Room.tscn")
	print("DRIVER changed to Room")


func _report() -> void:
	var cur: Node = current_scene
	if cur == null:
		print("DRIVER scene=null")
		return
	var sp: String = ""
	var sc: Script = cur.get_script()
	if sc != null:
		sp = sc.resource_path
	print("DRIVER scene=", cur.name, " script=", sp)
	if sp.ends_with("room.gd"):
		var pl: Label = cur.get("_players_label")
		var cd: Label = cur.get("_countdown")
		print("DRIVER room players='", pl.text if pl != null else "-", "' countdown='", cd.text if cd != null else "-", "'")
	if sp.ends_with("multiplayer_main.gd"):
		var ish: bool = bool(cur.get("_is_host"))
		var game: Node = cur.get("game")
		var nc: int = 0
		if game != null:
			nc = int(game.get("cities").size())
		print("DRIVER multiplayer is_host=", ish, " cities=", nc)
