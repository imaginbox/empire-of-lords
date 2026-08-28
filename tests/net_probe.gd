extends SceneTree
## Headless probe that verifies the Godot ENet transport connects a host and a
## client on localhost. Run two instances:
##   godot --headless --script res://tests/net_probe.gd -- --mode=host
##   godot --headless --script res://tests/net_probe.gd -- --mode=client

var mode := "host"
var peer := ENetMultiplayerPeer.new()
var t := 0.0
var done := false
var started := false


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--mode="):
			mode = a.trim_prefix("--mode=")


func _start() -> void:
	var mp: SceneMultiplayer = root.multiplayer
	if mode == "host":
		peer.create_server(7790, 4)
		mp.multiplayer_peer = peer
		print("PROBE host server up (id=", mp.get_unique_id(), ")")
		mp.peer_connected.connect(func(id: int):
			print("PROBE host got peer ", id)
			done = true)
	else:
		peer.create_client("127.0.0.1", 7790)
		mp.multiplayer_peer = peer
		print("PROBE client connecting")
		mp.connected_to_server.connect(func():
			print("PROBE client connected (id=", mp.get_unique_id(), ")")
			done = true)
		mp.connection_failed.connect(func():
			print("PROBE client CONNECTION FAILED")
			done = true)


func _process(delta: float) -> bool:
	if not started:
		started = true
		_start()
	t += delta
	if done:
		print("PROBE RESULT ", mode, " OK")
		quit(0)
		return true
	if t > 8.0:
		print("PROBE RESULT ", mode, " TIMEOUT")
		quit(1)
		return true
	return false
