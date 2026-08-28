extends Node
class_name BalanceSimulation
## Headless balance / difficulty simulation.
##
## Drives the REAL GameState with a competent bot player across many seasons and
## reports difficulty metrics: win/loss/stall per season, time to win, realm
## progression, economy & progression. This exercises the actual game code, so
## any imbalance found here is a real imbalance in the shipped game.

## How often the bot re-decides (seconds of game time).
const DECISION_INTERVAL := 0.3


## A reasonable, competent (not perfect) player. Used to probe difficulty.
class Bot:
	var game: GameState
	var recruit_allies: bool = true
	var max_allies: int = 2
	var peace_target: int = 3   # player cities before ending peace (0 = end now)
	var decision: float = 0.0

	func think(delta: float) -> void:
		decision += delta
		if decision < DECISION_INTERVAL:
			return
		decision = 0.0
		# Use the peace phase to expand into weak neutrals first (realistic).
		if game.peace and game.player_cities().size() >= peace_target:
			game.end_peace()
		_spend_skills()
		_recruit()
		_forge()
		_upgrade()
		_attack()

	func _spend_skills() -> void:
		# Economy & offense first, then defense — a sensible build order.
		var order: Array = [
			"recruitment", "armory", "brutal_assault", "fortify",
			"iron_garrison", "tax_collector", "rally", "war_vision",
			"supply_lines", "swift_march", "loss_reduction", "pillager",
		]
		for key: String in order:
			while game.player.can_upgrade_skill(key):
				game.player.upgrade_skill(key)

	func _recruit() -> void:
		if not recruit_allies:
			return
		if game.allies.size() < max_allies and game.player.gold >= GameState.ALLY_COST_GOLD:
			game.recruit_ally()

	func _forge() -> void:
		# Forge when we have a gem surplus (boosts the Lord permanently).
		if game.player.gems >= 100 and game.player.gold >= 150:
			game.player.forge(game.player.gold, game.player.gems)

	func _upgrade() -> void:
		# Upgrade the cheapest affordable player city first, keep a gold reserve.
		while true:
			var best: CityNode = null
			var best_cost: int = 1 << 30
			for c: CityNode in game.player_cities():
				var cost := game.upgrade_cost(c.id)
				if cost < best_cost:
					best_cost = cost
					best = c
			if best == null:
				break
			if game.player.gold < best_cost + 60:
				break
			game.upgrade_city(best.id)

	func _attack() -> void:
		# From each player city, hit the weakest non-friendly city if we can take
		# it with a margin while keeping a defensive reserve.
		for src: CityNode in game.player_cities():
			var target := _pick_target()
			if target == null:
				continue
			var atk_bonus: float = game.player.attack_bonus()
			var def: float = float(target.garrison) * target.defense_city_bonus()
			var needed := int(ceil(def / (1.0 + atk_bonus) * 1.25))
			if needed < 15:
				continue
			var reserve := int(float(src.garrison) * 0.25)
			if src.garrison - reserve < needed:
				continue
			game.launch_army(src.id, target.id, needed)

	func _pick_target() -> CityNode:
		var best: CityNode = null
		var best_score := INF
		for c: CityNode in game.cities:
			if c.owner == CityNode.OWNER_PLAYER or c.owner == CityNode.OWNER_ALLY:
				continue
			if game.zone_of(c) > game._zone_front:
				continue  # locked (undiscovered) zone — cannot be reached yet
			var eff: float = float(c.garrison) * c.defense_city_bonus()
			var score: float = eff * (0.85 if c.owner == CityNode.OWNER_NEUTRAL else 1.0)
			if score < best_score:
				best_score = score
				best = c
		return best


## Runs `num_seasons` seasons with a bot and returns a metrics dictionary.
func run(
	num_seasons: int = 4,
	season_len: float = 240.0,
	recruit_allies: bool = true,
	starting_realm: int = 0,
	max_allies: int = 2,
	peace_target: int = 3,
) -> Dictionary:
	var game := GameState.new()
	add_child(game)
	game.realm = clampi(starting_realm, 0, GameState.REALMS.size() - 1)
	# In some headless environments _ready() isn't auto-fired on add_child; make
	# sure the map exists so the first season is real.
	if game.cities.is_empty():
		game._build_map()
	# Peace stays active until the bot expands to `peace_target` player cities
	# (realistic use of the tutorial peace phase); peace_target=0 = full pressure.
	var bot := Bot.new()
	bot.game = game
	bot.recruit_allies = recruit_allies
	bot.max_allies = max_allies
	bot.peace_target = peace_target

	var report: Array = []
	var wins := 0
	var losses := 0
	var stalls := 0
	var total_time := 0.0
	var max_realm := 0
	var start_season := game.season_number
	var target_season := start_season + num_seasons
	var guard := 0

	while game.season_number < target_season:
		var s := game.season_number
		game.season_remaining = season_len
		var season_time := 0.0
		var won := false
		var lost := false
		var timed := false
		var snap := {"dom": 0, "my": 0, "ally": 0}
		while true:
			game._process(0.1)
			bot.think(0.1)
			season_time += 0.1
			if game.season_number > s:
				timed = true
				break
			if game._front_cleared():
				won = true
				break
			if game.eliminated:
				lost = true
				break
			if season_time > season_len + 5.0:
				timed = true
				break
			guard += 1
			if guard > 2_000_000:
				break
		# Snapshot the REAL ownership BEFORE forcing the season reset.
		if won or lost:
			snap = _snapshot(game)
		# Force the season to end cleanly so the next one starts.
		if not timed and game.season_number == s:
			game.season_remaining = 0.0
			game._process(0.1)

		if won:
			wins += 1
		elif lost:
			losses += 1
		else:
			stalls += 1
		max_realm = maxi(max_realm, game.realm)
		total_time += season_time

		report.append({
			"season": s,
			"won": won,
			"lost": lost,
			"time": season_time,
			"realm": game.realm,
			"level": game.player.level,
			"gold": game.player.gold,
			"gems": game.player.gems,
			"dominance": snap["dom"],
			"my_cities": snap["my"],
			"ally_cities": snap["ally"],
		})
		print("S%d: %-10s %6.0fs  realm=%-6s lvl=%2d dom=%d mine=%d allies=%d gold=%d" % [
			s,
			"VICTOIRE" if won else ("DÉFAITE" if lost else "TEMPORELLE"),
			season_time,
			GameState.REALMS[game.realm],
			game.player.level,
			snap["dom"],
			snap["my"],
			snap["ally"],
			game.player.gold,
		])

	return {
		"seasons": num_seasons,
		"recruit_allies": recruit_allies,
		"starting_realm": starting_realm,
		"max_allies": max_allies,
		"peace_target": peace_target,
		"wins": wins,
		"losses": losses,
		"stalls": stalls,
		"win_rate": float(wins) / float(maxi(1, num_seasons)),
		"avg_time": total_time / float(maxi(1, num_seasons)),
		"max_realm": max_realm,
		"per_season": report,
	}


## Ownership snapshot of the LIVE map (before any season reset).
func _snapshot(game: GameState) -> Dictionary:
	var my := 0
	var ally := 0
	for c in game.cities:
		if c.owner == CityNode.OWNER_PLAYER:
			my += 1
		elif c.owner == CityNode.OWNER_ALLY:
			ally += 1
	return {"dom": game.dominance_score(), "my": my, "ally": ally}
