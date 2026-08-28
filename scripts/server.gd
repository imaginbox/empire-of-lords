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
var _last_rankings: Array = []
var _winner_announced := false
var _toast := ""
var _pending_choice: Dictionary = {}   # pid -> true (attend le choix de zone)


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
	game.center_final = true   # conquete de l'exterieur vers le centre (zone finale au milieu)
	add_child(game)
	if game.load_from_file(SAVE_PATH):
		print("SERVER: Tournoi repris depuis %s (saison %d, zone %d)." % [SAVE_PATH, game.season_number, game.zone_physical(game._zone_front) + 1])
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
		_last_rankings = _territory_rankings(game)
		var prev_sn: int = game.season_number
		game._process(delta)   # le Tournoi simule en permanence
		if game.season_number != prev_sn:
			_winner_announced = false
			_announce_season_winner(_last_rankings)
		else:
			_check_immediate_win()
	for wid in _party_worlds.keys():
		var w: Dictionary = _party_worlds[wid]
		w.game._process(delta)
		_vs_lifecycle(w, int(wid), delta)
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
	_pending_choice.erase(peer_id)
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
	_tournament_peers[peer_id] = true
	# Reconnexion : le joueur a deja une capitale -> on la lui rend, pas de choix.
	if _peer_has_capital(peer_id):
		_assign_city(game, peer_id)
		_net.call("notify_game_start", peer_id, "conquest")
		_broadcast_snapshots()
		print("SERVER: player %d a rejoint le Tournoi (capitale existante)." % peer_id)
		return
	# Nouveau joueur : on lui propose de choisir sa zone de depart.
	var zones := _available_zones()
	if zones.is_empty():
		_assign_city(game, peer_id)   # fallback : aucune zone libre
		_net.call("notify_game_start", peer_id, "conquest")
		_broadcast_snapshots()
		print("SERVER: player %d a rejoint (aucune zone libre, capitale auto)." % peer_id)
		return
	_pending_choice[peer_id] = true
	_net.call("offer_zone_choice", peer_id, zones)
	print("SERVER: player %d -> choix de zone (%d zones)." % [peer_id, zones.size()])


## True si le joueur possede deja une capitale dans le Tournoi.
func _peer_has_capital(peer_id: int) -> bool:
	for c: CityNode in game.cities:
		if c.owner == CityNode.OWNER_PLAYER and c.controller == peer_id:
			return true
	return false


## Zones jouables (frontiere comprise) ayant au moins une ville neutre libre.
func _available_zones() -> Array:
	var out: Array = []
	for zi in range(game.zones.size()):
		if game.zone_physical(zi) > game._zone_front:
			continue
		var free := 0
		for c: CityNode in game.cities:
			if game.zone_of(c) == zi and c.owner == CityNode.OWNER_NEUTRAL and c.controller == 0:
				free += 1
		if free > 0:
			out.append({"index": zi, "name": str(game.zones[zi]["name"]), "free": free})
	return out


## Appele par LanNet quand le joueur a choisi sa zone de depart.
func on_pick_zone(peer_id: int, zone_index: int) -> void:
	if game == null or peer_id <= 1:
		return
	_pending_choice.erase(peer_id)
	var ok := false
	for zi in range(game.zones.size()):
		if zi == zone_index and game.zone_physical(zi) <= game._zone_front:
			ok = true
	if ok:
		_assign_city(game, peer_id, zone_index)
	else:
		_assign_city(game, peer_id)   # fallback si zone invalide
	_net.call("notify_game_start", peer_id, "conquest")
	_broadcast_snapshots()
	print("SERVER: player %d a choisi la zone %d." % [peer_id, zone_index])


func _on_season_ended(_rank: int, _gems: int, _realm: int, _res: String) -> void:
	for p in _tournament_peers:
		if int(p) > 1:
			_assign_city(game, int(p))
	_save_state()


## Classement des joueurs par nombre de villes controlees (descendant).
func _territory_rankings(g: GameState) -> Array:
	var counts: Dictionary = {}
	for c: CityNode in g.cities:
		if c.owner == CityNode.OWNER_PLAYER and c.controller > 1:
			counts[c.controller] = int(counts.get(c.controller, 0)) + 1
	var out: Array = []
	for pid in counts:
		out.append({"controller": int(pid),
			"name": str(_net.call("get_peer_name", int(pid))),
			"cities": int(counts[pid])})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["cities"]) > int(b["cities"]))
	return out


## Victoire immédiate : un joueur contrôle 100% du monde.
func _check_immediate_win() -> void:
	if _winner_announced or _last_rankings.is_empty():
		return
	var total: int = game.cities.size()
	if total <= 0:
		return
	if int(_last_rankings[0]["cities"]) >= total:
		_winner_announced = true
		_announce_season_winner(_last_rankings)
		game._end_season()


## Annonce le vainqueur de la saison (le plus de territoire) a tous.
func _announce_season_winner(rankings: Array) -> void:
	if rankings.is_empty():
		return
	var top: Dictionary = rankings[0]
	var msg: String = "🏆 %s remporte la saison %d avec %d ville(s) !" % [
		top["name"], game.season_number, int(top["cities"])]
	print("SERVER: %s" % msg)
	_toast = msg
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
	# Option "avec IA" : sans IA, pas de seigneurs ennemis (pur PvP).
	if not bool(match_dict.get("with_ai", true)):
		for c: CityNode in g.cities:
			if c.owner == CityNode.OWNER_ENEMY:
				c.owner = CityNode.OWNER_NEUTRAL
				c.controller = 0
				c.revealed = false
	# Carte reduite : les joueurs et leurs villes sont proches du centre.
	_shrink_vs_world(g)
	# Pas de saisons en VS : une seule bataille jusqu'au vainqueur.
	g.season_remaining = 1.0e9
	var peers: Dictionary = {}
	for p in players:
		var pid: int = int(p)
		if pid > 1:
			# VS : capitales regroupees pres du centre pour des batailles rapides.
			_assign_city(g, pid, -1, true)
			peers[pid] = true
	_party_worlds[mid] = {
		"game": g, "peers": peers,
		"eliminated": {}, "toast": "",
		"over": false, "vs_winner": "", "over_timer": 0.0,
		"is_vs": true,
	}
	_broadcast_snapshots()
	print("SERVER: partie \"%s\" demarree -- %d joueur(s), monde reduit (%d villes)." % [match_dict.get("name", "?"), players.size(), g.cities.size()])


## Rayon (px) du monde d'une partie VS : carte reduite, joueurs proches.
const VS_RADIUS := 2000.0

func _shrink_vs_world(g: GameState) -> void:
	## Ne garde que les villes proches du centre => carte plus petite et
	## concentration des affrontements entre joueurs.
	var keep: Array = []
	for c: CityNode in g.cities:
		if c.map_pos.distance_to(Vector2.ZERO) <= VS_RADIUS:
			keep.append(c)
	if keep.size() < 8:
		return   # trop peu de villes proches : on garde le monde entier
	var keep_ids: Dictionary = {}
	for c: CityNode in keep:
		keep_ids[c.id] = true
	g.cities = keep
	for zi: int in g.zones.size():
		g.zones[zi]["city_ids"] = []
	for c: CityNode in g.cities:
		var zi: int = int(g._city_zone.get(c.id, 0))
		g.zones[zi]["city_ids"].append(c.id)
	for cid: int in g._city_zone.keys():
		if not keep_ids.has(cid):
			g._city_zone.erase(cid)
	print("SERVER: monde VS reduit a %d villes (rayon %.0f px)." % [g.cities.size(), VS_RADIUS])


func _cities_of(g: GameState, pid: int) -> int:
	var n := 0
	for c: CityNode in g.cities:
		if c.owner == CityNode.OWNER_PLAYER and c.controller == pid:
			n += 1
	return n


func _broadcast_toast(w: Dictionary, msg: String) -> void:
	w.toast = msg
	print("SERVER: %s" % msg)


func _vs_lifecycle(w: Dictionary, mid: int, delta: float) -> void:
	## Declare le vainqueur unique quand un seul joueur a encore des villes,
	## elimine ceux qui n'en ont plus, puis ferme la partie.
	if w.over:
		w.over_timer += delta
		if w.over_timer >= 7.0:
			_end_vs_match(w, mid)
		return
	var active: Array = []
	for pid: int in w.peers.keys():
		if _cities_of(w.game, pid) > 0:
			active.append(pid)
		elif not w.eliminated.has(pid):
			w.eliminated[pid] = true
			_net.call("rpc_vs_eliminated", pid)
			var nm: String = _net.call("get_peer_name", pid)
			print("SERVER: VS %s: %s elimine." % [mid, nm])
			_broadcast_toast(w, "💀 %s est éliminé !" % nm)
	if active.size() == 1:
		var winner: int = int(active[0])
		w.over = true
		w.vs_winner = str(_net.call("get_peer_name", winner))
		print("SERVER: VS %s: %s a gagne !" % [mid, w.vs_winner])
		_broadcast_toast(w, "🏆 %s a gagné la partie !" % w.vs_winner)
	elif active.is_empty() and not w.peers.is_empty():
		w.over = true
		w.over_timer = 7.0


func _end_vs_match(w: Dictionary, mid: int) -> void:
	_net.call("close_match", mid)
	w.game.queue_free()
	_party_worlds.erase(mid)
	print("SERVER: VS %s terminee, monde ferme." % mid)


# ------------------------------------------------------------- villes

## Attribue une capitale au joueur. Si zone_idx >= 0, le choix se limite a
## cette zone physique (choix de zone de depart). Si close_spawn est vrai
## (Parties VS), on REGROUPE les capitales pres du centre pour des batailles
## rapides au lieu de les eloigner au maximum.
func _assign_city(g: GameState, peer_id: int, zone_idx: int = -1, close_spawn: bool = false) -> void:
	if g == null:
		return
	# Si le joueur possede deja une ville (reconnexion), on la lui rend.
	for c: CityNode in g.cities:
		if c.owner == CityNode.OWNER_PLAYER and c.controller == peer_id:
			c.revealed = true
			g.node_changed.emit(c.id)
			return
	var best: CityNode = null
	var best_score := -INF
	if close_spawn:
		best_score = INF   # on va chercher le MINIMUM de distance au centre
	for c: CityNode in g.cities:
		if c.owner != CityNode.OWNER_NEUTRAL or c.controller != 0:
			continue
		if zone_idx >= 0 and g.zone_of(c) != zone_idx:
			continue   # choix de zone : restreindre a cette zone
		if close_spawn:
			# VS : capitale au plus pres du centre => les joueurs se rencontrent vite.
			var d0: float = c.map_pos.distance_to(Vector2.ZERO)
			if d0 < best_score:
				best_score = d0
				best = c
			continue
		# Sinon (Tournoi) : on attribue une ville NEUTRE LIBRE, la plus eloignee
		# possible des villes des autres joueurs => apparition DISTINCTE sur la carte.
		var min_d := INF
		var others := 0
		for o: CityNode in g.cities:
			if o.owner == CityNode.OWNER_PLAYER and o.controller > 1:
				others += 1
				var dd: float = c.map_pos.distance_to(o.map_pos)
				if dd < min_d:
					min_d = dd
		var score: float = c.map_pos.distance_to(Vector2.ZERO) if others == 0 else min_d
		if g.zone_position_of(c) <= g._zone_front:
			score += 2000.0   # on prefere la zone actuelle (jouable)
		if score > best_score:
			best_score = score
			best = c
	if best == null:
		print("SERVER: aucune ville libre a attribuer au joueur %d." % peer_id)
		return
	best.owner = CityNode.OWNER_PLAYER
	if close_spawn:
		# Force egale au depart en VS : meme niveau, meme garnison pour tous.
		best.level = 1
		best.garrison = 300
	else:
		best.garrison = maxi(best.garrison, 300)
	best.controller = peer_id
	best.revealed = true
	g.node_changed.emit(best.id)
	print("SERVER: %s attribuee au joueur %d (apparition %s)." % [best.node_name, peer_id, "regroupee VS" if close_spawn else "distincte"])


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
		zname = str(g.zones[g.zone_physical(g._zone_front)]["name"])
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
		"names": names, "toast": _toast,
	}


func _broadcast_snapshots() -> void:
	var known: PackedInt32Array = multiplayer.get_peers()
	if game != null and not _tournament_peers.is_empty():
		var tsnap: Dictionary = _build_snapshot(game)
		for pid in _tournament_peers:
			if int(pid) > 1 and int(pid) in known and _ready_peers.has(pid):
				_recv_snapshot.rpc_id(int(pid), tsnap)
		_toast = ""   # toast consomme apres une diffusion
	for wid in _party_worlds:
		var w: Dictionary = _party_worlds[wid]
		if w.peers.is_empty():
			continue
		var psnap: Dictionary = _build_snapshot(w.game)
		# Snapshot specifique a la partie (toast + fin de partie VS).
		psnap["toast"] = w.get("toast", "")
		w.toast = ""
		psnap["vs_over"] = bool(w.get("over", false))
		psnap["vs_winner"] = str(w.get("vs_winner", ""))
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
	# En VS (tous contre tous, dernier survivant), pas d'alliances.
	if bool(w.get("is_vs", false)):
		return
	w.game.recruit_ally()
