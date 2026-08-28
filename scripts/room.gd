extends Control
## Salle d'attente dédiée d'une partie VS (modèle VPS).
##
## Interface SÉPARÉE du lobby : quand un joueur crée ou rejoint une partie, il
## bascule ici et voit TOUS les joueurs connectés à la partie + leur statut
## PRÊT, discute dans le chat, appuie sur PRÊT, ou quitte. La partie démarre
## automatiquement à 4/4 ou dès que tout le monde est prêt (2+).

var _net: Node = null
var _my_match: Dictionary = {}
var _in_match := false
var _ready_state := false
var _leaving := false

# UI refs
var _title: Label
var _sub: Label
var _roster: Label
var _status: Label
var _ready_btn: Button
var _chat_box: RichTextLabel
var _chat_input: LineEdit


func _ready() -> void:
	_net = get_node_or_null("/root/LanNet")
	_build()
	if _net == null:
		_status.text = "Réseau indisponible."
		return
	_net.match_list_changed.connect(_on_list)
	_net.chat_message.connect(_on_chat_message)
	_net.game_started.connect(_on_game_started)
	_net.connection_failed.connect(_go_lobby)
	_net.call("request_matches")


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.10, 0.16)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	add_child(margin)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	margin.add_child(vb)

	_title = Label.new()
	_title.text = "Salle d'attente…"
	_title.add_theme_font_size_override("font_size", 26)
	_title.add_theme_color_override("font_color", Color(1, 0.9, 0.6))
	vb.add_child(_title)

	_sub = Label.new()
	_sub.text = "Rejoindre la partie…"
	_sub.add_theme_font_size_override("font_size", 14)
	_sub.add_theme_color_override("font_color", Color(0.75, 0.8, 0.9))
	vb.add_child(_sub)

	_roster = Label.new()
	_roster.text = "Joueurs : —"
	_roster.add_theme_font_size_override("font_size", 16)
	_roster.add_theme_color_override("font_color", Color(0.85, 0.95, 0.85))
	_roster.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_roster)

	_status = Label.new()
	_status.text = "La partie démarre automatiquement à 4/4 ou dès que tout le monde est prêt (2+)."
	_status.add_theme_font_size_override("font_size", 13)
	_status.add_theme_color_override("font_color", Color(0.9, 0.75, 0.4))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_status)

	_ready_btn = Button.new()
	_ready_btn.text = "PRÊT"
	_ready_btn.custom_minimum_size = Vector2(0, 42)
	_ready_btn.pressed.connect(_on_ready_toggle)
	vb.add_child(_ready_btn)

	var sep := HSeparator.new()
	vb.add_child(sep)
	var l := Label.new()
	l.text = "Chat — discutez en attendant :"
	l.add_theme_font_size_override("font_size", 14)
	vb.add_child(l)

	_chat_box = RichTextLabel.new()
	_chat_box.bbcode_enabled = true
	_chat_box.custom_minimum_size = Vector2(0, 140)
	_chat_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(_chat_box)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	vb.add_child(hb)
	_chat_input = LineEdit.new()
	_chat_input.placeholder_text = "Votre message…"
	_chat_input.custom_minimum_size = Vector2(0, 34)
	_chat_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chat_input.text_submitted.connect(func(_t: String): _on_chat_send())
	hb.add_child(_chat_input)
	var b_send := Button.new()
	b_send.text = "Envoyer"
	b_send.pressed.connect(_on_chat_send)
	hb.add_child(b_send)

	var b_quit := Button.new()
	b_quit.text = "Quitter la partie"
	b_quit.pressed.connect(_on_quit)
	vb.add_child(b_quit)


# ------------------------------------------------------------- logique salle

func _on_list(list: Array) -> void:
	var me: int = _net.my_id() if _net != null else 0
	_my_match = {}
	var found_any := false
	for m in list:
		if str(m.get("mode", "vs")) == "vs" and m.get("players") != null \
				and me in (m.get("players") as Array):
			found_any = true
			if m.get("status") == "waiting":
				_my_match = m
			# si "running" : la partie démarre, _on_game_started basculera.
			break
	if not _my_match.is_empty():
		_in_match = true
		_render()
	elif _in_match and not found_any:
		# La partie a été fermée (plus présente du tout) -> retour lobby.
		_go_lobby()


func _render() -> void:
	var m := _my_match
	var ai_txt: String = "avec IA" if bool(m.get("with_ai", true)) else "sans IA"
	_title.text = "Salle d'attente — %s" % m.get("name", "Partie")
	_sub.text = "Mode VS · %s · hôte : %s" % [ai_txt, m.get("host_name", "Joueur %d" % int(m.get("host", 0)))]
	var players: Array = m.get("players", [])
	var names: Dictionary = m.get("names", {})
	var rdy: Dictionary = m.get("ready", {})
	var me: int = _net.my_id() if _net != null else 0
	var txt := "Joueurs (%d/%d) :\n" % [players.size(), int(m.get("max", 4))]
	for p: int in players:
		var nm: String = str(names.get(p, "Joueur %d" % p))
		var r: String = "✔ PRÊT" if bool(rdy.get(p, false)) else "… en attente"
		txt += "  • %s — %s%s\n" % [nm, r, "  (vous)" if p == me else ""]
	_roster.text = txt


func _on_ready_toggle() -> void:
	_ready_state = not _ready_state
	_ready_btn.text = "PAS PRÊT" if _ready_state else "PRÊT"
	_ready_btn.modulate = Color(0.9, 0.5, 0.4) if _ready_state else Color.WHITE
	_net.call("set_ready", _ready_state)


func _on_chat_send() -> void:
	var t: String = _chat_input.text
	_net.call("send_chat", t)
	_chat_input.text = ""


func _on_chat_message(sender: String, text: String) -> void:
	_chat_box.push_color(Color(0.55, 0.9, 1.0))
	_chat_box.add_text(sender)
	_chat_box.pop()
	_chat_box.add_text(": %s\n" % text)


func _on_game_started(_m: String) -> void:
	if _leaving:
		return
	_leaving = true
	get_tree().change_scene_to_file("res://scenes/Multiplayer.tscn")


func _on_quit() -> void:
	if _leaving:
		return
	_leaving = true
	_net.call("leave_match")
	get_tree().change_scene_to_file("res://scenes/Lobby.tscn")


func _go_lobby() -> void:
	if _leaving:
		return
	_leaving = true
	get_tree().change_scene_to_file("res://scenes/Lobby.tscn")
