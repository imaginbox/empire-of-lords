extends Node2D
## Multiplayer scene controller — shared real-time world.
##
## The relay is a pure message switch, so the AUTHORITY is a real peer: the
## lowest real peer id (see _net). The host runs the authoritative GameState
## and broadcasts compact world snapshots to every client; clients render the
## shared world from those snapshots and send commands (launch / upgrade /
## recruit) to the host via RPC. All human players share one kingdom and race
## to clear the evolving frontier together.

const TX_NEUTRAL := preload("res://assets/generated/city_neutral.png")
const TX_PLAYER := preload("res://assets/generated/city_player.png")
const TX_ENEMY := preload("res://assets/generated/city_enemy.png")
const TX_ALLY := preload("res://assets/generated/city_ally.png")
const TX_ARMY := preload("res://assets/generated/army_marker.png")

const SNAPSHOT_INTERVAL := 0.12
const MIN_ZOOM := 0.55
const MAX_ZOOM := 2.2
const PAN_SPEED := 850.0
const WORLD_LIMIT := 4300.0

var game: GameState = null        # host-only authoritative world
var _is_host := false
var _net: Node = null             # /root/LanNet autoload (resolved at runtime)

# Client-side snapshot state.
var _snap: Dictionary = {}
var _has_snap := false

# Rendered world.
var _city_nodes := {}             # city_id -> Node2D
var _army_root: Node2D
var _snap_timer := 0.0

# Selection / attack.
var source_id := -1
var target_id := -1

# Camera / pan.
var camera: Camera2D
var _dragging := false
var _drag_last := Vector2.ZERO

# Minimal HUD.
var _top_label: Label
var _ctx_panel: PanelContainer
var _ctx_title: Label
var _ctx_info: Label
var _slider: HSlider
var _send_btn: Button
var _upgrade_btn: Button
var _toast: Label
var _toast_timer: Timer
var _quit_btn: Button

# Pause menu / recenter.
var _pause_layer: CanvasLayer
var _pause_visible := false
var _recenter_btn: Button
var _my_capital := Vector2.ZERO
var _has_capital := false
var _centered_once := false
var _help_layer: CanvasLayer
var _help_visible := false
var _help_btn: Button


func _ready() -> void:
	_net = get_node_or_null("/root/LanNet")
	camera = $Camera2D
	_army_root = Node2D.new()
	_army_root.name = "Armies"
	add_child(_army_root)
	_build_hud()
	_start_net()


# ------------------------------------------------------------- networking

func _start_net() -> void:
	if _net == null:
		_show_toast("Réseau multijoueur indisponible.")
		await get_tree().create_timer(1.4).timeout
		get_tree().change_scene_to_file("res://scenes/Lobby.tscn")
		return
	_net.connection_failed.connect(_on_net_failed)
	if not _net.is_connected_to_room():
		_show_toast("Connexion au monde…")
		await _net.connected
	_is_host = _net.is_host()
	# The host (ENet server, peer 1) owns this scene's RPCs.
	set_multiplayer_authority(_net.current_host())
	if _is_host:
		_host_init()
	else:
		_client_init()


func _on_net_failed() -> void:
	_show_toast("Connexion perdue avec le serveur.")
	await get_tree().create_timer(1.2).timeout
	get_tree().change_scene_to_file("res://scenes/Lobby.tscn")


# ------------------------------------------------------------- host side

func _host_init() -> void:
	game = GameState.new()
	game.name = "GameState"
	add_child(game)
	game.end_peace()  # no tutorial grace in multiplayer
	if str(_net.get("mode")) == "vs":
		# VS = quick match: short season, no realm/tournament meta push.
		game.season_remaining = minf(game.season_remaining, 90.0)
		_show_toast("Mode VS — partie rapide !")
	else:
		_show_toast("Mode Conquête — tournoi : courez vers le Top !")
	game.zone_discovered.connect(func(_z: int): _show_toast("🎉 Nouvelle zone découverte !"))
	game.game_over.connect(func(): _show_toast("La partie est terminée !"))
	game.season_ended.connect(_on_host_season_ended)
	_net.peer_joined.connect(func(p: int): _assign_city(p))
	_assign_city(_net.my_id())
	for p in _net.real_peers():
		if int(p) != _net.my_id():
			_assign_city(int(p))
	_host_render_update()


func _on_host_season_ended(_rank: int, _gems: int, _realm: int, _res: String) -> void:
	# The world was rebuilt by _reset_map; forget and redraw all city visuals.
	for n in _city_nodes.values():
		if is_instance_valid(n):
			n.queue_free()
	_city_nodes.clear()
	for c: CityNode in game.cities:
		_ensure_city_node(c.id, c.map_pos, c.node_name)
	_host_render_update()


func _assign_city(peer_id: int) -> void:
	if game == null:
		return
	# The host (first peer) claims the existing starter capital (Fort-Sud).
	if peer_id == _net.my_id():
		var starter: CityNode = null
		for c: CityNode in game.cities:
			if c.owner == CityNode.OWNER_PLAYER and c.controller == 0:
				starter = c
				break
		if starter != null:
			starter.controller = peer_id
			starter.garrison = maxi(starter.garrison, 300)
			starter.revealed = true
			game.node_changed.emit(starter.id)
			return
	# Otherwise convert the nearest neutral city in the current frontier.
	var best: CityNode = null
	var best_d := INF
	for c: CityNode in game.cities:
		if c.owner == CityNode.OWNER_NEUTRAL and c.controller == 0 \
				and game.zone_of(c) <= game._zone_front:
			var d: float = c.map_pos.distance_to(Vector2.ZERO)
			if d < best_d:
				best_d = d
				best = c
	if best == null:
		best = game.get_city(0)
	if best == null:
		return
	best.owner = CityNode.OWNER_PLAYER
	best.garrison = maxi(best.garrison, 300)
	best.controller = peer_id
	best.revealed = true
	game.node_changed.emit(best.id)


# ------------------------------------------------------------- client side

func _client_init() -> void:
	_show_toast("Connexion au monde en cours…")
	_ctx_panel.visible = false
	# Tell the VPS (peer 1) we have loaded /root/Main so it sends us snapshots.
	if _net != null and _net.is_connected_to_room():
		_rpc_game_ready.rpc_id(1)


## Client-side stub of the "I am in the game" handshake (handled on the server).
@rpc("any_peer", "reliable")
func _rpc_game_ready() -> void:
	pass


# ------------------------------------------------------------- process

func _process(delta: float) -> void:
	if _is_host and game != null:
		game._process(delta)
		_host_render_update()
		_snap_timer += delta
		if _snap_timer >= SNAPSHOT_INTERVAL:
			_snap_timer = 0.0
			_broadcast_snapshot()
	_update_hud()


# ------------------------------------------------------------- snapshots

func _build_snapshot() -> Dictionary:
	var cities_arr: Array = []
	for c: CityNode in game.cities:
		cities_arr.append({
			"id": c.id, "name": c.node_name, "x": c.map_pos.x, "y": c.map_pos.y,
			"owner": c.owner, "level": c.level, "garrison": c.garrison,
			"revealed": c.revealed, "controller": c.controller,
		})
	var armies_arr: Array = []
	var idx := 0
	for a: Army in game.armies:
		var p: Vector2 = _army_pos(a)
		armies_arr.append({"id": idx, "x": p.x, "y": p.y, "faction": a.faction})
		idx += 1
	var zname := ""
	var zlord := ""
	if game.zones.size() > 0 and game._zone_front < game.zones.size():
		var z: Dictionary = game.zones[game._zone_front]
		zname = z["name"]
		zlord = z["lord"]
	return {
		"cities": cities_arr, "armies": armies_arr,
		"front": game._zone_front, "zone_total": game.zones.size(),
		"season": game.season_number, "season_left": game.season_remaining,
		"gold": game.player.gold, "level": game.player.level,
		"dominance": game.dominance_score(), "zname": zname, "zlord": zlord,
	}


func _broadcast_snapshot() -> void:
	_recv_snapshot.rpc(_build_snapshot())


@rpc("reliable")
func _recv_snapshot(snap: Dictionary) -> void:
	_snap = snap
	_has_snap = true
	_render_snap()


# ------------------------------------------------------------- rendering

func _texture_for(faction: int) -> Texture2D:
	match faction:
		CityNode.OWNER_PLAYER:
			return TX_PLAYER
		CityNode.OWNER_ENEMY:
			return TX_ENEMY
		CityNode.OWNER_ALLY:
			return TX_ALLY
	return TX_NEUTRAL


func _ensure_city_node(id: int, pos: Vector2, display_name: String) -> Node2D:
	var n: Node2D = _city_nodes.get(id)
	if n == null:
		n = Node2D.new()
		n.position = pos
		add_child(n)

		var shadow := Polygon2D.new()
		var sp := PackedVector2Array()
		var seg := 18
		for i in range(seg):
			var a: float = TAU * float(i) / float(seg)
			sp.append(Vector2(cos(a) * 28.0, sin(a) * 12.0))
		shadow.polygon = sp
		shadow.color = Color(0, 0, 0, 0.4)
		shadow.position = Vector2(2, 22)
		n.add_child(shadow)

		var spr := Sprite2D.new()
		spr.centered = true
		n.add_child(spr)
		spr.name = "Sprite"

		n.add_child(_label("0", Vector2(0, 20), Color.WHITE, 16, "Garrison"))
		n.add_child(_label(display_name, Vector2(0, 36), Color(0.85, 0.95, 0.85), 13, "Name"))
		var owner_lbl := _label("", Vector2(0, -18), Color.WHITE, 13, "Owner")
		owner_lbl.visible = false
		n.add_child(owner_lbl)
		_city_nodes[id] = n
	return n


func _player_color(pid: int) -> Color:
	var pal: Array = [
		Color(0.35, 0.65, 1.0),
		Color(1.0, 0.45, 0.35),
		Color(0.45, 0.9, 0.45),
		Color(1.0, 0.8, 0.3),
		Color(0.85, 0.5, 1.0),
		Color(0.4, 0.9, 0.9),
	]
	return pal[maxi(0, pid - 2) % pal.size()]


func _label(text: String, offset: Vector2, color: Color, size: int, node_name: String) -> Label:
	var l := Label.new()
	l.text = text
	l.name = node_name
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 4)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size = Vector2(120, 20)
	l.position = offset - Vector2(60, 0)
	return l


func _host_render_update() -> void:
	if game == null:
		return
	for c: CityNode in game.cities:
		var n: Node2D = _ensure_city_node(c.id, c.map_pos, c.node_name)
		n.visible = c.revealed
		(n.get_node("Sprite") as Sprite2D).texture = _texture_for(c.owner)
		(n.get_node("Garrison") as Label).text = str(c.garrison)
	for ch in _army_root.get_children():
		ch.free()
	for a: Army in game.armies:
		var m := Sprite2D.new()
		m.texture = TX_ARMY
		m.centered = true
		m.position = _army_pos(a)
		_army_root.add_child(m)


func _render_snap() -> void:
	if not _has_snap:
		return
	var names: Dictionary = _snap.get("names", {})
	_has_capital = false
	for e in _snap["cities"]:
		var id: int = e["id"]
		var n: Node2D = _ensure_city_node(id, Vector2(e["x"], e["y"]), e["name"])
		n.visible = e["revealed"]
		var spr := n.get_node("Sprite") as Sprite2D
		spr.texture = _texture_for(e["owner"])
		spr.modulate = Color.WHITE
		var owner_label := n.get_node("Owner") as Label
		owner_label.visible = false
		if e["owner"] == CityNode.OWNER_PLAYER and int(e["controller"]) > 1:
			var ctrl := int(e["controller"])
			var col := _player_color(ctrl)
			spr.modulate = col.lerp(Color.WHITE, 0.45)
			owner_label.text = str(names.get(ctrl, "Joueur %d" % ctrl))
			owner_label.add_theme_color_override("font_color", col)
			owner_label.visible = true
			if ctrl == _net.my_id():
				_my_capital = Vector2(e["x"], e["y"])
				_has_capital = true
		(n.get_node("Garrison") as Label).text = str(e["garrison"])
	if _has_capital and not _centered_once:
		_centered_once = true
		camera.position = _my_capital
		_clamp_camera()
	for ch in _army_root.get_children():
		ch.free()
	for a in _snap["armies"]:
		var m := Sprite2D.new()
		m.texture = TX_ARMY
		m.centered = true
		m.position = Vector2(a["x"], a["y"])
		_army_root.add_child(m)


func _army_pos(a: Army) -> Vector2:
	var src: CityNode = game.get_city(a.from_id)
	var dst: CityNode = game.get_city(a.to_id)
	if src == null or dst == null:
		return Vector2.ZERO
	var t: float = clampf((game.time - a.depart_time) / maxf(a.travel_time, 0.001), 0.0, 1.0)
	return src.map_pos.lerp(dst.map_pos, t)


# ------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if _help_visible:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			_toggle_help()
			get_viewport().set_input_as_handled()
		return
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
	elif event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			_toggle_pause()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_H:
			_recenter()
			get_viewport().set_input_as_handled()
			return
		var dir := Vector2.ZERO
		if event.keycode == KEY_LEFT or event.keycode == KEY_A:
			dir.x -= 1
		elif event.keycode == KEY_RIGHT or event.keycode == KEY_D:
			dir.x += 1
		elif event.keycode == KEY_UP or event.keycode == KEY_W:
			dir.y -= 1
		elif event.keycode == KEY_DOWN or event.keycode == KEY_S:
			dir.y += 1
		if dir != Vector2.ZERO:
			camera.position += dir.normalized() * PAN_SPEED / camera.zoom.x
			_clamp_camera()
			get_viewport().set_input_as_handled()


func _clamp_camera() -> void:
	var half: Vector2 = get_viewport().get_visible_rect().size * 0.5 / camera.zoom
	camera.position = camera.position.clamp(
		Vector2(-WORLD_LIMIT + half.x, -WORLD_LIMIT + half.y),
		Vector2(WORLD_LIMIT - half.x, WORLD_LIMIT - half.y))


func _screen_to_world(screen_pos: Vector2) -> Vector2:
	return camera.get_screen_center_position() + (screen_pos - get_viewport().get_visible_rect().size * 0.5) / camera.zoom


func _on_map_click(screen_pos: Vector2) -> void:
	var world: Vector2 = _screen_to_world(screen_pos)
	var hit := _city_at(world)
	if hit.is_empty() or not hit["revealed"]:
		_clear_selection()
		return
	var id: int = hit["id"]
	if source_id == id:
		_clear_selection()
		return
	if source_id == -1:
		if hit["owner"] == CityNode.OWNER_PLAYER and _can_control(id):
			source_id = id
			_show_source_bar()
		else:
			source_id = -1
			target_id = id
			_show_info_bar()
	elif source_id != -1:
		if hit["owner"] == CityNode.OWNER_PLAYER:
			_show_toast("Cité amie — choisissez une cible ennemie.")
			_clear_selection()
		else:
			target_id = id
			_show_attack_bar()


func _city_at(world: Vector2) -> Dictionary:
	if _is_host and game != null:
		var c: CityNode = game.find_city_at(world, 44.0)
		if c == null:
			return {}
		return {"id": c.id, "name": c.node_name, "owner": c.owner, "garrison": c.garrison,
			"revealed": c.revealed, "controller": c.controller}
	if not _has_snap:
		return {}
	var best := {}
	var best_d := INF
	for e in _snap["cities"]:
		var d: float = Vector2(e["x"], e["y"]).distance_to(world)
		if d < 44.0 and d < best_d:
			best_d = d
			best = e
	return best


func _can_control(id: int) -> bool:
	var me: int = _net.my_id()
	if _is_host and game != null:
		var c: CityNode = game.get_city(id)
		return c != null and c.controller == me
	if _has_snap:
		for e in _snap["cities"]:
			if int(e["id"]) == id:
				return int(e["controller"]) == me
	return false


# ------------------------------------------------------------- client commands

func _send_launch(troops: int) -> void:
	var h: int = _net.current_host()
	if h <= 0 or source_id < 0 or target_id < 0:
		return
	_cmd_launch.rpc_id(h, source_id, target_id, troops)


func _send_upgrade() -> void:
	var h: int = _net.current_host()
	if h <= 0 or source_id < 0:
		return
	_cmd_upgrade.rpc_id(h, source_id)


@rpc("any_peer", "reliable")
func _cmd_launch(from_id: int, to_id: int, troops: int) -> void:
	if not _is_host or game == null:
		return
	var peer: int = multiplayer.get_remote_sender_id()
	var src: CityNode = game.get_city(from_id)
	if src == null or src.owner != CityNode.OWNER_PLAYER or src.controller != peer:
		return
	game.launch_army(from_id, to_id, troops)


@rpc("any_peer", "reliable")
func _cmd_upgrade(city_id: int) -> void:
	if not _is_host or game == null:
		return
	var peer: int = multiplayer.get_remote_sender_id()
	var c: CityNode = game.get_city(city_id)
	if c == null or c.owner != CityNode.OWNER_PLAYER or c.controller != peer:
		return
	game.upgrade_city(city_id)


@rpc("any_peer", "reliable")
func _cmd_recruit() -> void:
	if not _is_host or game == null:
		return
	game.recruit_ally()


# ------------------------------------------------------------- HUD

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "UILayer"
	add_child(layer)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	_top_label = Label.new()
	_top_label.name = "TopBar"
	_top_label.position = Vector2(10, 6)
	_top_label.add_theme_font_size_override("font_size", 16)
	_top_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_top_label.add_theme_constant_override("outline_size", 5)
	root.add_child(_top_label)

	_ctx_panel = PanelContainer.new()
	_ctx_panel.anchor_left = 0.5
	_ctx_panel.anchor_top = 1.0
	_ctx_panel.anchor_right = 0.5
	_ctx_panel.anchor_bottom = 1.0
	_ctx_panel.offset_top = -190.0
	_ctx_panel.offset_bottom = -10.0
	_ctx_panel.visible = false
	root.add_child(_ctx_panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 5)
	_ctx_panel.add_child(vb)
	_ctx_title = _hud_label(vb, "", 18)
	_ctx_info = _hud_label(vb, "", 14)

	var hb := HBoxContainer.new()
	vb.add_child(hb)
	_slider = HSlider.new()
	_slider.min_value = 1.0
	_slider.max_value = 100.0
	_slider.value = 100.0
	_slider.step = 1.0
	_slider.custom_minimum_size = Vector2(300, 24)
	hb.add_child(_slider)

	_send_btn = Button.new()
	_send_btn.text = "ENVOYER"
	_send_btn.pressed.connect(_on_send)
	hb.add_child(_send_btn)

	var hb2 := HBoxContainer.new()
	vb.add_child(hb2)
	_upgrade_btn = Button.new()
	_upgrade_btn.text = "Améliorer la ville"
	_upgrade_btn.pressed.connect(_on_upgrade)
	hb2.add_child(_upgrade_btn)
	var b_desel := Button.new()
	b_desel.text = "Désélectionner"
	b_desel.pressed.connect(_clear_selection)
	hb2.add_child(b_desel)

	_quit_btn = Button.new()
	_quit_btn.text = "Quitter"
	_quit_btn.position = Vector2(10, 40)
	_quit_btn.pressed.connect(_on_quit)
	root.add_child(_quit_btn)

	_recenter_btn = Button.new()
	_recenter_btn.text = "⌂ Capitale"
	_recenter_btn.position = Vector2(10, 70)
	_recenter_btn.pressed.connect(_recenter)
	root.add_child(_recenter_btn)

	_help_btn = Button.new()
	_help_btn.text = "?"
	_help_btn.tooltip_text = "Aide / tutoriel (Échap ferme)"
	_help_btn.position = Vector2(10, 100)
	_help_btn.pressed.connect(_toggle_help)
	root.add_child(_help_btn)

	_build_pause_menu(root)
	_build_help_menu(root)

	_toast = Label.new()
	_toast.anchor_left = 0.5
	_toast.anchor_right = 0.5
	_toast.anchor_top = 0.5
	_toast.anchor_bottom = 0.5
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.visible = false
	_toast.add_theme_font_size_override("font_size", 22)
	_toast.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_toast.add_theme_constant_override("outline_size", 5)
	root.add_child(_toast)
	_toast_timer = Timer.new()
	_toast_timer.one_shot = true
	_toast_timer.timeout.connect(func(): _toast.visible = false)
	root.add_child(_toast_timer)


func _hud_label(parent: Node, text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	parent.add_child(l)
	return l


func _on_send() -> void:
	if _is_host and game != null:
		# Host runs authority locally.
		var pct: float = _slider.value / _slider.max_value
		var src: CityNode = game.get_city(source_id)
		if src != null:
			_send_launch_host(int(float(src.garrison) * pct))
		return
	var src_g: int = _snap_city(source_id).get("garrison", 0)
	var pct2: float = _slider.value / _slider.max_value
	_send_launch(int(float(src_g) * pct2))


func _send_launch_host(troops: int) -> void:
	if game != null and source_id >= 0 and target_id >= 0:
		game.launch_army(source_id, target_id, troops)
	_clear_selection()


func _on_upgrade() -> void:
	if _is_host and game != null:
		var c: CityNode = game.get_city(source_id)
		if c != null:
			game.upgrade_city(source_id)
		return
	_send_upgrade()


func _snap_city(id: int) -> Dictionary:
	for e in _snap["cities"]:
		if int(e["id"]) == id:
			return e
	return {}


func _clear_selection() -> void:
	source_id = -1
	target_id = -1
	_ctx_panel.visible = false


func _show_source_bar() -> void:
	var src := _city_state(source_id)
	_ctx_panel.visible = true
	_ctx_title.text = "%s — sélectionné" % src.get("name", "")
	_ctx_info.text = "Garnison : %d\nChoisissez une cible neutre/ennemie." % int(src.get("garrison", 0))
	_slider.max_value = float(maxi(1, int(src.get("garrison", 1))))
	_slider.value = _slider.max_value
	_send_btn.visible = false
	_upgrade_btn.visible = true
	_position_ctx()


func _show_attack_bar() -> void:
	var src := _city_state(source_id)
	var dst := _city_state(target_id)
	_ctx_panel.visible = true
	_ctx_title.text = "Envoyer des troupes"
	_ctx_info.text = "Source : %s (%d) → %s (Déf %d)" % [
		src.get("name", "-"), int(src.get("garrison", 0)),
		dst.get("name", "-"), int(dst.get("garrison", 0)),
	]
	_slider.max_value = float(maxi(1, int(src.get("garrison", 1))))
	_slider.value = _slider.max_value
	_send_btn.visible = true
	_upgrade_btn.visible = false
	_position_ctx()


func _show_info_bar() -> void:
	var d := _city_state(target_id)
	_ctx_panel.visible = true
	_ctx_title.text = "%s (Lv %d)" % [d.get("name", "-"), int(d.get("level", 1))]
	_ctx_info.text = "Garnison : %d\nPropriétaire : %s" % [
		int(d.get("garrison", 0)),
		_owner_name(d),
	]
	_send_btn.visible = false
	_upgrade_btn.visible = false
	_position_ctx()


func _owner_name(d: Dictionary) -> String:
	var ownr := int(d.get("owner", 0))
	var ctrl := int(d.get("controller", 0))
	if ownr == CityNode.OWNER_PLAYER:
		if ctrl == _net.my_id():
			return "Vous"
		var names: Dictionary = _snap.get("names", {})
		return str(names.get(ctrl, "Joueur %d" % ctrl))
	if ownr == CityNode.OWNER_ENEMY:
		return "Ennemi"
	if ownr == CityNode.OWNER_ALLY:
		return "Allié"
	return "Neutre"


func _city_state(id: int) -> Dictionary:
	if _is_host and game != null:
		var c: CityNode = game.get_city(id)
		if c == null:
			return {}
		return {"name": c.node_name, "garrison": c.garrison, "level": c.level,
			"owner": c.owner, "controller": c.controller}
	return _snap_city(id)


func _position_ctx() -> void:
	_ctx_panel.reset_size()
	var psize: Vector2 = _ctx_panel.get_combined_minimum_size()
	_ctx_panel.position = Vector2((get_viewport().get_visible_rect().size.x - psize.x) * 0.5,
		get_viewport().get_visible_rect().size.y - psize.y - 6.0)


func _update_hud() -> void:
	if not _has_snap and not (_is_host and game != null):
		_top_label.text = "En attente du monde partagé…"
		return
	var gold := 0
	var lvl := 0
	var season := 1
	var left := 0.0
	var front := 0
	var ztotal := 6
	var zname := "-"
	var dom := 0
	if _is_host and game != null:
		gold = game.player.gold
		lvl = game.player.level
		season = game.season_number
		left = game.season_remaining
		front = game._zone_front
		ztotal = game.zones.size()
		dom = game.dominance_score()
		if game.zones.size() > 0 and game._zone_front < game.zones.size():
			zname = game.zones[game._zone_front]["name"]
	else:
		gold = int(_snap.get("gold", 0))
		lvl = int(_snap.get("level", 1))
		season = int(_snap.get("season", 1))
		left = float(_snap.get("season_left", 0.0))
		front = int(_snap.get("front", 0))
		ztotal = int(_snap.get("zone_total", 6))
		zname = str(_snap.get("zname", "-"))
		dom = int(_snap.get("dominance", 0))
	var mm := int(left / 60.0)
	var ss := int(left) % 60
	var mode_txt := "Conquête"
	if _net != null and str(_net.get("mode")) == "vs":
		mode_txt = "VS"
	_top_label.text = "[%s] Niv %d · Or %d · S%d %d:%02d · Zone %d/%d · %s · Dom %d%%" % [
		mode_txt, lvl, gold, season, mm, ss, mini(front + 1, ztotal), ztotal, zname, dom,
	]


func _show_toast(text: String) -> void:
	_toast.text = text
	_toast.visible = true
	_toast_timer.start(2.4)


func _recenter() -> void:
	if _has_capital:
		camera.position = _my_capital
		_clamp_camera()


func _build_pause_menu(_root: Control) -> void:
	_pause_layer = CanvasLayer.new()
	_pause_layer.name = "PauseLayer"
	_pause_layer.layer = 30
	_pause_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_pause_layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_pause_layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_layer.add_child(center)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	vb.custom_minimum_size = Vector2(280, 0)
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
	var recenter := Button.new()
	recenter.text = "Aller à ma capitale"
	recenter.custom_minimum_size = Vector2(0, 46)
	recenter.pressed.connect(func():
		_recenter()
		_toggle_pause())
	vb.add_child(recenter)
	var quit := Button.new()
	quit.text = "Quitter au Lobby"
	quit.custom_minimum_size = Vector2(0, 46)
	quit.pressed.connect(_on_quit)
	vb.add_child(quit)
	_pause_layer.visible = false


func _toggle_pause() -> void:
	_pause_visible = not _pause_visible
	if _pause_layer != null:
		_pause_layer.visible = _pause_visible


func _build_help_menu(_root: Control) -> void:
	_help_layer = CanvasLayer.new()
	_help_layer.name = "HelpLayer"
	_help_layer.layer = 35
	_help_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_help_layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_help_layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_help_layer.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 0)
	center.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	panel.add_child(vb)
	var lbl := Label.new()
	lbl.text = "📖 AIDE — Empire of Lords"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 24)
	vb.add_child(lbl)
	var guide := Label.new()
	guide.text = "• Votre capitale produit des troupes et de l'or en continu.\n"
	guide.text += "• Cliquez sur UNE DE VOS villes pour la sélectionner, puis sur une ville neutre/ennemie et choisissez le % de troupes à envoyer.\n"
	guide.text += "• Le combat est calculé automatiquement à l'arrivée (Force_Attaque > Force_Défense). Conquérez les villes pour étendre votre royaume.\n"
	guide.text += "• Améliorez vos villes (niveau = plus de production et de défense).\n"
	guide.text += "• Les SAISONS avancent : à chaque fin de saison, le monde évolue et votre rang (Bronze → Diamant) progresse.\n"
	guide.text += "• La ZONE peut être débloquée : les villes de la zone actuelle une fois conquises, la frontière avance.\n"
	guide.text += "• Touches : H = capitale · Échap = menu · molette = zoom · glisser (clic droit/milieu) = déplacer la carte.\n"
	guide.text += "• Votre pseudo apparaît au-dessus de VOS villes (couleur unique), vos alliés aussi."
	guide.add_theme_font_size_override("font_size", 14)
	guide.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(guide)
	var close := Button.new()
	close.text = "Compris !"
	close.custom_minimum_size = Vector2(0, 42)
	close.pressed.connect(_toggle_help)
	vb.add_child(close)
	_help_layer.visible = false


func _toggle_help() -> void:
	_help_visible = not _help_visible
	if _help_layer != null:
		_help_layer.visible = _help_visible


func _on_quit() -> void:
	_net.disconnect_from_room()
	get_tree().change_scene_to_file("res://scenes/Lobby.tscn")