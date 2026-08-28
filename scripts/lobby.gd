extends Control
## Main menu / lobby. Choose between three game modes:
##   - Solo        : the single-player campaign.
##   - Multi VS    : quick matches, pick-up style (short season).
##   - Multi Conquête : the tournament/league conquest concept.
## For a multiplayer mode you host or join a server, then enter the waiting
## room (Room.tscn) where players gather, chat and a countdown starts the game.

var _mode := ""                # "", "vs", "conquest"
var _status: Label
var _host_port: LineEdit
var _join_ip: LineEdit
var _join_port: LineEdit
var _mp_panel: PanelContainer
var _mp_header: Label


func _ready() -> void:
	_build()


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.12, 0.16)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var title := Label.new()
	title.text = "Empire of Lords"
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", Color(1, 0.88, 0.55))
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	title.add_theme_constant_override("outline_size", 6)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	title.position = Vector2(0, 30)
	title.size = Vector2(0, 50)
	add_child(title)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(460, 0)
	center.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	panel.add_child(vb)

	var mode_label := Label.new()
	mode_label.text = "Choisissez votre mode de jeu"
	mode_label.add_theme_font_size_override("font_size", 20)
	mode_label.add_theme_color_override("font_color", Color(1, 0.95, 0.85))
	mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(mode_label)

	var b_solo := _make_button("Solo", Color(0.2, 0.5, 0.25))
	b_solo.custom_minimum_size = Vector2(0, 46)
	b_solo.pressed.connect(_on_solo)
	vb.add_child(b_solo)

	var b_vs := _make_button("Multi VS  (parties à la volée)", Color(0.18, 0.42, 0.55))
	b_vs.custom_minimum_size = Vector2(0, 46)
	b_vs.pressed.connect(func(): _on_choose_mode("vs"))
	vb.add_child(b_vs)

	var b_conq := _make_button("Multi Conquête  (tournoi)", Color(0.45, 0.3, 0.55))
	b_conq.custom_minimum_size = Vector2(0, 46)
	b_conq.pressed.connect(func(): _on_choose_mode("conquest"))
	vb.add_child(b_conq)

	# --- Multiplayer host/join panel (revealed after choosing a multi mode) ---
	_mp_panel = PanelContainer.new()
	_mp_panel.visible = false
	vb.add_child(_mp_panel)
	var mpb := VBoxContainer.new()
	mpb.add_theme_constant_override("separation", 8)
	_mp_panel.add_child(mpb)

	_mp_header = Label.new()
	_mp_header.text = ""
	_mp_header.add_theme_font_size_override("font_size", 16)
	_mp_header.add_theme_color_override("font_color", Color(0.9, 0.95, 1))
	_mp_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mpb.add_child(_mp_header)

	mpb.add_child(_section_label("HÉBERGER (vous créez le serveur)"))
	var ip_row := HBoxContainer.new()
	ip_row.add_theme_constant_override("separation", 6)
	mpb.add_child(ip_row)
	ip_row.add_child(_field_label("Votre IP LAN :"))
	ip_row.add_child(_value_label(_local_ip()))
	var hp_row := HBoxContainer.new()
	hp_row.add_theme_constant_override("separation", 6)
	mpb.add_child(hp_row)
	hp_row.add_child(_field_label("Port :"))
	_host_port = LineEdit.new()
	_host_port.text = "7777"
	_host_port.custom_minimum_size = Vector2(90, 30)
	hp_row.add_child(_host_port)
	var b_host := _make_button("Héberger et ouvrir la salle d'attente", Color(0.18, 0.4, 0.5))
	b_host.pressed.connect(_on_host)
	mpb.add_child(b_host)

	mpb.add_child(_section_label("REJOINDRE UN SERVEUR EXISTANT"))
	var ji_row := HBoxContainer.new()
	ji_row.add_theme_constant_override("separation", 6)
	mpb.add_child(ji_row)
	ji_row.add_child(_field_label("IP du serveur :"))
	_join_ip = LineEdit.new()
	_join_ip.placeholder_text = "ex. 192.168.1.20"
	_join_ip.custom_minimum_size = Vector2(180, 30)
	ji_row.add_child(_join_ip)
	var jp_row := HBoxContainer.new()
	jp_row.add_theme_constant_override("separation", 6)
	mpb.add_child(jp_row)
	jp_row.add_child(_field_label("Port :"))
	_join_port = LineEdit.new()
	_join_port.text = "7777"
	_join_port.custom_minimum_size = Vector2(80, 30)
	jp_row.add_child(_join_port)
	var b_join := _make_button("Rejoindre et entrer dans la salle", Color(0.2, 0.35, 0.55))
	b_join.pressed.connect(_on_join)
	mpb.add_child(b_join)

	_status = Label.new()
	_status.text = ""
	_status.add_theme_font_size_override("font_size", 13)
	_status.add_theme_color_override("font_color", Color(1, 0.7, 0.5))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mpb.add_child(_status)


func _section_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", Color(0.8, 0.95, 0.8))
	return l


func _field_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 14)
	l.custom_minimum_size = Vector2(150, 0)
	return l


func _value_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", Color(0.9, 0.9, 1))
	return l


func _make_button(text: String, color: Color) -> Button:
	var b := Button.new()
	b.text = text
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(6)
	b.add_theme_stylebox_override("normal", s)
	return b


func _local_ip() -> String:
	var ipv4: String = ""
	for a in IP.get_local_addresses():
		if a.contains(".") and not a.begins_with("127."):
			return a
		if a.contains("."):
			ipv4 = a
	if not ipv4.is_empty():
		return ipv4
	for a in IP.get_local_addresses():
		if not a.begins_with("127."):
			return a
	return "127.0.0.1"


func _net() -> Node:
	return get_node_or_null("/root/LanNet")


func _on_solo() -> void:
	get_tree().change_scene_to_file("res://scenes/Main.tscn")


func _on_choose_mode(m: String) -> void:
	_mode = m
	var net: Node = _net()
	if net != null:
		net.set("mode", m)
	_mp_header.text = "MODE : " + ("Multi VS (parties à la volée)" if m == "vs" else "Multi Conquête (tournoi)")
	_mp_panel.visible = true
	_status.text = ""


func _go_room() -> void:
	get_tree().change_scene_to_file("res://scenes/Room.tscn")


func _on_host() -> void:
	var net: Node = _net()
	if net == null or _mode.is_empty():
		_status.text = "Choisissez d'abord un mode multijoueur."
		return
	var port: int = int(_host_port.text.strip_edges()) if _host_port.text.strip_edges().is_valid_int() else 7777
	var err: int = int(net.call("host_game", port))
	if err == 0:
		_status.text = "Serveur lancé sur le port %d. Ouverture de la salle…" % port
		_go_room()
	else:
		_status.text = "Impossible d'héberger (port %d occupé ?)." % port


func _on_join() -> void:
	var net: Node = _net()
	if net == null or _mode.is_empty():
		_status.text = "Choisissez d'abord un mode multijoueur."
		return
	var ip: String = _join_ip.text.strip_edges()
	var port: int = int(_join_port.text.strip_edges()) if _join_port.text.strip_edges().is_valid_int() else 7777
	if ip.is_empty():
		_status.text = "Entrez l'IP du serveur à rejoindre."
		return
	var err: int = int(net.call("join_game", ip, port))
	if err == 0:
		_status.text = "Connexion à %s:%d…" % [ip, port]
		if _mode == "conquest":
			# Conquest is served by a persistent shared server: join the live
			# world directly (no waiting room — the world is already running).
			get_tree().change_scene_to_file("res://scenes/Multiplayer.tscn")
		else:
			_go_room()
	else:
		_status.text = "Erreur de connexion (%d)." % err
