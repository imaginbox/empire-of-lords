extends Node2D
## Renders the world as a calm cartoon CONTINENT on an ocean: an organic
## landmass (meadow green) with a sandy coastline, a few forest patches and
## inland lakes, plus a soft vignette. All cities (radius <= ~4100) sit on
## land, so the map reads like a real world map rather than a flat patch.

const OCEAN := Color(0.20, 0.40, 0.58)      # deep calm sea
const LAND := Color(0.37, 0.57, 0.33)       # meadow green landmass
const COAST := Color(0.62, 0.68, 0.46)      # sandy coastline fringe
const FOREST := Color(0.23, 0.40, 0.20)     # dark forest patches
const WATER := Color(0.24, 0.46, 0.62)      # inland lakes
const RADIUS := 4600.0
const EDGE := Color(0.0, 0.0, 0.0, 0.40)

func _ready() -> void:
	queue_redraw()
	_build_vignette()


func _build_vignette() -> void:
	# Soft radial vignette: transparent in the center, gently darker at the rim.
	var gt := GradientTexture2D.new()
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 1.0)
	gt.width = 1024
	gt.height = 1024
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
	g.colors = PackedColorArray([Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.0), EDGE])
	gt.gradient = g
	var vs := Sprite2D.new()
	vs.texture = gt
	vs.centered = true
	vs.position = Vector2.ZERO
	vs.scale = Vector2(RADIUS * 2.3, RADIUS * 2.3)
	add_child(vs)


func _draw() -> void:
	# Ocean floor.
	draw_circle(Vector2.ZERO, RADIUS * 1.3, OCEAN)
	# Sandy coastline fringe (slightly larger than the land -> beach rim).
	draw_colored_polygon(_blob(RADIUS * 1.06, 0.05), COAST)
	# The continent itself.
	draw_colored_polygon(_blob(RADIUS * 0.97, 0.05), LAND)
	# Forest patches spread across the land.
	_patch(Vector2(300, 420), 1000, 640, FOREST, 0.34)
	_patch(Vector2(-540, -360), 880, 780, FOREST, 0.32)
	_patch(Vector2(900, -660), 720, 900, FOREST, 0.30)
	_patch(Vector2(-960, 540), 940, 620, FOREST, 0.32)
	_patch(Vector2(80, -940), 780, 660, FOREST, 0.30)
	# A couple of smaller groves close to the starting kingdom so the early
	# view has gentle terrain variety too.
	_patch(Vector2(240, 180), 420, 300, FOREST, 0.30)
	_patch(Vector2(-300, 220), 360, 280, FOREST, 0.28)
	# A few inland lakes.
	draw_circle(Vector2(-720, 60), 240, WATER)
	draw_circle(Vector2(620, 360), 200, WATER)
	draw_circle(Vector2(180, -560), 170, WATER)


## Deterministic organic coastline: layered sine harmonics produce a natural,
## non-repeating continent outline (always >= ~4200 so every city stays on land).
func _blob(base_r: float, amp: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var n := 96
	for i in range(n):
		var t := TAU * float(i) / float(n)
		var r := base_r * (1.0 + amp * (sin(t * 3.0 + 1.3) + sin(t * 5.0 + 0.7) * 0.6 + sin(t * 7.0) * 0.4))
		pts.append(Vector2(cos(t), sin(t)) * r)
	return pts


func _patch(center: Vector2, rx: float, ry: float, col: Color, alpha: float) -> void:
	var pts := PackedVector2Array()
	var n := 40
	for i in range(n):
		var t := TAU * float(i) / float(n)
		pts.append(center + Vector2(cos(t) * rx, sin(t) * ry))
	draw_colored_polygon(pts, Color(col.r, col.g, col.b, alpha))
