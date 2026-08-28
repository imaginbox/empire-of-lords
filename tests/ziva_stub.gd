extends Node
## Test-only stub of the LanNet autoload API for headless single-process
## validation of multiplayer_main.gd's host path. Not used by the real game.
## Mirrors Godot ENet semantics: the server/host is peer id 1.

signal connected
signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)
signal host_changed(host_id: int)
signal connection_failed

var _host: int = 1


func is_connected_to_room() -> bool:
	return true


func is_host() -> bool:
	return my_id() == 1


func my_id() -> int:
	return 1


func current_host() -> int:
	return 1


func real_peers() -> Array:
	return [1]


func disconnect_from_room() -> void:
	pass
