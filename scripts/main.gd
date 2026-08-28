extends Node2D
## Main game scene controller: builds the map visuals, handles camera & map
## input, keeps city/army visuals in sync with GameState.

const TX_NEUTRAL := preload("res://assets/generated/city_neutral.png")
const TX_PLAYER := preload("res://assets/generated/city_player.png")
const TX_ENEMY := preload("res://assets/generated/city_enemy.png")
const TX_ALLY := preload("res://assets/generated/city_ally.png")
const TX_ARMY := preload("res://assets/generated/army_marker.png")

@onready var game: GameState = $GameState
@onready var camera: Camera2D = $Camera2D
@onready var hud: Control = $UILayer/HUD

var _city_nodes := {}          # city_id -> Node2D
var _army_nodes := {}          # army (instance) -> Node2D
var source_city: CityNode = null
var target_city: CityNode = null

const MIN_ZOOM := 0.55
const MAX_ZOOM := 2.2
const PAN_SPEED := 850.0
const WORLD_LIMIT := 2700.0   # outer edge of the 4-zone evolving world

var _dragging := false        # right/middle-mouse drag to pan the camera
var _drag_last := Vector2.ZERO

# Pause menu / speed / recenter.
var _pause_layer: CanvasLayer
var _pause_visible := false
var _capital_pos := Vector2.ZERO
var _has_capital := false


func _ready() -> void:
	hud.main_node = self
	hud.attach(game)
	_build_cities()
	_build_army_layer()
	_build_pause_menu()
	_build_mini_hud()
	game.army_launched.connect(_on_army_launched)
	game.army_arrived.connect(_on_army_arrived)
	game.node_changed.connect(_on_node_changed)
	game.season_ended.connect(_on_season_ended)
	game.zone_discovered.connect(_on_zone_discovered)


# ---------------------------------------------------------------- building visuals

func _build_cities() -> void:
	for c in game.cities:
		var n := Node2D.new()
		n.position = c.map_pos
		add_child(n)

		# Soft cast shadow to ground the building (drawn under the sprite).
		var shadow := Polygon2D.new()
		var sp := PackedVector2Array()
		var seg := 18
		for i in range(seg):
			var a := TAU * float(i) / float(seg)
			sp.append(Vector2(cos(a) * 28.0, sin(a) * 12.0))
		shadow.polygon = sp
		shadow.color = Color(0, 0, 0, 0.4)
		shadow.position = Vector2(2, 22)
		n.add_child(shadow)
		shadow.name = "Shadow"

		var spr := Sprite2D.new()
		spr.texture = _texture_for(c.owner)
		spr.centered = true
		n.add_child(spr)
		spr.name = "Sprite"

		var ring := Node2D.new()
		ring.visible = false
		n.add_child(ring)
		ring.name = "Ring"
		ring.set_script(load("res://scripts/city_ring.gd"))

		var lvl := _make_label("%d" % c.level, Vector2(0, -38), Color(1, 0.9, 0.3))
		n.add_child(lvl)
		lvl.name = "Level"

		var gar := _make_label("0", Vector2(0, 20), Color.WHITE, 16)
		n.add_child(gar)
		gar.name = "Garrison"

		var nm := _make_label(c.node_name, Vector2(0, 36), Color(0.85, 0.95, 0.85), 13)
		n.add_child(nm)
		nm.name = "Name"

		_city_nodes[c.id] = n
		_update_city_visual(c)
		if c.owner == CityNode.OWNER_PLAYER and c.controller == 0 and not _has_capital:
			_capital_pos = c.map_pos
			_has_capital = true


func _make_label(text: String, offset: Vector2, color: Color, size: int = 14) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 4)
	l.position = offset
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size = Vector2(120, 20)
	l.set_anchors_preset(Control.PRESET_CENTER_TOP)
	l.position = offset - Vector2(60, 0)
	return l


func _build_army_layer() -> void:
	# Armies are added under a dedicated node created lazily.
	pass


func _texture_for(faction: int) -> Texture2D:
	match faction:
		CityNode.OWNER_PLAYER:
			return TX_PLAYER
		CityNode.OWNER_ENEMY:
			return TX_ENEMY
		CityNode.OWNER_ALLY:
			return TX_ALLY
	return TX_NEUTRAL


# ---------------------------------------------------------------- sync

func _process(_delta: float) -> void:
	if is_instance_valid(game):
		_update_army_positions()
		_update_garrison_labels()
		hud.refresh_top_bar()
		_pan_camera(_delta)


func _update_city_visual(c: CityNode) -> void:
	var n: Node2D = _city_nodes.get(c.id)
	if n == null:
		return
	# Fog of war: hidden cities are not drawn until discovered.
	n.visible = c.revealed
	var spr: Sprite2D = n.get_node("Sprite")
	spr.texture = _texture_for(c.owner)
	(n.get_node("Level") as Label).text = "Lv %d" % c.level
	_update_city_garrison(c)


func _update_city_garrison(c: CityNode) -> void:
	var n: Node2D = _city_nodes.get(c.id)
	if n == null:
		return
	(n.get_node("Garrison") as Label).text = str(c.garrison)


func _update_garrison_labels() -> void:
	for c in game.cities:
		_update_city_garrison(c)


func _on_node_changed(city_id: int) -> void:
	var c := game.get_city(city_id)
	if c != null:
		_update_city_visual(c)


func _on_army_launched(army: Army) -> void:
	var node := Node2D.new()
	var spr := Sprite2D.new()
	spr.texture = TX_ARMY
	spr.scale = Vector2(0.7, 0.7)
	node.add_child(spr)
	var lbl := Label.new()
	lbl.text = str(army.troops)
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	lbl.add_theme_constant_override("outline_size", 3)
	lbl.position = Vector2(-20, 14)
	node.add_child(lbl)
	$Armies.add_child(node)
	_army_nodes[army] = node


func _update_army_positions() -> void:
	for army in _army_nodes.keys():
		var node: Node2D = _army_nodes[army]
		if not is_instance_valid(node):
			_army_nodes.erase(army)
			continue
		var src: CityNode = game.get_city(army.from_id)
		var dst: CityNode = game.get_city(army.to_id)
		if src == null or dst == null:
			node.queue_free()
			_army_nodes.erase(army)
			continue
		var p: float = army.progress(game.time)
		node.position = src.map_pos.lerp(dst.map_pos, p)
		# fade army as it arrives
		if p > 0.7:
			node.modulate.a = 1.0 - (p - 0.7) / 0.3


func _on_season_ended(_rank: int, _gems: int, _realm: int, _realm_result: String) -> void:
	# Map reset to season start: drop selections, clear marching armies.
	clear_selection()
	for node in _army_nodes.values():
		if is_instance_valid(node):
			node.queue_free()
	_army_nodes.clear()


func _on_zone_discovered(zone_index: int) -> void:
	# A new territory with its own evolved lord is revealed.
	if is_instance_valid(hud):
		hud.on_zone_discovered(zone_index)


func _on_army_arrived(army: Army, won: bool) -> void:
	# Army node removed here; combat already resolved by GameState.
	var dst: CityNode = game.get_city(army.to_id)
	if dst != null:
		var col := Color(0.4, 1.0, 0.4) if won else Color(1.0, 0.4, 0.4)
		_spawn_floater(dst.map_pos, "Victoire !" if won else "Défaite !", col)
	for a in _army_nodes.keys():
		if not is_instance_valid(_army_nodes[a]):
			_army_nodes.erase(a)
	# cleanup stale army nodes
	for a in _army_nodes.keys():
		if a not in game.armies:
			if is_instance_valid(_army_nodes[a]):
				_army_nodes[a].queue_free()
			_army_nodes.erase(a)


func _spawn_floater(world_pos: Vector2, text: String, color: Color) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 20)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 5)
	l.position = world_pos - Vector2(60, 0)
	l.size = Vector2(120, 24)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(l)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y - 42.0, 1.2)
	tw.tween_property(l, "modulate:a", 0.0, 1.2)
	tw.chain().tween_callback(l.queue_free)


# ---------------------------------------------------------------- selection

func set_source(c: CityNode) -> void:
	source_city = c
	target_city = null
	_clear_rings()
	if c != null:
		_mark_ring(c, Color(0.3, 0.8, 1.0))
		hud.show_source_selected(c)


func set_target(c: CityNode) -> void:
	target_city = c
	_clear_rings()
	if source_city != null:
		_mark_ring(source_city, Color(0.3, 0.8, 1.0))
	if c != null:
		_mark_ring(c, Color(1.0, 0.3, 0.3))
	hud.show_attack_bar(source_city, c)


func clear_selection() -> void:
	source_city = null
	target_city = null
	_clear_rings()
	hud.clear_selection()


func city_screen_pos(id: int) -> Vector2:
	var c := game.get_city(id)
	if c == null:
		return Vector2(640.0, 360.0)
	var rect := get_viewport().get_visible_rect()
	return rect.size * 0.5 + (c.map_pos - camera.get_screen_center_position()) * camera.zoom


func _mark_ring(c: CityNode, color: Color) -> void:
	var n: Node2D = _city_nodes.get(c.id)
	if n == null:
		return
	var ring: Node2D = n.get_node("Ring")
	ring.visible = true
	ring.call("set_color", color)


func _clear_rings() -> void:
	for id in _city_nodes:
		var n: Node2D = _city_nodes[id]
		var ring: Node2D = n.get_node("Ring")
		ring.visible = false


func send_troops(percent: float) -> void:
	if source_city == null or target_city == null:
		return
	var count := int(float(source_city.garrison) * clampf(percent, 0.0, 1.0))
	if count <= 0:
		hud.toast("Pas assez de troupes")
		return
	game.launch_army(source_city.id, target_city.id, count)
	clear_selection()


# ---------------------------------------------------------------- input

func _pan_camera(delta: float) -> void:
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
		dir.x -= 1
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		dir.x += 1
	if Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W):
		dir.y -= 1
	if Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S):
		dir.y += 1
	if dir != Vector2.ZERO:
		camera.position += dir.normalized() * PAN_SPEED * delta / camera.zoom.x
		_clamp_camera()


func _clamp_camera() -> void:
	var half: Vector2 = get_viewport().get_visible_rect().size * 0.5 / camera.zoom
	camera.position = camera.position.clamp(
		Vector2(-WORLD_LIMIT + half.x, -WORLD_LIMIT + half.y),
		Vector2(WORLD_LIMIT - half.x, WORLD_LIMIT - half.y))


func _unhandled_input(event: InputEvent) -> void:
	if _pause_visible:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			_toggle_pause()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera.zoom = (camera.zoom * 1.15).clamp(Vector2(MIN_ZOOM, MIN_ZOOM), Vector2(MAX_ZOOM, MAX_ZOOM))
			get_viewport().set_input_as_handled()
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera.zoom = (camera.zoom / 1.15).clamp(Vector2(MIN_ZOOM, MIN_ZOOM), Vector2(MAX_ZOOM, MAX_ZOOM))
			get_viewport().set_input_as_handled()
		elif event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_on_map_click(event.position)
			get_viewport().set_input_as_handled()
		elif event.pressed and (event.button_index == MOUSE_BUTTON_RIGHT or event.button_index == MOUSE_BUTTON_MIDDLE):
			_dragging = true
			_drag_last = event.position
			get_viewport().set_input_as_handled()
		elif not event.pressed and (event.button_index == MOUSE_BUTTON_RIGHT or event.button_index == MOUSE_BUTTON_MIDDLE):
			_dragging = false
	elif event is InputEventMouseMotion and _dragging:
		var delta: Vector2 = event.position - _drag_last
		_drag_last = event.position
		camera.position -= delta / camera.zoom.x
		_clamp_camera()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_N:
		# dev shortcut: end the current season immediately
		game._end_season()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_toggle_pause()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_H:
		_recenter()
		get_viewport().set_input_as_handled()


func _on_map_click(screen_pos: Vector2) -> void:
	var world := camera.get_screen_center_position() + (screen_pos - get_viewport().get_visible_rect().size * 0.5) / camera.zoom
	var clicked: CityNode = game.find_city_at(world, 44.0)
	# Cannot select/attack a city hidden by the fog of war.
	if clicked != null and not clicked.revealed:
		clicked = null
	if clicked == null:
		clear_selection()
		return
	# toggle logic
	if source_city != null and clicked.id == source_city.id:
		clear_selection()
		return
	if source_city == null:
		if clicked.owner == CityNode.OWNER_PLAYER:
			set_source(clicked)
		else:
			hud.show_node_info(clicked)
	elif source_city != null:
		if clicked.owner == CityNode.OWNER_PLAYER:
			hud.toast("Impossible d'attaquer votre propre cité")
			clear_selection()
		elif clicked.owner == CityNode.OWNER_ALLY:
			hud.toast("Cité alliée — impossible de l'attaquer")
			clear_selection()
		else:
			set_target(clicked)


# ---------------------------------------------------------------- pause / speed / recenter

func _build_mini_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "MiniHUD"
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	vb.offset_left = -70.0
	vb.offset_top = 10.0
	vb.offset_right = -10.0
	vb.offset_bottom = 96.0
	vb.add_theme_constant_override("separation", 6)
	root.add_child(vb)
	var pause := Button.new()
	pause.text = "⏸ Pause"
	pause.tooltip_text = "Menu Pause (Échap)"
	pause.pressed.connect(_toggle_pause)
	vb.add_child(pause)
	var rec := Button.new()
	rec.text = "⌂ Capitale"
	rec.tooltip_text = "Centrer sur votre capitale (H)"
	rec.pressed.connect(_recenter)
	vb.add_child(rec)


func _build_pause_menu() -> void:
	_pause_layer = CanvasLayer.new()
	_pause_layer.name = "PauseLayer"
	_pause_layer.layer = 40
	_pause_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_pause_layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_pause_layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_layer.add_child(center)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	vb.custom_minimum_size = Vector2(300, 0)
	center.add_child(vb)
	var lbl := Label.new()
	lbl.text = "PAUSE"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 34)
	vb.add_child(lbl)
	var resume := Button.new()
	resume.text = "Reprendre"
	resume.custom_minimum_size = Vector2(0, 46)
	resume.pressed.connect(_toggle_pause)
	vb.add_child(resume)
	var speed_row := HBoxContainer.new()
	speed_row.add_theme_constant_override("separation", 8)
	speed_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(speed_row)
	var sp_lbl := Label.new()
	sp_lbl.text = "Vitesse :"
	vb.add_child(sp_lbl)
	for i in [1, 2, 3]:
		var b := Button.new()
		b.text = "x%d" % i
		b.custom_minimum_size = Vector2(70, 42)
		var v: int = i
		b.pressed.connect(func(): _set_speed(v))
		speed_row.add_child(b)
	var recenter := Button.new()
	recenter.text = "Aller à ma capitale"
	recenter.custom_minimum_size = Vector2(0, 46)
	recenter.pressed.connect(func():
		_recenter()
		_toggle_pause())
	vb.add_child(recenter)
	var quit := Button.new()
	quit.text = "Retour au menu"
	quit.custom_minimum_size = Vector2(0, 46)
	quit.pressed.connect(_on_quit_to_lobby)
	vb.add_child(quit)
	_pause_layer.visible = false


func _toggle_pause() -> void:
	_pause_visible = not _pause_visible
	get_tree().paused = _pause_visible
	if _pause_layer != null:
		_pause_layer.visible = _pause_visible


func _set_speed(speed: int) -> void:
	Engine.time_scale = float(speed)


func _recenter() -> void:
	if _has_capital:
		camera.position = _capital_pos
		_clamp_camera()


func _on_quit_to_lobby() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file("res://scenes/Lobby.tscn")
