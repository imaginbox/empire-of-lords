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
signal chat_message(sender_name: String, text: String)   # emitted on the CLIENT
signal zone_choice_offered(zones: Array) # emitted on the CLIENT: pick a starting zone
signal vs_eliminated              # emitted on the CLIENT: this player is out of a VS match

## Public VPS address (TLS terminated by nginx/caddy -> internal ws port).
const SERVER_URL := "wss://195-35-24-169.sslip.io"
## Local test server (headless). Overridable with --server-url=...
const LOCAL_URL := "ws://127.0.0.1:9080"
const WS_PORT := 9080

var mode: String = "conquest"   # "vs" | "conquest"
var _hosting: bool = false
var _connected: bool = false
var player_name: String = ""    # pseudo du joueur local, envoye au serveur

# --- server-side matchmaking state (only meaningful on the VPS) ---
var matches: Array = []         # [{id,name,mode,host,players,status}]
var _next_match_id := 1
# peer_id -> match_id they are currently in
var _peer_match: Dictionary = {}
# peer_id -> pseudo du joueur (cote serveur)
var _peer_names: Dictionary = {}


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


## Set the local player's pseudo (sent to the server on matchmaking actions).
func set_player_name(n: String) -> void:
	player_name = n.strip_edges()


## Server-side helper: readable name for a peer (default "Joueur N").
func get_peer_name(pid: int) -> String:
	var n: Variant = _peer_names.get(pid, "")
	if n != null and str(n) != "":
		return str(n)
	return "Joueur %d" % pid


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

## The OFFICIAL persistent Tournament (Conquete). Joining it is a direct
## action (no match to create): the VPS assigns you a capital and starts the
## persistent world.
func join_tournament() -> void:
	if not is_connected_to_room():
		print("LanNet: join_tournament ignore (non connecte).")
		return
	_rpc_join_tournament.rpc_id(1, player_name)


func create_match(match_name: String, m: String, with_ai: bool = false) -> void:
	if not is_connected_to_room():
		print("LanNet: create_match ignore (non connecte).")
		return
	_rpc_create_match.rpc_id(1, match_name, m, player_name, with_ai)


## Tell the server this player toggled their ready state in their VS match.
## The match starts automatically when full (4/4) or when everyone is ready.
func set_ready(is_ready: bool) -> void:
	if not is_connected_to_room():
		return
	_rpc_set_ready.rpc_id(1, is_ready)


func join_match(match_id: int) -> void:
	if not is_connected_to_room():
		print("LanNet: join_match ignore (non connecte).")
		return
	_rpc_join_match.rpc_id(1, match_id, player_name)


func leave_match() -> void:
	if not is_connected_to_room():
		return
	_rpc_leave_match.rpc_id(1)


func start_match() -> void:
	if not is_connected_to_room():
		return
	_rpc_start_match.rpc_id(1)


func request_matches() -> void:
	if not is_connected_to_room():
		return
	_rpc_request_matches.rpc_id(1)


## Send a chat message to the other players in your current party.
func send_chat(text: String) -> void:
	var t: String = text.strip_edges()
	if t.is_empty():
		return
	_rpc_chat.rpc_id(1, t)


## Server-side helper: tell one client to load the game scene.
func notify_game_start(pid: int, game_mode: String) -> void:
	_rpc_game_start.rpc_id(pid, game_mode)


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


## Server relays a chat message to every player in the sender's party.
@rpc("reliable")
func _rpc_chat_msg(sender_name: String, text: String) -> void:
	if multiplayer.is_server():
		return
	chat_message.emit(sender_name, text)


# ------------------------------------------------------------- server-side matchmaking

## Server receives a request to join the official persistent Tournament.
@rpc("any_peer", "reliable")
func _rpc_join_tournament(pname: String) -> void:
	if not multiplayer.is_server():
		return
	var pid := multiplayer.get_remote_sender_id()
	if pname != "":
		_peer_names[pid] = pname
	_remove_from_match(pid)   # leave any player-created party first
	var main: Node = get_node_or_null("/root/Main")
	if main != null and main.has_method("on_join_tournament"):
		main.call("on_join_tournament", pid)

## Server offers the list of available starting zones to a new player.
func offer_zone_choice(peer_id: int, zones: Array) -> void:
	_rpc_offer_zone_choice.rpc_id(peer_id, zones)

## Client receives the zone choice offer -> lobby shows a picker.
@rpc("reliable")
func _rpc_offer_zone_choice(zones: Array) -> void:
	if multiplayer.is_server():
		return
	zone_choice_offered.emit(zones)

## Client tells the server which starting zone they picked.
func pick_zone(zone_index: int) -> void:
	if not is_connected_to_room():
		print("LanNet: pick_zone ignore (non connecte).")
		return
	_rpc_pick_zone.rpc_id(1, zone_index)

## Server receives the player's zone pick -> assigns their capital there.
@rpc("any_peer", "reliable")
func _rpc_pick_zone(zone_index: int) -> void:
	if not multiplayer.is_server():
		return
	var pid := multiplayer.get_remote_sender_id()
	var main: Node = get_node_or_null("/root/Main")
	if main != null and main.has_method("on_pick_zone"):
		main.call("on_pick_zone", pid, zone_index)

## Server receives a request to create a named match.
@rpc("any_peer", "reliable")
func _rpc_create_match(match_name: String, m: String, creator_name: String, with_ai: bool = false) -> void:
	if not multiplayer.is_server():
		return
	var pid := multiplayer.get_remote_sender_id()
	if creator_name != "":
		_peer_names[pid] = creator_name
	var match_dict := {
		"id": _next_match_id, "name": match_name, "mode": m,
		"host": pid, "players": [pid], "status": "waiting",
		"host_name": get_peer_name(pid),
		"max": 4, "with_ai": with_ai, "ready": {pid: false},
		"names": {pid: get_peer_name(pid)},
	}
	_next_match_id += 1
	matches.append(match_dict)
	_peer_match[pid] = match_dict["id"]
	_push_match_list()
	print("SERVER: player %d (%s) created match \"%s\" (%s, with_ai=%s)." % [pid, get_peer_name(pid), match_name, m, with_ai])


@rpc("any_peer", "reliable")
func _rpc_join_match(match_id: int, pname: String) -> void:
	if not multiplayer.is_server():
		return
	var pid := multiplayer.get_remote_sender_id()
	if pname != "":
		_peer_names[pid] = pname
	for match_dict in matches:
		if match_dict["id"] == match_id and match_dict["status"] == "waiting":
			if pid not in match_dict["players"]:
				match_dict["players"].append(pid)
				_peer_match[pid] = match_id
				match_dict["ready"][pid] = false
				match_dict["names"][pid] = get_peer_name(pid)
			print("SERVER: player %d joined match %d (%d/%d)." % [pid, match_id, match_dict["players"].size(), match_dict["max"]])
			_push_match_list()
			# Full house (4/4) -> start immediately.
			if match_dict["players"].size() >= int(match_dict["max"]):
				_start_match(match_dict)
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


## Server receives a chat message and relays it to the sender's party.
@rpc("any_peer", "reliable")
func _rpc_chat(text: String) -> void:
	if not multiplayer.is_server():
		return
	var pid := multiplayer.get_remote_sender_id()
	var m_id: int = _peer_match.get(pid, -1)
	if m_id < 0:
		return
	var sname: String = get_peer_name(pid)
	for match_dict in matches:
		if match_dict["id"] == m_id:
			for p: int in match_dict["players"]:
				_rpc_chat_msg.rpc_id(p, sname, text)
			return


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


## Toggle this player's ready flag; auto-start when full or all ready.
@rpc("any_peer", "reliable")
func _rpc_set_ready(is_ready: bool) -> void:
	if not multiplayer.is_server():
		return
	var pid := multiplayer.get_remote_sender_id()
	var m_id: int = _peer_match.get(pid, -1)
	for match_dict in matches:
		if match_dict["id"] == m_id:
			if not match_dict.has("ready"):
				match_dict["ready"] = {}
			match_dict["ready"][pid] = is_ready
			_push_match_list()
			_check_auto_start(match_dict)
			return


func _check_auto_start(match_dict: Dictionary) -> void:
	if match_dict["status"] != "waiting":
		return
	# Start when the room is full, or when every connected player is ready.
	var full: bool = match_dict["players"].size() >= int(match_dict["max"])
	var all_ready: bool = true
	var rdy_map: Dictionary = match_dict.get("ready", {})
	for p: int in match_dict["players"]:
		if not bool(rdy_map.get(p, false)):
			all_ready = false
			break
	# Il faut au moins 2 joueurs pour demarrer sur "tous prets".
	if full or (all_ready and match_dict["players"].size() >= 2):
		print("SERVER: match %d auto-starts (full=%s all_ready=%s)." % [match_dict["id"], full, all_ready])
		_start_match(match_dict)


## Server helper: tell one client they are eliminated from a VS match.
func rpc_vs_eliminated(pid: int) -> void:
	if multiplayer.is_server() and _peer_connected(pid):
		_rpc_vs_eliminated.rpc_id(pid)


@rpc("reliable")
func _rpc_vs_eliminated() -> void:
	if multiplayer.is_server():
		return
	vs_eliminated.emit()


## Server helper: fully close a running VS match (winner decided / aborted),
## freeing its players back to the lobby and refreshing the list.
func close_match(m_id: int) -> void:
	if not multiplayer.is_server():
		return
	for match_dict in matches:
		if match_dict["id"] == m_id:
			for p: int in match_dict["players"]:
				if _peer_match.get(p, -1) == m_id:
					_peer_match.erase(p)
			matches.erase(match_dict)
			break
	_push_match_list()


func _peer_connected(pid: int) -> bool:
	return int(pid) in multiplayer.get_peers()


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
	for pid in multiplayer.get_peers():
		if int(pid) > 1:
			_rpc_match_list.rpc_id(int(pid), matches)


func _on_peer_connected(id: int) -> void:
	if id > 1:
		peer_joined.emit(id)


func _on_peer_disconnected(id: int) -> void:
	if id > 1:
		peer_left.emit(id)
		if multiplayer.is_server():
			_peer_names.erase(id)
			_remove_from_match(id)
