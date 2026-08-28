extends Node
## Serveur officiel dedie (VPS).
##
## Deux choses distinctes :
##   1) LE TOURNOI (Conquete officielle) : un monde PERSISTANT, toujours actif,
##      cree par le serveur lui-meme. Les joueurs le REJOIGNENT directement.
##      Le VPS en fixe les regles (saisons, zones, course au Top).
##   2) LES PARTIES : des matchs ephemeres crees par les joueurs (nommes,
##      listes dans "parties en cours"). Quand une partie demarre, le serveur
##      cree un monde neuf POUR CETTE PARTIE uniquement.
##
## ROOT DU NODE = "Main" (pour aligner les chemins RPC avec Multiplayer.tscn).
##
## Lancement headless : ./serveur.x86_64 --server --port 9080

const SAVE_PATH := "user://conquest_world.json"
const SNAPSHOT_INTERVAL := 0.12
const AUTOSAVE_INTERVAL := 15.0

var game: GameState = null                 # le monde persistant du Tournoi
var _tournament_peers: Dictionary = {}     # pid -> true (dans le tournoi)
var _party_worlds: Dictionary = {}         # match_id -> {"game": GameState, "peers": {}}
var _ready_peers: Dictionary = {}          # pid -> true (a charge la scene de jeu)
var _net: Node = null
var _snap_timer := 0.0
var _save_timer := 0.0


func _ready() -> void:
	_net = get_node_or_null("/root/LanNet")
	if _net == null:
		print("SERVER: LanNet autoload missing -- aborting.")
		get_tree().quit(1)
		return
	var port := _arg_int("--port", 9080)
	var err := int(_net.call("host_server", port))
	if err != 0:
		print("SERVER: cannot host on port %d (err=%d)." % [port, err])
		get_tree().quit(1)
		return
	print("SERVER: hosting WebSocket server on port %d" % port)

	# --- Tournoi persistant, toujours actif ---
	game = GameState.new()
	game.name = "GameState"
	add_child(game)
	if game.load_from_file(SAVE_PATH):
		print("SERVER: Tournoi repris depuis %s (saison %d, zone %d)." % [SAVE_PATH, game.season_number, game._zone_front + 1])
	else:
		game.end_peace()
		print("SERVER: nouveau Tournoi cree.")
	_save_state()

	set_multiplayer_authority(1)
	game.season_ended.connect(_on_season_ended)
	_net.peer_left.connect(_on_peer_left)
	print("SERVER: ready. Tournoi actif -- les joueurs peuvent rejoindre.")


func _process(delta: float) -> void:
	if game != null:
		game._process(delta)   # le Tournoi simule en permanence
	for wid in _party_worlds:
		_party_worlds[wid].game._process(delta)
	_snap_timer += delta
	if _snap_timer >= SNAPSHOT_INTERVAL:
		_snap_timer = 0.0
		_broadcast_snapshots()
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


# ------------------------------------------------------------- args

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


# ------------------------------------------------------------- peers

func _on_peer_left(peer_id: int) -> void:
	if peer_id <= 1:
		return
	_tournament_peers.erase(peer_id)
	_ready_peers.erase(peer_id)
	for wid in _party_worlds.keys():
		var w: Dictionary = _party_worlds[wid]
		w.peers.erase(peer_id)
		if w.peers.is_empty():
			w.game.queue_free()
			_party_worlds.erase(wid)
			print("SERVER: partie %s vide, monde ferme." % wid)
	print("SERVER: player %d disconnected." % peer_id)


## Le monde dans lequel un peer joue (Tournoi ou une partie), ou vide.
func _world_of(peer_id: int) -> Dictionary:
	if _tournament_peers.has(peer_id):
		return {"game": game, "peers": _tournament_peers}
	for wid in _party_worlds:
		var w: Dictionary = _party_worlds[wid]
		if w.peers.has(peer_id):
			return w
	return {}


# ------------------------------------------------------------- TOURNOI

## Appele par LanNet quand un joueur clique "Rejoindre le Tournoi".
func on_join_tournament(peer_id: int) -> void:
	if game == null or peer_id <= 1:
		return
	_assign_city(game, peer_id)
	_tournament_peers[peer_id] = true
	_net.call("notify_game_start", peer_id, "conquest")
	_broadcast_snapshots()
	print("SERVER: player %d a rejoint le Tournoi officiel." % peer_id)


func _on_season_ended(_rank: int, _gems: int, _realm: int, _res: String) -> void:
	for p in _tournament_peers:
		if int(p) > 1:
			_assign_city(game, int(p))
	_save_state()


# ------------------------------------------------------------- PARTIES

## Appele par LanNet quand une partie creee par un joueur demarre.
func start_match_game(match_dict: Dictionary) -> void:
	var players: Array = match_dict.get("players", [])
	var mid: int = int(match_dict.get("id", -1))
	if mid < 0:
		return
	var g := GameState.new()
	g.name = "GameState_P%d" % mid
	add_child(g)
	g.end_peace()
	var peers: Dictionary = {}
	for p in players:
		var pid: int = int(p)
		if pid > 1:
			_assign_city(g, pid)
			peers[pid] = true
	_party_worlds[mid] = {"game": g, "peers": peers}
	_broadcast_snapshots()
	print("SERVER: partie \"%s\" demarree -- %d joueur(s), monde neuf." % [match_dict.get("name", "?"), players.size()])


# ------------------------------------------------------------- villes

func _assign_city(g: GameState, peer_id: int) -> void:
	if g == null:
		return
	# Si le joueur possede deja une ville (reconnexion), on la lui rend.
	for c: CityNode in g.cities:
		if c.owner == CityNode.OWNER_PLAYER and c.controller == peer_id:
			c.revealed = true
			g.node_changed.emit(c.id)
			return
	# Sinon : on attribue une ville NEUTRE LIBRE, la plus eloignee possible des
	# villes des autres joueurs => chaque joueur apparait a un ENDROIT DISTINCT
	# de la carte et peut voir les autres (pas de brouillard en multijoueur).
	# Jamais une ville que quelqu'un possede deja (bug "meme perso" corrige).
	var best: CityNode = null
	var best_score := -INF
	for c: CityNode in g.cities:
		if c.owner != CityNode.OWNER_NEUTRAL or c.controller != 0:
			continue
		var min_d := INF
		var others := 0
		for o: CityNode in g.cities:
			if o.owner == CityNode.OWNER_PLAYER and o.controller > 1:
				others += 1
				var dd: float = c.map_pos.distance_to(o.map_pos)
				if dd < min_d:
					min_d = dd
		var score: float = c.map_pos.distance_to(Vector2.ZERO) if others == 0 else min_d
		if g.zone_of(c) <= g._zone_front:
			score += 2000.0   # on prefere la zone actuelle (jouable)
		if score > best_score:
			best_score = score
			best = c
	if best == null:
		print("SERVER: aucune ville libre a attribuer au joueur %d." % peer_id)
		return
	best.owner = CityNode.OWNER_PLAYER
	best.garrison = maxi(best.garrison, 300)
	best.controller = peer_id
	best.revealed = true
	g.node_changed.emit(best.id)
	print("SERVER: %s attribuee au joueur %d (apparition distincte)." % [best.node_name, peer_id])


# ------------------------------------------------------------- snapshots

func _build_snapshot(g: GameState) -> Dictionary:
	var city_arr: Array = []
	for c: CityNode in g.cities:
		city_arr.append({
			"id": c.id, "name": c.node_name, "x": c.map_pos.x, "y": c.map_pos.y,
			"owner": c.owner, "level": c.level, "garrison": c.garrison,
			"revealed": c.revealed, "controller": c.controller,
		})
	var army_arr: Array = []
	for a: Army in g.armies:
		var p: Vector2 = _army_pos(a, g)
		army_arr.append({"id": army_arr.size(), "x": p.x, "y": p.y, "faction": a.faction})
	var zname := ""
	if g.zones.size() > 0 and g._zone_front < g.zones.size():
		zname = str(g.zones[g._zone_front]["name"])
	var names := {}
	for c: CityNode in g.cities:
		if c.controller > 1 and not names.has(c.controller):
			names[c.controller] = _net.call("get_peer_name", c.controller)
	return {
		"cities": city_arr, "armies": army_arr,
		"front": g._zone_front, "zone_total": g.zones.size(),
		"season": g.season_number, "season_left": g.season_remaining,
		"gold": g.player.gold, "level": g.player.level,
		"dominance": g.dominance_score(), "zname": zname,
		"names": names,
	}


func _broadcast_snapshots() -> void:
	var known: PackedInt32Array = multiplayer.get_peers()
	if game != null and not _tournament_peers.is_empty():
		var tsnap: Dictionary = _build_snapshot(game)
		for pid in _tournament_peers:
			if int(pid) > 1 and int(pid) in known and _ready_peers.has(pid):
				_recv_snapshot.rpc_id(int(pid), tsnap)
	for wid in _party_worlds:
		var w: Dictionary = _party_worlds[wid]
		if w.peers.is_empty():
			continue
		var psnap: Dictionary = _build_snapshot(w.game)
		for pid in w.peers:
			if int(pid) > 1 and int(pid) in known and _ready_peers.has(pid):
				_recv_snapshot.rpc_id(int(pid), psnap)


@rpc("any_peer", "reliable")
func _rpc_game_ready() -> void:
	if not multiplayer.is_server():
		return
	_ready_peers[multiplayer.get_remote_sender_id()] = true


## Stub : le serveur ne fait qu'ENVOYER les snapshots.
@rpc("reliable")
func _recv_snapshot(_snap: Dictionary) -> void:
	pass


func _army_pos(a: Army, g: GameState) -> Vector2:
	var src: CityNode = g.get_city(a.from_id)
	var dst: CityNode = g.get_city(a.to_id)
	if src == null or dst == null:
		return Vector2.ZERO
	var t: float = clampf((g.time - a.depart_time) / maxf(a.travel_time, 0.001), 0.0, 1.0)
	return src.map_pos.lerp(dst.map_pos, t)


# ------------------------------------------------------------- commandes clients

@rpc("any_peer", "reliable")
func _cmd_launch(from_id: int, to_id: int, troops: int) -> void:
	var peer: int = multiplayer.get_remote_sender_id()
	var w: Dictionary = _world_of(peer)
	if w.is_empty():
		return
	var g: GameState = w.game
	var src: CityNode = g.get_city(from_id)
	if src == null or src.owner != CityNode.OWNER_PLAYER or src.controller != peer:
		return
	g.launch_army(from_id, to_id, troops)


@rpc("any_peer", "reliable")
func _cmd_upgrade(city_id: int) -> void:
	var peer: int = multiplayer.get_remote_sender_id()
	var w: Dictionary = _world_of(peer)
	if w.is_empty():
		return
	var g: GameState = w.game
	var c: CityNode = g.get_city(city_id)
	if c == null or c.owner != CityNode.OWNER_PLAYER or c.controller != peer:
		return
	g.upgrade_city(city_id)


@rpc("any_peer", "reliable")
func _cmd_recruit() -> void:
	var peer: int = multiplayer.get_remote_sender_id()
	var w: Dictionary = _world_of(peer)
	if w.is_empty():
		return
	w.game.recruit_ally()
