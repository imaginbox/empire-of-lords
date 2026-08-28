extends Node
## Dedicated persistent Conquest server.
## Run it headless on a VPS (the binary exported by CI) with:
##     ./EmpireOfLords_server.x86_64 --server --port 7777
## This node's ROOT MUST BE NAMED "Main" so that snapshot / command RPCs route
## to the same node path as the clients' Multiplayer scene (/root/Main).
##
## The server hosts the authoritative GameState, persists it to
## user://conquest_world.json (resumed on restart), accepts players joining at
## any time (each gets their own capital city) and broadcasts world snapshots.
## Other modes (Solo / Multi VS) are NOT served here — this is Conquest only.

const SAVE_PATH := "user://conquest_world.json"
const SNAPSHOT_INTERVAL := 0.12
const AUTOSAVE_INTERVAL := 15.0

var game: GameState = null
var _net: Node = null
var _snap_timer := 0.0
var _save_timer := 0.0


func _ready() -> void:
	_net = get_node_or_null("/root/LanNet")
	if _net == null:
		print("SERVER: LanNet autoload missing — aborting.")
		get_tree().quit(1)
		return
	var port := _arg_int("--port", 7777)
	var err := int(_net.call("host_game", port))
	if err != 0:
		print("SERVER: cannot host on port %d (err=%d)." % [port, err])
		get_tree().quit(1)
		return
	_net.set("mode", "conquest")
	print("SERVER: hosting Conquest on port %d" % port)

	game = GameState.new()
	game.name = "GameState"
	add_child(game)
	if game.load_from_file(SAVE_PATH):
		print("SERVER: world resumed from %s (season %d, zone %d)." % [SAVE_PATH, game.season_number, game._zone_front + 1])
	else:
		game.end_peace()   # no tutorial grace on the shared server
		print("SERVER: new world created.")
	_save_state()

	set_multiplayer_authority(1)
	game.season_ended.connect(_on_season_ended)
	_net.peer_joined.connect(_on_peer_joined)
	print("SERVER: ready. Waiting for players…")


func _process(delta: float) -> void:
	game._process(delta)
	_snap_timer += delta
	if _snap_timer >= SNAPSHOT_INTERVAL:
		_snap_timer = 0.0
		_broadcast_snapshot()
	_save_timer += delta
	if _save_timer >= AUTOSAVE_INTERVAL:
		_save_timer = 0.0
		_save_state()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_CRASH:
		_save_state()


func _exit_tree() -> void:
	_save_state()


func _save_state() -> void:
	if game != null:
		game.save_to_file(SAVE_PATH)


# ------------------------------------------------------------- arg parsing

func _arg_int(flag: String, default_val: int) -> int:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for i in args.size():
		if args[i].begins_with(flag + "="):
			var v := args[i].trim_prefix(flag + "=")
			if v.is_valid_int():
				return int(v)
		elif args[i] == flag and i + 1 < args.size() and args[i + 1].is_valid_int():
			return int(args[i + 1])
	return default_val


# ------------------------------------------------------------- players

func _on_peer_joined(peer_id: int) -> void:
	if peer_id <= 1:
		return
	print("SERVER: player %d joined." % peer_id)
	_assign_city(peer_id)
	_broadcast_snapshot()


func _on_peer_left(peer_id: int) -> void:
	if peer_id > 1:
		print("SERVER: player %d left." % peer_id)


func _assign_city(peer_id: int) -> void:
	if game == null:
		return
	# Reconnect: if the player already owns a city, just re-reveal it.
	for c: CityNode in game.cities:
		if c.owner == CityNode.OWNER_PLAYER and c.controller == peer_id:
			c.revealed = true
			game.node_changed.emit(c.id)
			return
	# New player: nearest neutral city inside the current frontier.
	var best: CityNode = null
	var best_d := INF
	for c: CityNode in game.cities:
		if c.owner == CityNode.OWNER_NEUTRAL and c.controller == 0 \
				and game.zone_of(c) <= game._zone_front:
			var dd: float = c.map_pos.distance_to(Vector2.ZERO)
			if dd < best_d:
				best_d = dd
				best = c
	if best == null:
		best = game.get_city(0)
	if best == null:
		return
	best.owner = CityNode.OWNER_PLAYER
	best.garrison = maxi(best.garrison, 300)
	best.controller = peer_id
	best.revealed = true
	game.node_changed.emit(best.id)
	print("SERVER: assigned %s to player %d." % [best.node_name, peer_id])


func _on_season_ended(_rank: int, _gems: int, _realm: int, _res: String) -> void:
	# The map was rebuilt; hand every connected player their capital again.
	for p in _net.real_peers():
		if int(p) > 1:
			_assign_city(int(p))
	_save_state()


# ------------------------------------------------------------- snapshots

func _build_snapshot() -> Dictionary:
	var city_arr: Array = []
	for c: CityNode in game.cities:
		city_arr.append({
			"id": c.id, "name": c.node_name, "x": c.map_pos.x, "y": c.map_pos.y,
			"owner": c.owner, "level": c.level, "garrison": c.garrison,
			"revealed": c.revealed, "controller": c.controller,
		})
	var army_arr: Array = []
	for a: Army in game.armies:
		var p: Vector2 = _army_pos(a)
		army_arr.append({"id": army_arr.size(), "x": p.x, "y": p.y, "faction": a.faction})
	var zname := ""
	if game.zones.size() > 0 and game._zone_front < game.zones.size():
		zname = str(game.zones[game._zone_front]["name"])
	return {
		"cities": city_arr, "armies": army_arr,
		"front": game._zone_front, "zone_total": game.zones.size(),
		"season": game.season_number, "season_left": game.season_remaining,
		"gold": game.player.gold, "level": game.player.level,
		"dominance": game.dominance_score(), "zname": zname,
	}


func _broadcast_snapshot() -> void:
	_recv_snapshot.rpc(_build_snapshot())


## Stub: the server only SENDS snapshots. This exists so the .rpc() callable
## compiles and routes to clients (which implement the real receiver).
@rpc("reliable")
func _recv_snapshot(_snap: Dictionary) -> void:
	pass


func _army_pos(a: Army) -> Vector2:
	var src: CityNode = game.get_city(a.from_id)
	var dst: CityNode = game.get_city(a.to_id)
	if src == null or dst == null:
		return Vector2.ZERO
	var t: float = clampf((game.time - a.depart_time) / maxf(a.travel_time, 0.001), 0.0, 1.0)
	return src.map_pos.lerp(dst.map_pos, t)


# ------------------------------------------------------------- client commands
## Clients send these via rpc_id(1, ...) targeting /root/Main on this server.

@rpc("any_peer", "reliable")
func _cmd_launch(from_id: int, to_id: int, troops: int) -> void:
	if game == null:
		return
	var peer: int = multiplayer.get_remote_sender_id()
	var src: CityNode = game.get_city(from_id)
	if src == null or src.owner != CityNode.OWNER_PLAYER or src.controller != peer:
		return
	game.launch_army(from_id, to_id, troops)


@rpc("any_peer", "reliable")
func _cmd_upgrade(city_id: int) -> void:
	if game == null:
		return
	var peer: int = multiplayer.get_remote_sender_id()
	var c: CityNode = game.get_city(city_id)
	if c == null or c.owner != CityNode.OWNER_PLAYER or c.controller != peer:
		return
	game.upgrade_city(city_id)


@rpc("any_peer", "reliable")
func _cmd_recruit() -> void:
	if game == null:
		return
	game.recruit_ally()
