class_name GameState
extends Node
## Authoritative single-player simulation. Holds all cities, armies, time and
## player meta, and advances the core loop each frame.

signal node_changed(city_id: int)
signal army_launched(army: Army)
signal army_arrived(army: Army, attacker_won: bool)
signal log_message(text: String)
signal warning(text: String)
signal game_over
signal season_ended(rank_index: int, gems_reward: int, realm: int, realm_result: String)
signal alliance_changed
signal tournament_changed
signal peace_ended
signal zone_discovered(zone_index: int)

const ARMY_SPEED := 90.0   # px per second (before speed_mult)
const AI_INTERVAL := 2.5   # seconds between AI decision passes
const ENEMY_PRODUCTION := 1.15   # enemy cities grow a bit faster than the player (tuned down from 1.3)
# Season length is tunable via project setting "game/season_length" (seconds).
const DEFAULT_SEASON_LENGTH := 300.0

const RANKS := ["Bronze", "Argent", "Or", "Platine", "Diamant"]
const RANK_MIN_LEVELS := [2, 4, 7, 10, 14]   # total city levels required
const RANK_GEMS := [20, 40, 70, 110, 160]    # gems reward per rank
const UPGRADE_BASE := 80     # gold cost to upgrade = UPGRADE_BASE * current level

# Kingdom ladder ("Royaumes") — each realm is one step toward the ultimate
# tournament. Conquer everything to be promoted; fail and you restart the climb.
const REALMS := ["Cendres", "Bronze", "Argent", "Or", "Platine", "Diamant", "Seigneur des Royaumes"]

# ---- Evolving world: the map is split into zones. Zone 0 is the starting
# kingdom (fully visible); outer zones are ruled by evolved AI lords and stay
# hidden (fog of war) until the previous zone is conquered and they are
# discovered. Deterministic layout now, architected for procedural later.
const REVEAL_RADIUS := 620.0

const ZONE0_LAYOUT := [
	{"name": "Fort-Sud",    "pos": Vector2(0, 0),       "owner": CityNode.OWNER_PLAYER, "level": 3},
	{"name": "Ombrage",     "pos": Vector2(420, -120),  "owner": CityNode.OWNER_ENEMY,  "level": 2},
	{"name": "Rivage-Or",   "pos": Vector2(470, 170),   "owner": CityNode.OWNER_ENEMY,  "level": 1},
	{"name": "Vallée-Verte","pos": Vector2(-420, 150),  "owner": CityNode.OWNER_NEUTRAL,"level": 1},
	{"name": "Pic-Aigu",    "pos": Vector2(-480, -140), "owner": CityNode.OWNER_NEUTRAL,"level": 1},
	{"name": "Croisé",      "pos": Vector2(-80, -260),  "owner": CityNode.OWNER_NEUTRAL,"level": 2},
	{"name": "Tour-Nord",   "pos": Vector2(140, -300),  "owner": CityNode.OWNER_NEUTRAL,"level": 1},
	{"name": "Ferme-Lointaine", "pos": Vector2(180, 300), "owner": CityNode.OWNER_NEUTRAL,"level": 1},
	{"name": "Brume",       "pos": Vector2(-170, 400),  "owner": CityNode.OWNER_NEUTRAL,"level": 1},
	{"name": "Halte-Midi",  "pos": Vector2(330, -340),  "owner": CityNode.OWNER_NEUTRAL,"level": 1},
]

const WORLD_ZONES := [
	{"name": "Le Cœur des Cendres",  "lord": "",               "lord_level": 0,  "count": 8,  "r_min": 0.0,   "r_max": 560.0,  "lord_cities": 0},
	{"name": "Les Marches du Duc",   "lord": "Duc Eldric",     "lord_level": 6,  "count": 10, "r_min": 950.0,  "r_max": 1350.0, "lord_cities": 2},
	{"name": "Le Duché de Veyra",    "lord": "Comtesse Veyra", "lord_level": 9,  "count": 12, "r_min": 1550.0, "r_max": 2050.0, "lord_cities": 3},
	{"name": "Le Royaume de Maldur", "lord": "Roi Maldur",     "lord_level": 12, "count": 14, "r_min": 2200.0, "r_max": 2700.0, "lord_cities": 3},
	{"name": "Les Terres Sacrées",   "lord": "Reine des Cendres", "lord_level": 14, "count": 16, "r_min": 2850.0, "r_max": 3400.0, "lord_cities": 4},
	{"name": "La Couronne Déchue",   "lord": "Dragonlord",     "lord_level": 16, "count": 18, "r_min": 3550.0, "r_max": 4100.0, "lord_cities": 5},
]

var time: float = 0.0
var cities: Array = []     # of CityNode
var armies: Array = []     # of Army
var player: PlayerStats = PlayerStats.new()
var _next_id: int = 0
var _ai_timer: float = 0.0

# Zones: the evolving world (see WORLD_ZONES). `_zone_front` is the zone the
# player is currently conquering; the next one is discovered once it's cleared.
var zones: Array = []               # of {id, name, lord, lord_level, city_ids, unlocked}
var _zone_front: int = 0            # progression index of the zone being conquered
var _city_zone: Dictionary = {}     # city_id -> zone index
var _reveal_timer: float = 0.0      # local fog-of-war proximity reveal cadence
var _front_announced: bool = false  # true once the frontier-cleared toast fired
# When true (Conquest persistent world), the frontier advances from the OUTER
# zones INWARD, so the CENTER zone is the final one. Solo keeps center-outward.
var center_final := false


## Physical zone index for a progression index. In the Conquest world the
## progression goes outer edge -> center (the final zone).
func zone_physical(prog: int) -> int:
	if center_final:
		return WORLD_ZONES.size() - 1 - prog
	return prog


## Direction-aware position of a city along the conquest path: 0 is the START
## zone (center for Solo, outer edge for Conquest) and it increases as you
## advance toward the FINAL zone. Use this for all frontier comparisons.
func zone_position_of(c: CityNode) -> int:
	return zone_physical(zone_of(c))

# Season state
var season_number: int = 1
var season_remaining: float = DEFAULT_SEASON_LENGTH
var best_rank: int = 0
var seasons_won: int = 0

# Tutorial "peace" phase: while true, enemies never attack the player.
var peace: bool = true

# Realm state (persists across seasons)
var realm: int = 0
var best_realm: int = 0
var eliminated: bool = false   # true when the player lost everything this season

# Alliance (allied AI lords who fight the enemy at your side)
const ALLY_COST_GOLD := 400
const MAX_ALLIES := 3
const ALLY_NAMES := ["Aldric", "Béline", "Cédric", "Donia", "Éverard"]
var allies: Array = []   # of {"name": String, "home_id": int}
var _ally_ai_timer: float = 0.0

# Tournament of the Lord of Realms (top-realm arena)
const TOURNAMENT_CHAMPIONS := ["Chevalier d'Acier", "Mage des Runes", "Reine des Cendres", "Dragonlord", "Roi Déchu"]
const CHAMPION_BASE_DEF := 700
const CHAMPION_DEF_STEP := 800
const TOURNAMENT_WIN_GEMS := 200
var tournament_wins: int = 0
var tournament_won: bool = false

# Lifetime (persist across all seasons -> "Top des Seigneurs")
var best_dominance: int = 0
var total_gems_earned: int = 0
var total_conquests: int = 0
var season_history: Array = []   # of {season, rank, dominance, cities}

# Battle log (most recent first)
var battle_log: Array = []


func _ready() -> void:
	_build_map()
	season_remaining = season_length()


func season_length() -> float:
	return float(ProjectSettings.get_setting("game/season_length", DEFAULT_SEASON_LENGTH))


func _process(delta: float) -> void:
	time += delta
	_tick(delta)
	season_remaining -= delta
	if season_remaining <= 0.0:
		_end_season()


# ---------------------------------------------------------------- setup

func _build_map() -> void:
	cities.clear()
	_next_id = 0
	_city_zone = {}
	_front_announced = false
	zones = []
	for zi in range(WORLD_ZONES.size()):
		var zdef: Dictionary = WORLD_ZONES[zi]
		zones.append({"id": zi, "name": zdef["name"], "lord": zdef["lord"],
			"lord_level": zdef["lord_level"], "city_ids": [], "unlocked": zone_physical(zi) <= _zone_front})

	for zi in range(WORLD_ZONES.size()):
		var zdef: Dictionary = WORLD_ZONES[zi]
		var conquered: bool = zone_physical(zi) < _zone_front   # already won, behind the frontier
		var is_front: bool = zone_physical(zi) == _zone_front   # the live battle zone this season
		for spec in _zone_city_specs(zi, zdef):
			var c := CityNode.new()
			c.id = _next_id
			_next_id += 1
			c.node_name = spec["name"]
			c.map_pos = spec["pos"]
			c.level = spec["level"]
			if conquered:
				# Settled empire behind you: friendly, visible, still productive.
				c.owner = CityNode.OWNER_PLAYER
				c.garrison = 220
				c.revealed = true
			elif is_front:
				c.owner = spec["owner"]
				c.garrison = spec["garrison"]
				c.revealed = true
			else:
				# Locked zone: hidden by the fog of war until its zone is reached.
				c.owner = spec["owner"]
				c.garrison = spec["garrison"]
				c.revealed = false
			cities.append(c)
			_city_zone[c.id] = zi
			zones[zi]["city_ids"].append(c.id)


## Deterministic per-zone city specs (names, positions, owners, strength).
## Outer zones are rings ruled by evolved AI lords; zone 0 is the fixed core.
func _zone_city_specs(zi: int, zdef: Dictionary) -> Array:
	var out: Array = []
	if zi == 0:
		for entry in ZONE0_LAYOUT:
			var fac: int = entry["owner"]
			var lvl: int = entry["level"]
			var gar: int
			if fac == CityNode.OWNER_ENEMY:
				lvl = mini(5, lvl + realm)
				gar = 150 + realm * 25
			else:
				gar = 300 if fac == CityNode.OWNER_PLAYER else 150
			out.append({"name": entry["name"], "pos": entry["pos"], "owner": fac,
				"level": lvl, "garrison": gar})
		return out
	var n_cities: int = zdef["count"]
	var lord_cities: int = zdef["lord_cities"]
	var lord_scale: int = zdef["lord_level"] + realm
	for i in range(n_cities):
		var t: float = float(i) / float(n_cities)
		var angle: float = TAU * t + float(zi) * 0.85
		var radius: float = lerpf(zdef["r_min"], zdef["r_max"],
			0.35 + 0.3 * absf(2.0 * t - 1.0))
		var spec := {}
		spec["pos"] = Vector2(cos(angle), sin(angle) * 0.85) * radius
		if i < lord_cities:
			spec["owner"] = CityNode.OWNER_ENEMY
			spec["level"] = mini(15, lord_scale + (i % 3))
			spec["garrison"] = 250 + lord_scale * 25 + (i % 3) * 60
			spec["name"] = "%s-%d" % [zdef["lord"].split(" ")[-1], i + 1]
		else:
			spec["owner"] = CityNode.OWNER_NEUTRAL
			spec["level"] = 1 + (i % 3)
			spec["garrison"] = 150 + (i % 2) * 50
			spec["name"] = "Avant-poste %s-%d" % [zdef["name"].split(" ")[-1], i + 1]
		out.append(spec)
	return out


func zone_of(c: CityNode) -> int:
	return int(_city_zone.get(c.id, 0))


## True when every city of the current frontier zone is friendly (player+ally).
func _front_cleared() -> bool:
	if _zone_front >= zones.size():
		return true  # whole world conquered — nothing left to fight
	var ids: Array = zones[zone_physical(_zone_front)]["city_ids"]
	for cid in ids:
		var c: CityNode = get_city(cid)
		if c == null or not (c.owner == CityNode.OWNER_PLAYER or c.owner == CityNode.OWNER_ALLY):
			return false
	return true


func _update_reveals() -> void:
	# Local fog of war: in unlocked zones, cities are revealed when they are
	# owned by the player/ally or close to a friendly city.
	for c: CityNode in cities:
		if c.revealed:
			continue
		if zone_position_of(c) > _zone_front:
			continue  # locked land stays hidden
		if c.owner == CityNode.OWNER_PLAYER or c.owner == CityNode.OWNER_ALLY:
			c.revealed = true
			node_changed.emit(c.id)
			continue
		for p: CityNode in cities:
			if (p.owner == CityNode.OWNER_PLAYER or p.owner == CityNode.OWNER_ALLY) \
					and p.map_pos.distance_to(c.map_pos) <= REVEAL_RADIUS:
				c.revealed = true
				node_changed.emit(c.id)
				break


func get_city(city_id: int) -> CityNode:
	for c: CityNode in cities:
		if c.id == city_id:
			return c
	return null


func find_city_at(pos: Vector2, radius: float = 40.0) -> CityNode:
	for c: CityNode in cities:
		if c.map_pos.distance_to(pos) <= radius:
			return c
	return null


func player_cities() -> Array:
	var out: Array = []
	for c: CityNode in cities:
		if c.owner == CityNode.OWNER_PLAYER:
			out.append(c)
	return out


# ---------------------------------------------------------------- tick

func _tick(delta: float) -> void:
	_produce(delta)
	_move_armies()
	_ai_tick(delta)
	_ally_ai_tick(delta)
	_reveal_timer += delta
	if _reveal_timer >= 1.0:
		_reveal_timer = 0.0
		_update_reveals()
	# Celebrate clearing the frontier before the season timer ends.
	if not _front_announced and _zone_front < zones.size() and _front_cleared():
		_front_announced = true
		_add_log("🎉 Frontière %s conquise ! La saison va se terminer et vous serez promu."
			% zones[zone_physical(_zone_front)]["name"])


func end_peace() -> void:
	if not peace:
		return
	peace = false
	peace_ended.emit()
	_add_log("Le temps de paix est terminé : les ennemis peuvent vous attaquer !")


func _produce(delta: float) -> void:
	for c: CityNode in cities:
		if c.owner == CityNode.OWNER_NEUTRAL:
			continue
		var mult: float = player.production_mult() if c.owner == CityNode.OWNER_PLAYER else ENEMY_PRODUCTION + float(realm) * 0.05
		var rate := c.production_per_sec() * mult
		var cap := int(float(c.storage_cap()) * (player.storage_mult() if c.owner == CityNode.OWNER_PLAYER else 1.0))
		# Fractions accumulate so small per-frame deltas don't lose troops.
		c.prod_buf += rate * delta
		var gained := int(c.prod_buf)
		c.prod_buf -= gained
		c.garrison = mini(c.garrison + gained, cap)
		# gold income from player cities (fractional accumulator, no loss).
		if c.owner == CityNode.OWNER_PLAYER:
			var gold_rate := 2.0 * (1.0 + float(c.level) * 0.5) * player.tax_mult()
			player.gold_buf += gold_rate * delta
			var g := int(player.gold_buf)
			if g > 0:
				player.gold_buf -= g
				player.gold += g
				player.gold_changed.emit(player.gold)
		# don't spam node_changed every frame for every city; handled by UI polling
		if c.owner == CityNode.OWNER_PLAYER or c.owner == CityNode.OWNER_ENEMY:
			if c.id % 2 == 0:
				node_changed.emit(c.id)


func _move_armies() -> void:
	var arrived: Array = []
	for a: Army in armies:
		if time >= a.arrival_time():
			arrived.append(a)
	for a in arrived:
		armies.erase(a)
		_resolve_combat(a)


# ---------------------------------------------------------------- AI

func _ai_tick(delta: float) -> void:
	if peace:
		return  # tutorial peace phase: enemies never attack the player
	_ai_timer += delta
	if _ai_timer < AI_INTERVAL:
		return
	_ai_timer = 0.0
	for c: CityNode in cities:
		if c.owner == CityNode.OWNER_ENEMY and zone_position_of(c) <= _zone_front:
			_ai_city_decide(c)


func _ai_city_decide(c: CityNode) -> void:
	# Hold back ~50% for defense, then unleash a big, coordinated strike at the
	# player's weakest city. Keeps real pressure without instant wipes.
	var holdback := int(float(c.garrison) * 0.5)
	var max_launch := c.garrison - holdback
	if max_launch < 100:
		return
	var target := _ai_pick_target(c)
	if target == null:
		return
	var frac := randf_range(0.6, 0.8)
	var count := int(float(max_launch) * frac)
	if count < 60:
		return
	launch_army(c.id, target.id, count)
	# Foreshadow so the player can react (visible warning) when their cities
	# are the ones about to be hit.
	if target.owner == CityNode.OWNER_PLAYER:
		warning.emit("⚠ Assaut massif en préparation sur %s !" % target.node_name)


func _ai_pick_target(c: CityNode) -> CityNode:
	# Aim at the player's most vulnerable city: prefers weak garrisons that are
	# within reach (distance weight + garrison weight).
	var best: CityNode = null
	var best_score := INF
	for t: CityNode in cities:
		if t.owner != CityNode.OWNER_PLAYER:
			continue
		if zone_position_of(t) > _zone_front:
			continue
		var score := c.map_pos.distance_to(t.map_pos) * 0.4 + float(t.garrison)
		if score < best_score:
			best_score = score
			best = t
	# If the AI is strong and has no player target in reach, it grabs neutral
	# or allied towns to expand instead (keeps the world alive & competitive).
	if best == null:
		for t: CityNode in cities:
			if t.owner != CityNode.OWNER_NEUTRAL and t.owner != CityNode.OWNER_ALLY:
				continue
			if zone_position_of(t) > _zone_front:
				continue
			var d: float = c.map_pos.distance_to(t.map_pos)
			if d < best_score:
				best_score = d
				best = t
	return best


# ---------------------------------------------------------------- alliance

func friendly_cities() -> Array:
	var out: Array = []
	for c: CityNode in cities:
		if c.owner == CityNode.OWNER_PLAYER or c.owner == CityNode.OWNER_ALLY:
			out.append(c)
	return out


func ally_home_city(ally: Dictionary) -> CityNode:
	var c := get_city(ally.get("home_id", -1))
	if c == null or c.owner != CityNode.OWNER_ALLY:
		return null
	return c


func recruit_ally() -> bool:
	if allies.size() >= MAX_ALLIES:
		return false
	if player.gold < ALLY_COST_GOLD:
		return false
	player.gold -= ALLY_COST_GOLD
	player.gold_changed.emit(player.gold)
	var ally_name: String = ALLY_NAMES[allies.size() % ALLY_NAMES.size()]
	var ally := {"name": ally_name, "home_id": -1}
	# give the new lord a neutral home closest to the player
	var best: CityNode = null
	var best_d := INF
	for c: CityNode in cities:
		if c.owner != CityNode.OWNER_NEUTRAL:
			continue
		if zone_position_of(c) > _zone_front:
			continue  # never home an ally in undiscovered land
		var d := c.map_pos.distance_to(Vector2.ZERO)
		if d < best_d:
			best_d = d
			best = c
	if best != null:
		best.owner = CityNode.OWNER_ALLY
		best.garrison = maxi(best.garrison, 140)
		ally["home_id"] = best.id
		node_changed.emit(best.id)
	allies.append(ally)
	alliance_changed.emit()
	_add_log("%s rejoint votre alliance !" % ally_name)
	return true


func _ally_ai_tick(delta: float) -> void:
	_ally_ai_timer += delta
	if _ally_ai_timer < 5.0:
		return
	_ally_ai_timer = 0.0
	for ally: Dictionary in allies:
		_ally_city_decide(ally)


func _ally_city_decide(ally: Dictionary) -> void:
	var home := ally_home_city(ally)
	if home == null:
		return
	var max_launch := home.garrison - 60
	if max_launch < 60:
		return
	var target := _ai_pick_enemy(home)
	if target == null:
		return
	# Allies help but must not carry the campaign: send a modest share.
	var count := int(float(max_launch) * 0.35)
	if count < 20:
		return
	launch_army(home.id, target.id, count)


func _ai_pick_enemy(c: CityNode) -> CityNode:
	var best: CityNode = null
	var best_dist := INF
	for t: CityNode in cities:
		if t.owner != CityNode.OWNER_ENEMY:
			continue
		if zone_position_of(t) > _zone_front:
			continue
		var d: float = c.map_pos.distance_to(t.map_pos)
		if d < best_dist:
			best_dist = d
			best = t
	return best


# ---------------------------------------------------------------- tournament

func tournament_available() -> bool:
	return realm == REALMS.size() - 1


func champion_defense(index: int) -> int:
	return CHAMPION_BASE_DEF + index * CHAMPION_DEF_STEP


func total_player_force() -> int:
	var total := 0.0
	for c: CityNode in player_cities():
		total += float(c.garrison) * (1.0 + player.attack_bonus())
	return int(total)


func challenge_champion() -> bool:
	## Duel against the current champion using your combined army.
	if not tournament_available():
		return false
	var atk := float(total_player_force())
	var def := float(champion_defense(tournament_wins))
	if atk > def:
		tournament_wins += 1
		if tournament_wins >= TOURNAMENT_CHAMPIONS.size():
			tournament_won = true
			player.gems += TOURNAMENT_WIN_GEMS * 2
			player.gems_changed.emit(player.gems)
			total_gems_earned += TOURNAMENT_WIN_GEMS * 2
			_add_log("🏆 VOUS RÉGNEZ SUR LE ROYAUME DES SEIGNEURS !")
		else:
			player.gems += TOURNAMENT_WIN_GEMS
			player.gems_changed.emit(player.gems)
			total_gems_earned += TOURNAMENT_WIN_GEMS
			_add_log("Champion « %s » vaincu ! (+%d gemmes)" % [TOURNAMENT_CHAMPIONS[tournament_wins - 1], TOURNAMENT_WIN_GEMS])
		tournament_changed.emit()
		return true
	else:
		realm = maxi(0, realm - 1)
		tournament_wins = 0
		tournament_changed.emit()
		_add_log("Vous êtes vaincu au tournoi… vous retombez au Royaume de %s." % REALMS[realm])
		return false


# ---------------------------------------------------------------- combat

func _hostile_to(attacker: int, target: int) -> bool:
	# Neutral cities are a conquest target for every faction.
	if target == CityNode.OWNER_NEUTRAL:
		return true
	# A faction never fights its own cities.
	if target == attacker:
		return false
	# The player and the allied lords are friends — they never fight each other.
	if (attacker == CityNode.OWNER_PLAYER and target == CityNode.OWNER_ALLY) \
		or (attacker == CityNode.OWNER_ALLY and target == CityNode.OWNER_PLAYER):
		return false
	return true


func launch_army(from_id: int, to_id: int, troops: int) -> Army:
	var src := get_city(from_id)
	var dst := get_city(to_id)
	if src == null or dst == null or troops <= 0:
		return null
	# No self-attack and no friendly-fire: a faction can never attack its own
	# cities, and the player/ally alliance can never attack each other.
	if src.id == dst.id or not _hostile_to(src.owner, dst.owner):
		return null
	# Undiscovered land: you cannot send armies into a locked (hidden) zone.
	if zone_position_of(src) > _zone_front or zone_position_of(dst) > _zone_front:
		return null
	if not dst.revealed:
		dst.revealed = true
		node_changed.emit(dst.id)
	var dist := src.map_pos.distance_to(dst.map_pos)
	var travel := dist / (ARMY_SPEED * player.speed_mult())
	var army := Army.new()
	army.from_id = from_id
	army.to_id = to_id
	army.faction = src.owner
	army.troops = troops
	army.depart_time = time
	army.travel_time = travel
	src.garrison -= troops
	armies.append(army)
	army_launched.emit(army)
	_add_log("Armée de %d envoyée de %s vers %s (%.0fs)" % [troops, src.node_name, dst.node_name, travel])
	if dst.owner == CityNode.OWNER_PLAYER and src.owner == CityNode.OWNER_ENEMY:
		warning.emit("⚠ Attaque imminente sur %s !" % dst.node_name)
	return army


func travel_time_between(from_id: int, to_id: int) -> float:
	var src := get_city(from_id)
	var dst := get_city(to_id)
	if src == null or dst == null:
		return 0.0
	return src.map_pos.distance_to(dst.map_pos) / (ARMY_SPEED * player.speed_mult())


func _resolve_combat(a: Army) -> void:
	var target := get_city(a.to_id)
	if target == null:
		return
	# Player hero bonuses only apply to the player's own armies and cities.
	var atk_hero := (1.0 + player.attack_bonus()) if a.faction == CityNode.OWNER_PLAYER else 1.0
	var atk := float(a.troops) * atk_hero
	var def_hero := (1.0 + player.defense_bonus()) if target.owner == CityNode.OWNER_PLAYER else 1.0
	var city_def := target.defense_city_bonus()
	if target.owner == CityNode.OWNER_PLAYER:
		city_def *= (1.0 + player.extra_city_defense())
	var def := float(target.garrison) * def_hero * city_def

	var attacker_won := atk > def
	if attacker_won:
		var remaining_raw := (atk - def) / maxf(atk_hero, 1.0)
		target.owner = a.faction
		target.garrison = int(remaining_raw)
		target.prod_buf = 0.0
		target.revealed = true
		if a.faction == CityNode.OWNER_PLAYER:
			# In multiplayer the conqueror keeps controlling the captured city.
			var src_c: CityNode = get_city(a.from_id)
			if src_c != null:
				target.controller = src_c.controller
			total_conquests += 1
			var xp := 20 + target.level * 15
			var gold := int(remaining_raw * 0.5 * player.gold_pillage_mult())
			player.gain_xp(xp)
			player.gold += gold
			player.gold_changed.emit(player.gold)
			_add_log("Victoire ! %s conquise (+%d XP, +%d or)" % [target.node_name, xp, gold])
		else:
			_add_log("%s est tombée aux mains de l'ennemi !" % target.node_name)
			if a.faction == CityNode.OWNER_ENEMY and player_cities().is_empty():
				eliminated = true
				game_over.emit()
	else:
		var loss_frac := atk / def
		var loss := int(float(target.garrison) * loss_frac * (1.0 - player.loss_reduction()))
		target.garrison = maxi(1, target.garrison - loss)
		if a.faction == CityNode.OWNER_PLAYER:
			var xp := 5 + target.level * 3
			player.gain_xp(xp)
			_add_log("Attaque repoussée sur %s (perte de %d garnison, +%d XP)" % [target.node_name, loss, xp])
		else:
			_add_log("Votre garnison de %s a repoussé une attaque (-%d)" % [target.node_name, loss])
	army_arrived.emit(a, attacker_won)
	node_changed.emit(target.id)


# ---------------------------------------------------------------- actions

func upgrade_city(city_id: int) -> bool:
	var c := get_city(city_id)
	if c == null or c.owner != CityNode.OWNER_PLAYER:
		return false
	var cost := UPGRADE_BASE * c.level
	if player.gold < cost:
		return false
	player.gold -= cost
	player.gold_changed.emit(player.gold)
	c.level += 1
	node_changed.emit(c.id)
	_add_log("%s améliorée au niveau %d (-%d or)" % [c.node_name, c.level, cost])
	return true


func upgrade_cost(city_id: int) -> int:
	var c := get_city(city_id)
	if c == null:
		return 0
	return UPGRADE_BASE * c.level


# ---------------------------------------------------------------- season

func dominance_score() -> int:
	## Higher = stronger position: sum of the levels of cities you control.
	var s := 0
	for c: CityNode in player_cities():
		s += c.level
	return s


func current_rank_index() -> int:
	var d := dominance_score()
	var idx := 0
	for i in range(RANK_MIN_LEVELS.size()):
		if d >= RANK_MIN_LEVELS[i]:
			idx = i
	return idx


func _end_season() -> void:
	var rank := current_rank_index()
	if rank > best_rank:
		best_rank = rank
	var reward: int = RANK_GEMS[rank]
	total_gems_earned += reward
	player.gems += reward
	player.gems_changed.emit(player.gems)
	if rank >= 3:
		seasons_won += 1

	# Frontier ladder: clear the current frontier zone to be promoted. The
	# frontier persists across seasons (one zone = one step toward the top).
	var cleared := _front_cleared()
	var realm_result := ""
	if cleared:
		seasons_won += 1
		if _zone_front < zones.size() - 1:
			var cleared_name: String = zones[zone_physical(_zone_front)]["name"]
			_zone_front += 1
			realm = mini(_zone_front, REALMS.size() - 1)
			if realm > best_realm:
				best_realm = realm
			realm_result = "Promu au Royaume de %s !" % REALMS[realm]
			_add_log("🎉 %s conquise ! Promu au Royaume de %s" % [cleared_name, REALMS[realm]])
			zone_discovered.emit(_zone_front)
		else:
			_zone_front += 1   # == zones.size(): the whole world is yours
			realm = REALMS.size() - 1
			best_realm = maxi(best_realm, realm)
			realm_result = "Vous régnez au sommet : le Royaume des Seigneurs !"
			_add_log("🌍 Le monde entier est à vous ! Seigneur des Royaumes.")
	elif eliminated:
		realm = 0
		_zone_front = 0
		realm_result = "Vous retombez au Royaume des Cendres. Recommencez l'ascension !"
	else:
		realm_result = "Vous restez au Royaume de %s. Conquérez la zone « %s » pour monter !" \
			% [REALMS[realm], zones[zone_physical(_zone_front)]["name"]]

	_add_log("Saison %d terminée — rang %s (+%d gemmes)" % [season_number, RANKS[rank], reward])
	# The tournament only lives at the top realm; falling below resets it.
	if realm < REALMS.size() - 1:
		tournament_wins = 0
	_reset_map(rank, realm_result)


func _reset_map(rank: int, realm_result: String) -> void:
	## Fresh season map — the Lord keeps level, skills, equipment, gold & gems.
	var d := dominance_score()
	best_dominance = maxi(best_dominance, d)
	season_history.push_front({
		"season": season_number,
		"rank": rank,
		"dominance": d,
		"cities": player_cities().size(),
		"realm": realm,
	})
	if season_history.size() > 30:
		season_history.resize(30)
	eliminated = false
	armies.clear()
	cities.clear()
	_next_id = 0
	season_number += 1
	season_remaining = season_length()
	_build_map()
	# Rebase allied lords onto fresh neutral towns for the new season.
	for ally: Dictionary in allies:
		var best: CityNode = null
		var best_d := INF
		for c: CityNode in cities:
			if c.owner != CityNode.OWNER_NEUTRAL:
				continue
			if zone_position_of(c) > _zone_front:
				continue
			var dist := c.map_pos.distance_to(Vector2.ZERO)
			if dist < best_d:
				best_d = dist
				best = c
		if best != null:
			best.owner = CityNode.OWNER_ALLY
			best.garrison = 140
			ally["home_id"] = best.id
	for c: CityNode in cities:
		node_changed.emit(c.id)
	season_ended.emit(rank, RANK_GEMS[rank], realm, realm_result)


func _add_log(text: String) -> void:
	battle_log.push_front(text)
	if battle_log.size() > 50:
		battle_log.resize(50)
	log_message.emit(text)


# ---------------------------------------------------------------- persistence
## Save/load the full world state so a persistent Conquest server can resume
## where it left off across restarts.

const SAVE_VERSION := 1


func to_dict() -> Dictionary:
	var city_arr: Array = []
	for c: CityNode in cities:
		city_arr.append({
			"id": c.id, "name": c.node_name, "px": c.map_pos.x, "py": c.map_pos.y,
			"owner": c.owner, "level": c.level, "garrison": c.garrison,
			"prod_buf": c.prod_buf, "revealed": c.revealed, "controller": c.controller,
			"zone": int(_city_zone.get(c.id, 0)),
		})
	var army_arr: Array = []
	for a: Army in armies:
		army_arr.append({
			"from": a.from_id, "to": a.to_id, "faction": a.faction,
			"troops": a.troops, "depart": a.depart_time, "travel": a.travel_time,
		})
	return {
		"version": SAVE_VERSION,
		"time": time,
		"cities": city_arr,
		"armies": army_arr,
		"next_id": _next_id,
		"zone_front": _zone_front,
		"season_number": season_number,
		"season_remaining": season_remaining,
		"realm": realm,
		"best_realm": best_realm,
		"best_rank": best_rank,
		"seasons_won": seasons_won,
		"eliminated": eliminated,
		"allies": allies,
		"tournament_wins": tournament_wins,
		"total_gems_earned": total_gems_earned,
		"total_conquests": total_conquests,
		"best_dominance": best_dominance,
		"season_history": season_history,
		"battle_log": battle_log,
		"player": {
			"level": player.level, "xp": player.xp, "gold": player.gold,
			"gems": player.gems, "gold_buf": player.gold_buf,
			"skill_points": player.skill_points,
			"skills": player.skills, "inventory": player.inventory,
			"equipped": player.equipped,
		},
	}


## Rebuild the whole world from a dict previously returned by to_dict().
func from_dict(data: Dictionary) -> void:
	cities.clear()
	armies.clear()
	_next_id = int(data.get("next_id", 0))
	time = float(data.get("time", 0.0))
	_zone_front = int(data.get("zone_front", 0))
	season_number = int(data.get("season_number", 1))
	season_remaining = float(data.get("season_remaining", season_length()))
	realm = int(data.get("realm", 0))
	best_realm = int(data.get("best_realm", 0))
	best_rank = int(data.get("best_rank", 0))
	seasons_won = int(data.get("seasons_won", 0))
	eliminated = bool(data.get("eliminated", false))
	allies = (data.get("allies", []) as Array).duplicate(true)
	tournament_wins = int(data.get("tournament_wins", 0))
	total_gems_earned = int(data.get("total_gems_earned", 0))
	total_conquests = int(data.get("total_conquests", 0))
	best_dominance = int(data.get("best_dominance", 0))
	season_history = (data.get("season_history", []) as Array).duplicate(true)
	battle_log = (data.get("battle_log", []) as Array).duplicate(true)

	# Player meta.
	var pdata: Dictionary = data.get("player", {})
	player.level = int(pdata.get("level", 1))
	player.xp = int(pdata.get("xp", 0))
	player.gold = int(pdata.get("gold", 300))
	player.gems = int(pdata.get("gems", 60))
	player.gold_buf = float(pdata.get("gold_buf", 0.0))
	player.skill_points = int(pdata.get("skill_points", 0))
	for k in player.SKILLS:
		player.skills[k] = int(pdata.get("skills", {}).get(k, 0))
	player.inventory = (pdata.get("inventory", []) as Array).duplicate(true)
	player.equipped = (pdata.get("equipped", {}) as Dictionary).duplicate(true)

	# Cities.
	_city_zone = {}
	zones = []
	for zi in range(WORLD_ZONES.size()):
		var zdef: Dictionary = WORLD_ZONES[zi]
		zones.append({"id": zi, "name": zdef["name"], "lord": zdef["lord"],
			"lord_level": zdef["lord_level"], "city_ids": [], "unlocked": zone_physical(zi) <= _zone_front})
	for cd in (data.get("cities", []) as Array):
		var c := CityNode.new()
		c.id = int(cd["id"])
		c.node_name = str(cd["name"])
		c.map_pos = Vector2(float(cd["px"]), float(cd["py"]))
		c.owner = int(cd["owner"])
		c.level = int(cd["level"])
		c.garrison = int(cd["garrison"])
		c.prod_buf = float(cd["prod_buf"])
		c.revealed = bool(cd["revealed"])
		c.controller = int(cd["controller"])
		cities.append(c)
		var zi2: int = int(cd["zone"])
		_city_zone[c.id] = zi2
		zones[zi2]["city_ids"].append(c.id)

	# Armies.
	for ad in (data.get("armies", []) as Array):
		var a := Army.new()
		a.from_id = int(ad["from"])
		a.to_id = int(ad["to"])
		a.faction = int(ad["faction"])
		a.troops = int(ad["troops"])
		a.depart_time = float(ad["depart"])
		a.travel_time = float(ad["travel"])
		armies.append(a)
	_front_announced = false


func save_to_file(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(to_dict()))
	f.close()
	return true


func load_from_file(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var data: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (data is Dictionary):
		return false
	from_dict(data)
	return true
