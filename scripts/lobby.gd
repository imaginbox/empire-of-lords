extends Control
## Menu principal / Lobby.
##
##   - SOLO            : la campagne hors-ligne.
##   - TOURNOI OFFICIEL: le monde Conquete PERSISTANT cree par le serveur VPS.
##                       Toujours disponible. On le REJOINT directement.
##   - PARTIES         : des parties creees par les JOUEURS (nommees, listees
##                       dans "parties en cours"). On en cree une, d'autres la
##                       rejoignent, l'hote la demarre.

var _net: Node
var _status: Label
var _list_box: VBoxContainer
var _name_edit: LineEdit
var _start_btn: Button
var _quit_btn: Button
var _in_match_id := -1
var _am_host := false


func _ready() -> void:
	_net = get_node_or_null("/root/LanNet")
	_build()
	if _net == null:
		_set_status("Réseau indisponible.")
		return
	_net.match_list_changed.connect(_refresh_list)
	_net.game_started.connect(_on_game_started)
	_net.connected.connect(func(): _set_status("Connecté au serveur."))
	_net.connection_failed.connect(func(): _set_status("Serveur injoignable — le mode Solo reste disponible."))
	var err: Error = _net.connect_to_server()
	if err != OK:
		_set_status("Connexion impossible (err %d)." % err)


# ------------------------------------------------------------- UI

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.12, 0.16)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var title := Label.new()
	title.text = "Empire of Lords"
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Color(1, 0.88, 0.55))
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	title.add_theme_constant_override("outline_size", 6)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.position = Vector2(0, 16)
	title.size = Vector2(0, 46)
	add_child(title)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(600, 640)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	center.add_child(scroll)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	vb.custom_minimum_size = Vector2(560, 0)
	scroll.add_child(vb)

	var b_solo := _make_button("SOLO (campagne)", Color(0.2, 0.5, 0.25))
	b_solo.custom_minimum_size = Vector2(0, 42)
	b_solo.pressed.connect(_on_solo)
	vb.add_child(b_solo)

	var sep := HSeparator.new()
	vb.add_child(sep)

	# ---------- TOURNOI OFFICIEL ----------
	vb.add_child(_section_label("TOURNOI OFFICIEL (Conquête)"))
	var b_tournament := _make_button("⚔  Rejoindre le Tournoi — le monde officiel", Color(0.55, 0.32, 0.15))
	b_tournament.custom_minimum_size = Vector2(0, 48)
	b_tournament.pressed.connect(func(): _net.call("join_tournament"))
	vb.add_child(b_tournament)
	var note_t := Label.new()
	note_t.text = "Le Tournoi est le monde persistant et partagé créé par le serveur officiel. "
	note_t.text += "Il tourne en continu (saisons, zones, course au Top) : vous le rejoignez à tout moment."
	note_t.add_theme_font_size_override("font_size", 12)
	note_t.add_theme_color_override("font_color", Color(0.7, 0.78, 0.85))
	note_t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(note_t)

	var sep2 := HSeparator.new()
	vb.add_child(sep2)

	# ---------- PARTIES DES JOUEURS ----------
	vb.add_child(_section_label("PARTIES DES JOUEURS"))
	_status = Label.new()
	_status.text = "Connexion au serveur…"
	_status.add_theme_font_size_override("font_size", 13)
	_status.add_theme_color_override("font_color", Color(1, 0.75, 0.5))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_status)

	var create_panel := PanelContainer.new()
	vb.add_child(create_panel)
	var cb := VBoxContainer.new()
	cb.add_theme_constant_override("separation", 6)
	create_panel.add_child(cb)
	cb.add_child(_section_label("CRÉER UNE PARTIE"))

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 6)
	cb.add_child(name_row)
	name_row.add_child(_field_label("Nom de la partie :"))
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "ex. La revanche du vendredi"
	_name_edit.custom_minimum_size = Vector2(240, 30)
	name_row.add_child(_name_edit)

	var b_create := _make_button("Créer la partie", Color(0.45, 0.3, 0.55))
	b_create.pressed.connect(_on_create)
	cb.add_child(b_create)

	vb.add_child(_section_label("PARTIES EN COURS"))
	_list_box = VBoxContainer.new()
	_list_box.add_theme_constant_override("separation", 6)
	vb.add_child(_list_box)

	_start_btn = _make_button("Démarrer ma partie", Color(0.18, 0.5, 0.3))
	_start_btn.pressed.connect(func(): _net.call("start_match"))
	_start_btn.visible = false
	vb.add_child(_start_btn)

	_quit_btn = _make_button("Quitter ma partie", Color(0.5, 0.25, 0.25))
	_quit_btn.pressed.connect(func(): _net.call("leave_match"))
	_quit_btn.visible = false
	vb.add_child(_quit_btn)


func _section_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", Color(0.8, 0.95, 0.8))
	return l


func _field_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 13)
	l.custom_minimum_size = Vector2(140, 0)
	return l


func _make_button(text: String, color: Color) -> Button:
	var b := Button.new()
	b.text = text
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(6)
	b.add_theme_stylebox_override("normal", s)
	return b


func _set_status(text: String) -> void:
	if _status != null:
		_status.text = text


# ------------------------------------------------------------- actions

func _on_solo() -> void:
	get_tree().change_scene_to_file("res://scenes/Main.tscn")


func _on_create() -> void:
	var name_text: String = _name_edit.text.strip_edges()
	if name_text.is_empty():
		_set_status("Donnez un nom à votre partie.")
		return
	_net.call("create_match", name_text, "vs")
	_set_status("Partie « %s » créée — elle apparaît dans la liste." % name_text)
	_name_edit.text = ""


func _refresh_list(list: Array) -> void:
	for child in _list_box.get_children():
		child.queue_free()
	_in_match_id = -1
	_am_host = false
	var me: int = _net.my_id() if _net != null else 0
	if list.is_empty():
		var empty := Label.new()
		empty.text = "Aucune partie en cours. Créez la première !"
		empty.add_theme_color_override("font_color", Color(0.6, 0.65, 0.7))
		_list_box.add_child(empty)
	else:
		for m in list:
			_list_box.add_child(_match_row(m, me))
	var in_waiting: bool = _in_match_id > 0
	_start_btn.visible = _am_host and in_waiting
	_quit_btn.visible = _in_match_id > 0


func _match_row(m: Dictionary, me: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var p_count: int = (m.get("players") as Array).size()
	var status_txt: String = " (en cours)" if m.get("status") == "running" else ""
	var label := Label.new()
	label.text = "%s — %d joueur(s)%s" % [m.get("name", "?"), p_count, status_txt]
	label.custom_minimum_size = Vector2(320, 0)
	label.add_theme_font_size_override("font_size", 14)
	row.add_child(label)

	if m.get("status") == "waiting" and me > 0 and int(m.get("id")) != _in_match_id:
		var join := _make_button("Rejoindre", Color(0.18, 0.42, 0.55))
		var m_id: int = int(m.get("id"))
		join.pressed.connect(func(): _net.call("join_match", m_id))
		row.add_child(join)
	elif me > 0 and m.get("players") != null and me in (m.get("players") as Array):
		var tag := Label.new()
		tag.text = "✦ vous êtes ici"
		tag.add_theme_color_override("font_color", Color(0.5, 1, 0.6))
		row.add_child(tag)
		_in_match_id = int(m.get("id"))
		if m.get("host") == me:
			_am_host = true
	return row


func _on_game_started(_m: String) -> void:
	print("LOBBY: partie démarrée — lancement du monde.")
	get_tree().change_scene_to_file("res://scenes/Multiplayer.tscn")
