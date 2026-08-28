class_name PlayerStats
extends RefCounted
## Player meta-progression: XP / level, skill tree (4 branches) and equipment.

signal level_up(new_level: int)
signal xp_changed(xp: int)
signal gold_changed(gold: int)
signal gems_changed(gems: int)
signal inventory_changed

const BRANCH_OFFENSIVE := "offensive"
const BRANCH_DEFENSIVE := "defensive"
const BRANCH_ECONOMY := "economy"
const BRANCH_COMMAND := "command"

# skill_key -> {branch, name, desc, max, per_level_percent}
const SKILLS := {
	"swift_march":     {"branch": BRANCH_OFFENSIVE, "name": "Marche Rapide",     "max": 5, "per": 0.08, "desc": "Vitesse des armées +8%/niv."},
	"brutal_assault":  {"branch": BRANCH_OFFENSIVE, "name": "Assaut Brutal",     "max": 5, "per": 0.05, "desc": "Attaque +5%/niv."},
	"pillager":        {"branch": BRANCH_OFFENSIVE, "name": "Pillard",           "max": 5, "per": 0.15, "desc": "Or pillé +15%/niv."},
	"iron_garrison":   {"branch": BRANCH_DEFENSIVE, "name": "Garnison de Fer",   "max": 5, "per": 0.05, "desc": "Défense héros +5%/niv."},
	"loss_reduction":  {"branch": BRANCH_DEFENSIVE, "name": "Réduction des Pertes", "max": 5, "per": 0.04, "desc": "Pertes défense -4%/niv."},
	"fortify":         {"branch": BRANCH_DEFENSIVE, "name": "Fortification",     "max": 5, "per": 0.04, "desc": "Bonus de niveau ville +4%/niv."},
	"recruitment":     {"branch": BRANCH_ECONOMY,   "name": "Recrutement",       "max": 5, "per": 0.10, "desc": "Production +10%/niv."},
	"armory":          {"branch": BRANCH_ECONOMY,   "name": "Armurerie",         "max": 5, "per": 0.10, "desc": "Capacité de stockage +10%/niv."},
	"tax_collector":   {"branch": BRANCH_ECONOMY,   "name": "Percepteur",        "max": 5, "per": 0.15, "desc": "Revenu d'or +15%/niv."},
	"war_vision":      {"branch": BRANCH_COMMAND,   "name": "Vision de Guerre",  "max": 5, "per": 0.04, "desc": "Défense de vos villes +4%/niv."},
	"rally":           {"branch": BRANCH_COMMAND,   "name": "Ralliement",        "max": 5, "per": 0.04, "desc": "Attaque (commandement) +4%/niv."},
	"supply_lines":    {"branch": BRANCH_COMMAND,   "name": "Lignes de Ravitaillement", "max": 5, "per": 0.05, "desc": "Vitesse +5%/niv."},
}

const RARITY_COMMON := 0
const RARITY_RARE := 1
const RARITY_EPIC := 2
const RARITY_LEGENDARY := 3
const RARITY_NAMES := ["Commun", "Rare", "Épique", "Légendaire"]

var level: int = 1
var xp: int = 0
var gold: int = 300
var gems: int = 60
var gold_buf: float = 0.0   # fractional gold-income accumulator (no truncation loss)
var skill_points: int = 0
var skills: Dictionary = {}          # skill_key -> invested level
var inventory: Array = []            # of item dicts
var equipped: Dictionary = {}        # slot -> item dict (weapon/armor/trinket)


func _init() -> void:
	for k in SKILLS:
		skills[k] = 0


func skill_level(key: String) -> int:
	return int(skills.get(key, 0))


func skill_percent(key: String) -> float:
	return skill_level(key) * float(SKILLS[key]["per"])


func xp_to_next() -> int:
	return 100 * level


func gain_xp(amount: int) -> void:
	xp += amount
	while xp >= xp_to_next():
		xp -= xp_to_next()
		level += 1
		skill_points += 1
		level_up.emit(level)
	xp_changed.emit(xp)


func can_upgrade_skill(key: String) -> bool:
	return skill_points > 0 and skill_level(key) < int(SKILLS[key]["max"])


func upgrade_skill(key: String) -> bool:
	if not can_upgrade_skill(key):
		return false
	skills[key] = skill_level(key) + 1
	skill_points -= 1
	return true


# ---- Combined multipliers (skills + equipment) ----

func _equip_bonus(stat: String) -> float:
	var total := 0.0
	for item in equipped.values():
		total += float(item.get(stat, 0.0))
	return total


func attack_bonus() -> float:
	return skill_percent("brutal_assault") + skill_percent("rally") + _equip_bonus("attack")


func defense_bonus() -> float:
	return skill_percent("iron_garrison") + skill_percent("war_vision") + _equip_bonus("defense")


func production_mult() -> float:
	return 1.0 + skill_percent("recruitment") + _equip_bonus("production")


func storage_mult() -> float:
	return 1.0 + skill_percent("armory")


func speed_mult() -> float:
	return 1.0 + skill_percent("swift_march") + skill_percent("supply_lines") + _equip_bonus("speed")


func gold_pillage_mult() -> float:
	return 1.0 + skill_percent("pillager")


func loss_reduction() -> float:
	return clampf(skill_percent("loss_reduction"), 0.0, 0.5)


func extra_city_defense() -> float:
	return skill_percent("fortify")


func tax_mult() -> float:
	return 1.0 + skill_percent("tax_collector")


# ---- Equipment / forge ----

func forge_cost() -> int:
	return 100 + 50 * inventory.size()


func forge(gold_available: int, gems_available: int) -> Dictionary:
	## Spend resources, produce a random item. Returns {} on failure, else the item.
	var cost := forge_cost()
	var gcost := 10 + inventory.size() * 5
	if gold_available < cost or gems_available < gcost:
		return {}
	gold -= cost
	gems -= gcost
	gold_changed.emit(gold)
	gems_changed.emit(gems)
	var item := _roll_item()
	inventory.append(item)
	inventory_changed.emit()
	_auto_equip(item)
	return item


func _roll_item() -> Dictionary:
	var r := randf()
	var rarity := RARITY_COMMON
	if r > 0.97:
		rarity = RARITY_LEGENDARY
	elif r > 0.88:
		rarity = RARITY_EPIC
	elif r > 0.65:
		rarity = RARITY_RARE
	var stat_mult: float = [1.0, 1.6, 2.4, 3.6][rarity]
	var slots := ["weapon", "armor", "trinket"]
	var slot: String = slots[randi() % slots.size()]
	var stats := ["attack", "defense", "production", "speed"]
	var item := {
		"name": _item_name(rarity, slot),
		"slot": slot,
		"rarity": rarity,
	}
	var n_stats := 1 + (2 if rarity >= RARITY_EPIC else 0)
	var chosen := []
	while chosen.size() < n_stats:
		var s: String = stats[randi() % stats.size()]
		if not chosen.has(s):
			chosen.append(s)
	for s: String in chosen:
		var val: float = (0.03 + randf() * 0.05) * stat_mult
		item[s] = roundf(val * 1000.0) / 1000.0
	return item


func _item_name(rarity: int, slot: String) -> String:
	var prefixes := ["Rouillé", "Solide", "Enchanté", "Mythique"]
	var slot_names := {"weapon": "Épée", "armor": "Armure", "trinket": "Talisman"}
	return "%s %s %s" % [prefixes[rarity], RARITY_NAMES[rarity], slot_names[slot]]


func _auto_equip(item: Dictionary) -> void:
	var cur = equipped.get(item["slot"])
	if cur == null or _item_score(item) > _item_score(cur):
		equipped[item["slot"]] = item


func _item_score(item: Dictionary) -> float:
	var s := 0.0
	for k in ["attack", "defense", "production", "speed"]:
		s += float(item.get(k, 0.0))
	return s


func total_stat_text() -> String:
	var a := attack_bonus()
	var d := defense_bonus()
	var p := production_mult() - 1.0
	var sp := speed_mult() - 1.0
	return "Att +%.0f%%  Déf +%.0f%%  Prod +%.0f%%  Vit +%.0f%%" % [a * 100.0, d * 100.0, p * 100.0, sp * 100.0]
