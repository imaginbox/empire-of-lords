extends Node
## ZivaNet — relay multiplayer autoload.
##
## Connects this instance to Ziva's hosted WebSocket relay (peer-to-peer message
## switch; there is NO dedicated game server). The relay owns phantom peer id 1,
## so the real host is the LOWEST real peer id (> 1). The first client into a
## fresh room is provably id 2 and may host immediately; every later peer waits
## to learn the roster before claiming authority.
##
## This autoload only handles the connection + authority rules. The world logic
## lives in multiplayer_main.gd (host runs GameState, broadcasts snapshots).

signal connected            # this peer finished connecting to the relay
signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)
signal host_changed(host_id: int)
signal connection_failed

var _host: int = 0          # the current real host peer id
var _room: String = ""


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_connection_failed)


# ------------------------------------------------------------- connect

## Opens the room on the relay and starts networking. Same call for host or
## client; the peer that turns out to be the lowest real id acts as host.
func join_room(room_id: String) -> Error:
	var user_id: String = ProjectSettings.get_setting("ziva/multiplayer/user_id", "")
	var game_id: String = ProjectSettings.get_setting("ziva/multiplayer/game_id", "")
	var relay_url: String = ProjectSettings.get_setting("ziva/multiplayer/relay_url", "")
	if user_id.is_empty() or game_id.is_empty() or relay_url.is_empty():
		push_error("Ziva multiplayer settings missing — run setup_multiplayer.")
		return ERR_UNCONFIGURED
	_room = room_id
	var url: String = "%s/r/%s?u=%s&g=%s&v=1" % [relay_url, room_id, user_id, game_id]
	var peer := WebSocketMultiplayerPeer.new()
	var err := peer.create_client(url)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	return OK


func disconnect_from_room() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_host = 0
	_room = ""


func is_connected_to_room() -> bool:
	return multiplayer.multiplayer_peer is WebSocketMultiplayerPeer \
		and multiplayer.get_unique_id() > 1


# ------------------------------------------------------------- authority

func my_id() -> int:
	return multiplayer.get_unique_id()


func real_peers() -> Array:
	var out: Array = []
	for p in multiplayer.get_peers():
		if int(p) > 1:
			out.append(int(p))
	return out


## Host = lowest real peer id. include_self_floor lets callers exclude `me`
## during the connect burst, so a non-host peer never transiently claims the
## spawner and REJECTS the real host's spawns with ERR_UNAUTHORIZED.
func refresh_host(include_self_floor: bool = true) -> void:
	var cands: Array = real_peers()
	var me: int = multiplayer.get_unique_id()
	if include_self_floor and me > 1:
		cands.append(me)
	cands.sort()
	if cands.size() > 0:
		var new_host: int = int(cands[0])
		if new_host != _host:
			_host = new_host
			host_changed.emit(_host)


func is_host() -> bool:
	return multiplayer.get_unique_id() == _host and _host > 0


func current_host() -> int:
	return _host


# ------------------------------------------------------------- events

func _on_connected_ok() -> void:
	var me: int = multiplayer.get_unique_id()
	# id 2 is the only peer that provably has no lower peer -> it may host now.
	refresh_host(me == 2)
	connected.emit()


func _on_peer_connected(id: int) -> void:
	if id <= 1:
		return
	refresh_host()
	peer_joined.emit(id)


func _on_peer_disconnected(id: int) -> void:
	if id <= 1:
		return
	peer_left.emit(id)
	refresh_host()


func _on_connection_failed() -> void:
	_host = 0
	connection_failed.emit()
