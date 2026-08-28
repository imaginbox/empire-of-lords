extends Node
## LanNet — Godot built-in high-level multiplayer (ENet) autoload.
##
## One player HOSTS using ENetMultiplayerPeer.create_server(port); the others
## JOIN using create_client(ip, port). With ENet the server is peer id 1 and is
## the authority — no external relay needed.
##
## Works out of the box on a LAN / same network. Over the internet the host must
## port-forward the chosen UDP port to be reachable (or run on a public IP).
##
## This autoload only handles connection + authority rules; the world logic lives
## in multiplayer_main.gd (host runs GameState, broadcasts snapshots).

signal connected            # this peer finished connecting (or started hosting)
signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)
signal connection_failed

var _hosting: bool = false  # true on the server machine

## Game mode chosen in the lobby: "vs" (quick match) or "conquest" (tournament).
## Persists across scene changes (lobby -> room -> multiplayer).
var mode: String = "conquest"


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(func(): connected.emit())
	multiplayer.connection_failed.connect(func(): connection_failed.emit())
	multiplayer.server_disconnected.connect(func(): connection_failed.emit())
	# A dedicated server binary (exported as "dedicated_server", or launched
	# with --server) boots straight into the persistent Conquest server scene.
	if OS.has_feature("dedicated_server") or "--server" in OS.get_cmdline_user_args():
		call_deferred("_start_dedicated_server")


func _start_dedicated_server() -> void:
	print("LANNET: dedicated server mode -> starting Conquest server scene.")
	get_tree().change_scene_to_file("res://scenes/server.tscn")


# ------------------------------------------------------------- lifecycle

## Starts a listen server on `port`. Caller (the host) becomes peer id 1.
func host_game(port: int) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, 16)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	_hosting = true
	connected.emit()
	return OK


## Connects to a hosted game at `ip:port`.
func join_game(ip: String, port: int) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	return OK


func disconnect_from_room() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_hosting = false


func is_connected_to_room() -> bool:
	var p: MultiplayerPeer = multiplayer.multiplayer_peer
	if not (p is ENetMultiplayerPeer):
		return false
	if _hosting:
		return true
	return multiplayer.get_unique_id() > 0


# ------------------------------------------------------------- authority

func my_id() -> int:
	return multiplayer.get_unique_id()


## The ENet server is always the host (peer 1) and the authority.
func is_host() -> bool:
	return multiplayer.is_server()


func current_host() -> int:
	return 1


func real_peers() -> Array:
	var out: Array = []
	for p in multiplayer.get_peers():
		if int(p) > 0:
			out.append(int(p))
	return out


# ------------------------------------------------------------- events

func _on_peer_connected(id: int) -> void:
	if id > 1:
		peer_joined.emit(id)


func _on_peer_disconnected(id: int) -> void:
	if id > 1:
		peer_left.emit(id)
