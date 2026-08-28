extends Control
## Waiting room / lobby before a multiplayer match starts. Shows the connected
## players, a chat to talk while waiting, and a countdown that launches the game
## scene once the players are ready. The host (ENet server, peer 1) orchestrates
## the roster and the start; chat is relayed through the host.

const CHAT_MAX := 200

var _net: Node = null
var _is_host := false
var _started := false
var _roster: Array = []        # peer ids present in the room

# UI refs
var _title: Label
var _players_label: Label
var _countdown: Label
var _chat_box: RichTextLabel
var _chat_input: LineEdit
var _start_btn: Button
var _host_ip_label: Label


func _ready() -> void:
	_net = get_node_or_null("/root/LanNet")
	_build()
	if _net == null:
		_countdown.text = "Réseau indisponible."
		return
	_is_host = bool(_net.call("is_host"))
	_net.connection_failed.connect(_on_net_failed)
	_start_btn.visible = _is_host
	if _is_host:
		_host_ip_label.text = "IP LAN de l'hôte : %s" % _local_ip()
		_net.peer_joined.connect(_on_peer_joined_host)
		_net.peer_left.connect(_on_peer_left_host)
		_roster = [1]
		_refresh_roster_ui()
	else:
		if not bool(_net.call("is_connected_to_room")):
			_countdown.text = "Connexion à la salle…"
			await _net.connected
		_title.text = "%s — Salle d'attente (rejointe)" % _mode_name()


func _mode_name() -> String:
	if _net == null:
		return "Multijoueur"
	return "Multi VS" if str(_net.get("mode")) == "vs" else "Multi Conquête"


func _local_ip() -> String:
	for a in IP.get_local_addresses():
		if a.contains(".") and not a.begins_with("127."):
			return a
	return "127.0.0.1"


# ------------------------------------------------------------- UI

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.11, 0.15)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	add_child(margin)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	margin.add_child(vb)

	_title = Label.new()
	_title.text = "Salle d'attente"
	_title.add_theme_font_size_override("font_size", 24)
	_title.add_theme_color_override("font_color", Color(1, 0.9, 0.6))
	vb.add_child(_title)

	_host_ip_label = Label.new()
	_host_ip_label.text = ""
	_host_ip_label.add_theme_font_size_override("font_size", 13)
	_host_ip_label.add_theme_color_override("font_color", Color(0.85, 0.9, 1))
	vb.add_child(_host_ip_label)

	_players_label = Label.new()
	_players_label.text = "Joueurs : 1"
	_players_label.add_theme_font_size_override("font_size", 16)
	vb.add_child(_players_label)

	_countdown = Label.new()
	_countdown.text = "En attente d'autres joueurs…"
	_countdown.add_theme_font_size_override("font_size", 26)
	_countdown.add_theme_color_override("font_color", Color(1, 0.8, 0.4))
	vb.add_child(_countdown)

	_start_btn = Button.new()
	_start_btn.text = "Démarrer la partie (décompte)"
	_start_btn.custom_minimum_size = Vector2(0, 40)
	_start_btn.pressed.connect(_on_start_pressed)
	vb.add_child(_start_btn)

	var sep := HSeparator.new()
	vb.add_child(sep)
	vb.add_child(_mk_label("Chat — discutez en attendant :", 14))

	_chat_box = RichTextLabel.new()
	_chat_box.bbcode_enabled = true
	_chat_box.custom_minimum_size = Vector2(0, 150)
	_chat_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(_chat_box)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	vb.add_child(hb)
	_chat_input = LineEdit.new()
	_chat_input.placeholder_text = "Votre message…"
	_chat_input.custom_minimum_size = Vector2(0, 34)
	_chat_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chat_input.text_submitted.connect(func(_t: String): _send_chat())
	hb.add_child(_chat_input)
	var b_send := Button.new()
	b_send.text = "Envoyer"
	b_send.pressed.connect(_send_chat)
	hb.add_child(b_send)

	var b_quit := Button.new()
	b_quit.text = "Quitter la salle"
	b_quit.pressed.connect(_on_quit)
	vb.add_child(b_quit)


func _mk_label(text: String, font_size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	return l


# ------------------------------------------------------------- roster

func _on_peer_joined_host(id: int) -> void:
	if id not in _roster:
		_roster.append(int(id))
	_refresh_roster_ui()
	_broadcast_roster()
	_add_system_line("Joueur %d a rejoint la salle." % id)
	if _started:
		# The countdown is already running: catch this late joiner up.
		_rpc_start_countdown.rpc_id(id)
	else:
		_maybe_auto_start()


func _on_peer_left_host(id: int) -> void:
	_roster.erase(int(id))
	_refresh_roster_ui()
	_broadcast_roster()
	_add_system_line("Joueur %d a quitté la salle." % id)


func _refresh_roster_ui() -> void:
	_roster.sort()
	var names: Array = []
	for p in _roster:
		names.append("Joueur %d" % int(p))
	_players_label.text = "Joueurs (%d) : %s" % [names.size(), ", ".join(names)]


@rpc("reliable")
func _sync_roster(ids: Array) -> void:
	_roster = ids.duplicate()
	_refresh_roster_ui()


func _broadcast_roster() -> void:
	_sync_roster.rpc(_roster)


# ------------------------------------------------------------- start / countdown

func _maybe_auto_start() -> void:
	if _started or not _is_host or _roster.size() < 2:
		return
	_started = true  # reserve so only one path triggers
	_countdown.text = "Joueurs prêts ! Démarrage…"
	await get_tree().create_timer(1.5).timeout
	_begin_countdown()


func _on_start_pressed() -> void:
	if _started or not _is_host:
		return
	_started = true
	_begin_countdown()


func _begin_countdown() -> void:
	_start_btn.disabled = true
	_start_btn.visible = false
	_rpc_start_countdown.rpc()
	_run_countdown()


@rpc("reliable")
func _rpc_start_countdown() -> void:
	if not _started:
		_started = true
		_start_btn.disabled = true
		_start_btn.visible = false
	_run_countdown()


func _run_countdown() -> void:
	for i in range(5, 0, -1):
		_countdown.text = "La partie commence dans %d…" % i
		await get_tree().create_timer(1.0).timeout
	_countdown.text = "C'est parti !"
	await get_tree().create_timer(0.4).timeout
	get_tree().change_scene_to_file("res://scenes/Multiplayer.tscn")


# ------------------------------------------------------------- chat

func _send_chat() -> void:
	var text: String = _chat_input.text.strip_edges()
	if text.is_empty():
		return
	_chat_input.text = ""
	if _is_host:
		_relay_chat("Joueur 1", text)
	else:
		_chat_from_client.rpc_id(1, text)


@rpc("any_peer", "reliable")
func _chat_from_client(text: String) -> void:
	if not _is_host:
		return
	var sender: int = multiplayer.get_remote_sender_id()
	_relay_chat("Joueur %d" % sender, text)


func _relay_chat(who: String, text: String) -> void:
	_chat_relay.rpc(who, text)
	_add_chat_line(who, text)


@rpc("reliable")
func _chat_relay(who: String, text: String) -> void:
	_add_chat_line(who, text)


func _add_chat_line(who: String, text: String) -> void:
	_chat_box.append_text("[b]%s[/b] : %s\n" % [who, text])
	if _chat_box.get_line_count() > CHAT_MAX:
		_chat_box.text = _chat_box.text.substr(int(_chat_box.text.length() / 2.0))


func _add_system_line(text: String) -> void:
	_chat_box.append_text("[color=#9ac]%s[/color]\n" % text)


# ------------------------------------------------------------- misc

func _on_net_failed() -> void:
	_countdown.text = "Connexion perdue."
	await get_tree().create_timer(1.2).timeout
	get_tree().change_scene_to_file("res://scenes/Lobby.tscn")


func _on_quit() -> void:
	if _net != null:
		_net.call("disconnect_from_room")
	get_tree().change_scene_to_file("res://scenes/Lobby.tscn")
