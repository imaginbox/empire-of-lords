extends Node
## LanNet — WebSocket networking + matchmaking autoload.
##
## Everything connects to ONE persistent VPS server over WebSocket (the only
## protocol that works in the browser). There is no client hosting anymore:
## players CREATE a named match on the server, it appears in "parties en
## cours", and others JOIN it. The VPS is always peer 1 = the authority, and
## decides how each match is played (Conquete = persistent shared world).
##
## This autoload is at /root/LanNet on BOTH client and server so that the
## matchmaking RPCs share the same node path.

signal connected              # connected to the server
signal connection_failed
signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)
signal match_list_changed(list: Array)   # emitted on the CLIENT with new list
signal game_started(mode: String)        # emitted on the CLIENT: load the game scene

## Public VPS address (TLS terminated by nginx/caddy -> internal ws port).
const SERVER_URL := "wss://195-35-24-169.sslip.io"
## Local test server (headless). Overridable with --server-url=...
const LOCAL_URL := "ws://127.0.0.1:9080"
const WS_PORT := 9080

var mode: String = "conquest"   # "vs" | "conquest"
var _hosting: bool = false
var _connected: bool = false

# --- server-side matchmaking state (only meaningful on the VPS) ---
var matches: Array = []         # [{id,name,mode,host,players,status}]
var _next_match_id := 1
# peer_id -> match_id they are currently in
var _peer_match: Dictionary = {}


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(func():
		_connected = true
		connected.emit()
		request_matches())
	multiplayer.connection_failed.connect(func(): connection_failed.emit())
	multiplayer.server_disconnected.connect(func():
		_connected = false
		connection_failed.emit())
	# A dedicated server binary boots straight into the server scene.
	if OS.has_feature("dedicated_server") or "--server" in OS.get_cmdline_user_args():
		call_deferred("_start_dedicated_server")


func _start_dedicated_server() -> void:
	print("LANNET: dedicated server mode -> starting matchmaking server scene.")
	get_tree().change_scene_to_file("res://scenes/server.tscn")


func _server_url() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--server-url="):
			return a.trim_prefix("--server-url=")
	return SERVER_URL


# ------------------------------------------------------------- connection

## Connect this process to the VPS server (used by clients).
func connect_to_server() -> Error:
	if _connected:
		return OK
	var url: String = _server_url()
	if OS.has_feature("web"):
		# In the browser the page is https, so we must use wss (the default URL).
		url = SERVER_URL
	var peer := WebSocketMultiplayerPeer.new()
	var err := peer.create_client(url)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	return OK


## Start the WebSocket server (used by the dedicated server / VPS).
func host_server(port: int = WS_PORT) -> Error:
	var peer := WebSocketMultiplayerPeer.new()
	var err := peer.create_server(port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	_hosting = true
	_connected = true
	connected.emit()
	return OK


func disconnect_from_room() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_hosting = false
	_connected = false


func is_connected_to_room() -> bool:
	return _connected or _hosting


func my_id() -> int:
	return multiplayer.get_unique_id()


## The VPS (peer 1) is always the authority/server.
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


# ------------------------------------------------------------- matchmaking (client)

func create_match(name: String, m: String) -> void:
	_rpc_create_match.rpc_id(1, name, m)


func join_match(match_id: int) -> void:
	_rpc_join_match.rpc_id(1, match_id)


func leave_match() -> void:
	_rpc_leave_match.rpc_id(1)


func start_match() -> void:
	_rpc_start_match.rpc_id(1)


func request_matches() -> void:
	_rpc_request_matches.rpc_id(1)


# --- client-side RPC receivers ---

## Server broadcasts the updated match list to every connected client.
@rpc("reliable")
func _rpc_match_list(list: Array) -> void:
	if multiplayer.is_server():
		return
	match_list_changed.emit(list)


## Server tells this client which match started -> load the game scene.
@rpc("reliable")
func _rpc_game_start(m: String) -> void:
	if multiplayer.is_server():
		return
	game_started.emit(m)


# ------------------------------------------------------------- server-side matchmaking

## Server receives a request to create a named match.
@rpc("any_peer", "reliable")
func _rpc_create_match(name: String, m: String) -> void:
	if not multiplayer.is_server():
		return
	var pid := multiplayer.get_remote_sender_id()
	var match_dict := {
		"id": _next_match_id, "name": name, "mode": m,
		"host": pid, "players": [pid], "status": "waiting",
	}
	_next_match_id += 1
	matches.append(match_dict)
	_peer_match[pid] = match_dict["id"]
	_push_match_list()
	print("SERVER: player %d created match \"%s\" (%s)." % [pid, name, m])


@rpc("any_peer", "reliable")
func _rpc_join_match(match_id: int) -> void:
	if not multiplayer.is_server():
		return
	var pid := multiplayer.get_remote_sender_id()
	for match_dict in matches:
		if match_dict["id"] == match_id and match_dict["status"] == "waiting":
			if pid not in match_dict["players"]:
				match_dict["players"].append(pid)
				_peer_match[pid] = match_id
			_push_match_list()
			print("SERVER: player %d joined match %d." % [pid, match_id])
			return


@rpc("any_peer", "reliable")
func _rpc_leave_match() -> void:
	if not multiplayer.is_server():
		return
	var pid := multiplayer.get_remote_sender_id()
	_remove_from_match(pid)


@rpc("any_peer", "reliable")
func _rpc_request_matches() -> void:
	if not multiplayer.is_server():
		return
	_rpc_match_list.rpc_id(multiplayer.get_remote_sender_id(), matches)


@rpc("any_peer", "reliable")
func _rpc_start_match() -> void:
	if not multiplayer.is_server():
		return
	var pid := multiplayer.get_remote_sender_id()
	var m_id: int = _peer_match.get(pid, -1)
	for match_dict in matches:
		if match_dict["id"] == m_id and match_dict["host"] == pid:
			_start_match(match_dict)
			return


func _remove_from_match(pid: int) -> void:
	var m_id: int = _peer_match.get(pid, -1)
	if m_id < 0:
		return
	for match_dict in matches:
		if match_dict["id"] == m_id:
			match_dict["players"].erase(pid)
			_peer_match.erase(pid)
			if match_dict["host"] == pid or match_dict["players"].size() == 0:
				# Host left or empty -> close the match.
				for p: int in match_dict["players"]:
					if _peer_match.get(p, -1) == m_id:
						_peer_match.erase(p)
				matches.erase(match_dict)
			break
	_push_match_list()


func _start_match(match_dict: Dictionary) -> void:
	if match_dict["status"] != "waiting":
		return
	match_dict["status"] = "running"
	print("SERVER: match %d \"%s\" starts with players %s." % [match_dict["id"], match_dict["name"], str(match_dict["players"])])
	# Tell every player in the match to load the game scene.
	for p: int in match_dict["players"]:
		_rpc_game_start.rpc_id(p, match_dict["mode"])
	# Notify the game authority (server.gd on /root/Main) to run this match.
	var main: Node = get_node_or_null("/root/Main")
	if main != null and main.has_method("start_match_game"):
		main.call("start_match_game", match_dict)
	_push_match_list()


func _push_match_list() -> void:
	_rpc_match_list.rpc(matches)


func _on_peer_connected(id: int) -> void:
	if id > 1:
		peer_joined.emit(id)


func _on_peer_disconnected(id: int) -> void:
	if id > 1:
		peer_left.emit(id)
		if multiplayer.is_server():
			_remove_from_match(id)
