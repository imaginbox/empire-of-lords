extends Control
## Menu principal / Lobby — 3 choix :
##
##   1) SOLO             : campagne Conquete vs IA (sauvegarde, pause).
##   2) PARTIES VS       : creer une partie (attente + chat) ou en rejoindre
##                         une qui attend des joueurs. Partie rapide.
##   3) LE JEU DE CONQUÊTE : monde PERSISTANT cree par l'ADMIN (le serveur
##                         officiel du VPS). Il apparait dans une liste et on
##                         le REJOINT. Contient tutoriel, saisons, course au Top.

const SETTINGS_PATH := "user://settings.json"

var _net: Node
var _status: Label
var _list_box: VBoxContainer
var _name_edit: LineEdit
var _pseudo_edit: LineEdit
var _retry_btn: Button
var _start_btn: Button
var _quit_btn: Button
var _chat_panel: PanelContainer
var _chat_log: RichTextLabel
var _chat_input: LineEdit
var _in_match_id := -1
var _am_host := false
var _pseudo := ""
var _zone_layer: CanvasLayer
var _zone_box: VBoxContainer


func _ready() -> void:
	_net = get_node_or_null("/root/LanNet")
	_load_settings()
	_build()
	_build_zone_picker()
	if _net != null:
		_net.set_player_name(_pseudo)
		_net.match_list_changed.connect(_refresh_list)
		_net.game_started.connect(_on_game_started)
		_net.chat_message.connect(_on_chat_message)
		_net.zone_choice_offered.connect(_on_zone_choice_offered)
		_net.connected.connect(func(): _set_status("Connecté au serveur en tant que %s." % _pseudo))
		_net.connection_failed.connect(_on_connection_failed)
		_connect()
	else:
		_set_status("Réseau indisponible.")


func _connect() -> void:
	if _net == null:
		return
	if _retry_btn != null:
		_retry_btn.visible = false
	_set_status("Connexion au serveur…")
	var err: Error = _net.connect_to_server()
	if err != OK:
		_set_status("Connexion impossible (err %d)." % err)
		if _retry_btn != null:
			_retry_btn.visible = true


func _on_connection_failed() -> void:
	_set_status("Serveur injoignable — le mode Solo reste disponible.")
	if _retry_btn != null:
		_retry_btn.visible = true


# ------------------------------------------------------------- settings (pseudo persiste)

func _load_settings() -> void:
	var d: Dictionary = {}
	if FileAccess.file_exists(SETTINGS_PATH):
		var f := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
		var txt := f.get_as_text()
		f.close()
		var data: Variant = JSON.parse_string(txt)
		if data is Dictionary:
			d = data
	_pseudo = str(d.get("pseudo", ""))


func _save_settings() -> void:
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify({"pseudo": _pseudo}))
	f.close()


func _on_pseudo_changed(new_text: String) -> void:
	_pseudo = new_text.strip_edges()
	if _net != null:
		_net.set_player_name(_pseudo)
	_save_settings()


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
	title.position = Vector2(0, 30)
	title.size = Vector2(0, 46)
	add_child(title)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(640, 680)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	center.add_child(scroll)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	vb.custom_minimum_size = Vector2(600, 0)
	scroll.add_child(vb)

	# ================= 1) SOLO =================
	vb.add_child(_section_label("1 · SOLO"))
	var b_solo := _make_button("🎮  Jouer en Solo — Conquête vs IA (sauvegarde, pause)", Color(0.2, 0.5, 0.25))
	b_solo.custom_minimum_size = Vector2(0, 46)
	b_solo.pressed.connect(_on_solo)
	vb.add_child(b_solo)
	var note_s := Label.new()
	note_s.text = "Campagne hors-ligne : conquérez les zones, développez votre royaume, "
	note_s.text += "avec pause, vitesse et sauvegarde de progression."
	note_s.add_theme_font_size_override("font_size", 12)
	note_s.add_theme_color_override("font_color", Color(0.7, 0.78, 0.85))
	note_s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(note_s)

	var sep := HSeparator.new()
	vb.add_child(sep)

	# ================= 2) PARTIES VS =================
	vb.add_child(_section_label("2 · PARTIES VS"))
	var note_v := Label.new()
	note_v.text = "Parties rapides créées par les joueurs : créez-en une (attente + chat), "
	note_v.text += "ou rejoignez une partie qui attend des joueurs."
	note_v.add_theme_font_size_override("font_size", 12)
	note_v.add_theme_color_override("font_color", Color(0.7, 0.78, 0.85))
	note_v.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(note_v)

	var sep2 := HSeparator.new()
	vb.add_child(sep2)

	# ================= 3) LE JEU DE CONQUÊTE (persistant) =================
	vb.add_child(_section_label("3 · LE JEU DE CONQUÊTE (monde persistant)"))
	var note_c := Label.new()
	note_c.text = "Le monde persistant, créé par le serveur officiel (admin) et toujours actif. "
	note_c.text += "Il contient le tutoriel, les saisons, les zones et la course au Top, en multijoueur. "
	note_c.text += "Rejoignez-le depuis la liste ci-dessous."
	note_c.add_theme_font_size_override("font_size", 12)
	note_c.add_theme_color_override("font_color", Color(0.7, 0.78, 0.85))
	note_c.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(note_c)
	_add_conquest_row(vb)

	var pseudo_row := HBoxContainer.new()
	pseudo_row.add_theme_constant_override("separation", 6)
	vb.add_child(pseudo_row)
	pseudo_row.add_child(_field_label("Votre pseudo :"))
	_pseudo_edit = LineEdit.new()
	_pseudo_edit.placeholder_text = "ex. LordAlaric"
	_pseudo_edit.text = _pseudo
	_pseudo_edit.custom_minimum_size = Vector2(240, 30)
	_pseudo_edit.text_changed.connect(_on_pseudo_changed)
	pseudo_row.add_child(_pseudo_edit)

	_status = Label.new()
	_status.text = "Connexion au serveur…"
	_status.add_theme_font_size_override("font_size", 13)
	_status.add_theme_color_override("font_color", Color(1, 0.75, 0.5))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_status)

	_retry_btn = _make_button("↻ Re-tenter la connexion", Color(0.4, 0.4, 0.45))
	_retry_btn.pressed.connect(_connect)
	_retry_btn.visible = false
	vb.add_child(_retry_btn)

	var create_panel := PanelContainer.new()
	vb.add_child(create_panel)
	var cb := VBoxContainer.new()
	cb.add_theme_constant_override("separation", 6)
	create_panel.add_child(cb)
	cb.add_child(_section_label("CRÉER UNE PARTIE VS"))

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 6)
	cb.add_child(name_row)
	name_row.add_child(_field_label("Nom de la partie :"))
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "ex. La revanche du vendredi"
	_name_edit.custom_minimum_size = Vector2(240, 30)
	name_row.add_child(_name_edit)

	var b_create := _make_button("Créer la partie VS", Color(0.45, 0.3, 0.55))
	b_create.pressed.connect(_on_create)
	cb.add_child(b_create)

	vb.add_child(_section_label("PARTIES VS EN COURS (en attente de joueurs)"))
	_list_box = VBoxContainer.new()
	_list_box.add_theme_constant_override("separation", 6)
	vb.add_child(_list_box)

	_start_btn = _make_button("Démarrer la partie", Color(0.18, 0.5, 0.3))
	_start_btn.pressed.connect(func(): _net.call("start_match"))
	_start_btn.visible = false
	vb.add_child(_start_btn)

	_quit_btn = _make_button("Quitter la partie", Color(0.5, 0.25, 0.25))
	_quit_btn.pressed.connect(func(): _net.call("leave_match"))
	_quit_btn.visible = false
	vb.add_child(_quit_btn)

	_build_chat(vb)

	var version := Label.new()
	version.text = "v1.0 · serveur officiel 195-35-24-169"
	version.add_theme_font_size_override("font_size", 11)
	version.add_theme_color_override("font_color", Color(0.5, 0.55, 0.6))
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(version)


func _add_conquest_row(parent: Node) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var label := Label.new()
	label.text = "🌐 Monde officiel — Conquête persistante (tutoriel, saisons, Top)"
	label.custom_minimum_size = Vector2(420, 0)
	label.add_theme_font_size_override("font_size", 14)
	row.add_child(label)
	var join := _make_button("Rejoindre", Color(0.55, 0.32, 0.15))
	join.custom_minimum_size = Vector2(110, 36)
	join.pressed.connect(func(): _net.call("join_tournament"))
	row.add_child(join)
	parent.add_child(row)


func _build_chat(parent: Node) -> void:
	_chat_panel = PanelContainer.new()
	parent.add_child(_chat_panel)
	var cb := VBoxContainer.new()
	cb.add_theme_constant_override("separation", 6)
	_chat_panel.add_child(cb)
	cb.add_child(_section_label("💬 DISCUSSION DE LA PARTIE"))
	_chat_log = RichTextLabel.new()
	_chat_log.bbcode_enabled = false
	_chat_log.custom_minimum_size = Vector2(0, 120)
	_chat_log.scroll_following = true
	_chat_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cb.add_child(_chat_log)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	cb.add_child(hb)
	_chat_input = LineEdit.new()
	_chat_input.placeholder_text = "Écrivez un message…"
	_chat_input.custom_minimum_size = Vector2(0, 30)
	_chat_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chat_input.text_submitted.connect(func(_t: String): _on_chat_send())
	hb.add_child(_chat_input)
	var send := _make_button("Envoyer", Color(0.18, 0.42, 0.55))
	send.pressed.connect(_on_chat_send)
	hb.add_child(send)
	_chat_panel.visible = false


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
	_set_status("Partie VS « %s » créée — elle apparaît dans la liste." % name_text)
	_name_edit.text = ""


func _on_chat_send() -> void:
	var t: String = _chat_input.text
	_net.call("send_chat", t)
	_chat_input.text = ""


func _on_chat_message(sender: String, text: String) -> void:
	_chat_log.push_color(Color(0.55, 0.9, 1.0))
	_chat_log.add_text(sender)
	_chat_log.pop()
	_chat_log.add_text(": %s\n" % text)


func _refresh_list(list: Array) -> void:
	for child in _list_box.get_children():
		child.queue_free()
	_in_match_id = -1
	_am_host = false
	var me: int = _net.my_id() if _net != null else 0
	var vs_only: Array = []
	for m in list:
		if m.get("mode", "vs") == "vs":
			vs_only.append(m)
	if vs_only.is_empty():
		var empty := Label.new()
		empty.text = "Aucune partie VS en attente. Créez la première !"
		empty.add_theme_color_override("font_color", Color(0.6, 0.65, 0.7))
		_list_box.add_child(empty)
	else:
		for m in vs_only:
			_list_box.add_child(_match_row(m, me))
	var in_waiting: bool = _in_match_id > 0
	_start_btn.visible = _am_host and in_waiting
	_quit_btn.visible = _in_match_id > 0
	if _chat_panel != null:
		_chat_panel.visible = _in_match_id > 0


func _match_row(m: Dictionary, me: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var p_count: int = (m.get("players") as Array).size()
	var status_txt: String = " (en cours)" if m.get("status") == "running" else ""
	var host_name: String = str(m.get("host_name", "Joueur %d" % int(m.get("host", 0))))
	var label := Label.new()
	label.text = "%s — %d joueur(s)%s · par %s" % [m.get("name", "?"), p_count, status_txt, host_name]
	label.custom_minimum_size = Vector2(360, 0)
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
	if _zone_layer != null:
		_zone_layer.visible = false
	get_tree().change_scene_to_file("res://scenes/Multiplayer.tscn")


# ------------------------------------------------------------- choix de zone

func _build_zone_picker() -> void:
	_zone_layer = CanvasLayer.new()
	_zone_layer.name = "ZonePicker"
	_zone_layer.layer = 50
	add_child(_zone_layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.82)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_zone_layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_zone_layer.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 0)
	center.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)
	var title := Label.new()
	title.text = "🏰 Choisissez votre zone de départ"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	vb.add_child(title)
	var note := Label.new()
	note.text = "Votre royaume commence dans la zone que vous choisissez. "
	note.text += "La conquête progresse vers le CENTRE de la carte : la zone du milieu est la finale, "
	note.text += "où se décidera le vainqueur ultime de la saison !"
	note.add_theme_font_size_override("font_size", 13)
	note.add_theme_color_override("font_color", Color(0.8, 0.85, 0.9))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(note)
	_zone_box = VBoxContainer.new()
	_zone_box.add_theme_constant_override("separation", 6)
	vb.add_child(_zone_box)
	_zone_layer.visible = false


func _on_zone_choice_offered(zones: Array) -> void:
	if _zone_box == null:
		return
	for ch in _zone_box.get_children():
		ch.queue_free()
	for z in zones:
		var btn := _make_button("⚔ %s  —  %d ville(s) libres" % [str(z["name"]), int(z["free"])],
			Color(0.35, 0.2, 0.1))
		btn.custom_minimum_size = Vector2(0, 36)
		var zi: int = int(z["index"])
		btn.pressed.connect(func(): _pick_zone(zi))
		_zone_box.add_child(btn)
	_zone_layer.visible = true
	_set_status("Choisissez votre zone de départ 🏰")


func _pick_zone(zone_index: int) -> void:
	_zone_layer.visible = false
	_set_status("Zone choisie — entrée dans le monde officiel…")
	_net.call("pick_zone", zone_index)
