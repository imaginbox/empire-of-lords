class_name CityNode
extends RefCounted
## A strategic node (city) on the map. Pure data.

const OWNER_NEUTRAL := 0
const OWNER_PLAYER := 1
const OWNER_ENEMY := 2
const OWNER_ALLY := 3   # controlled by a friendly AI lord in your alliance

const BASE_PRODUCTION := 1.5      # troops per second at level 1
const PRODUCTION_LEVEL_MULT := 0.25
const BASE_STORAGE := 400
const STORAGE_PER_LEVEL := 200
const CITY_DEFENSE_PER_LEVEL := 0.05

var id: int
var node_name: String
var map_pos: Vector2
var owner: int = OWNER_NEUTRAL
var level: int = 1
var garrison: int = 0
var prod_buf: float = 0.0   # fractional troop-production accumulator (no truncation loss)
var revealed: bool = false  # fog of war: hidden until discovered (own cities are always revealed)
var controller: int = 0     # multiplayer: peer id that commands this city (0 = none/AI/shared)


func production_per_sec() -> float:
	return BASE_PRODUCTION * (1.0 + float(level) * PRODUCTION_LEVEL_MULT)


func storage_cap() -> int:
	return BASE_STORAGE + level * STORAGE_PER_LEVEL


func defense_city_bonus() -> float:
	return 1.0 + float(level) * CITY_DEFENSE_PER_LEVEL
