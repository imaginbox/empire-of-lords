extends Node2D
## Draws a selection highlight ring around a city.

var color: Color = Color(1, 1, 1, 1)


func set_color(c: Color) -> void:
	color = c
	queue_redraw()


func _draw() -> void:
	draw_arc(Vector2.ZERO, 42.0, 0.0, TAU, 48, color, 3.0)
