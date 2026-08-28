extends SceneTree
## Client driver: joins the persistent Conquest server and verifies it enters the
## live Multiplayer world and receives snapshots (cities rendered).

var port := 7785
var ip := "127.0.0.1"
var started := false
var t := 0.0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--port="):
			port = int(a.trim_prefix("--port="))
		elif a.begins_with("--ip="):
			ip = a.trim_prefix("--ip=")


func _process(delta: float) -> bool:
	t += delta
	if not started:
		started = true
		var lan: Node = root.get_node_or_null("LanNet")
		if lan == null:
			print("DRIVER no LanNet")
			quit(1)
			return true
		lan.set("mode", "conquest")
		var err: int = int(lan.call("join_game", ip, port))
		print("DRIVER join err=", err)
		change_scene_to_file("res://scenes/Multiplayer.tscn")
		return false
	if int(t) % 2 == 0 and int(t * 2.0) != int((t - delta) * 2.0):
		_report()
	if t > 12.0:
		_report()
		print("DRIVER END")
		quit(0)
		return true
	return false


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
	if sp.ends_with("multiplayer_main.gd"):
		var city_nodes: Dictionary = cur.get("_city_nodes")
		print("DRIVER is_host=", bool(cur.get("_is_host")),
			" has_snap=", bool(cur.get("_has_snap")),
			" city_nodes=", city_nodes.size())
