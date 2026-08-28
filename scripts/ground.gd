extends Node2D
## Renders a calm, unified cartoon meadow for the whole evolving world.
## No busy tile pattern — a smooth matte green base with a few very subtle
## natural darker patches and a soft vignette toward the far edges, so it is
## relaxing on the eyes while still reading as a living cartoon landscape.

const BASE := Color(0.36, 0.56, 0.32)   # calm matte meadow green
const EDGE := Color(0.0, 0.0, 0.0, 0.40)
const RADIUS := 4700.0

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
	g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	g.colors = PackedColorArray([Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.0), EDGE])
	gt.gradient = g
	var vs := Sprite2D.new()
	vs.texture = gt
	vs.centered = true
	vs.position = Vector2.ZERO
	vs.scale = Vector2(RADIUS * 2.0, RADIUS * 2.0)
	add_child(vs)


func _draw() -> void:
	# Unified calm meadow base (single soft polygon).
	draw_colored_polygon(PackedVector2Array([
		Vector2(0, -RADIUS), Vector2(RADIUS, 0), Vector2(0, RADIUS), Vector2(-RADIUS, 0),
	]), BASE)
	# A few very subtle natural patches for gentle tonal variety.
	_patch(Vector2(300, 420), 1100, 700, 0.05)
	_patch(Vector2(-520, -320), 900, 820, 0.045)
	_patch(Vector2(920, -620), 720, 900, 0.04)
	_patch(Vector2(-940, 520), 1000, 620, 0.05)
	_patch(Vector2(80, -900), 820, 700, 0.04)


func _patch(center: Vector2, rx: float, ry: float, alpha: float) -> void:
	var pts := PackedVector2Array()
	var n := 48
	for i in range(n):
		var t := TAU * float(i) / float(n)
		pts.append(center + Vector2(cos(t) * rx, sin(t) * ry))
	draw_colored_polygon(pts, Color(0.18, 0.34, 0.16, alpha))
