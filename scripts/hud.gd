extends Control
## HUD: top bar, node info / attack bar, bottom nav, skill tree, forge and log.

var game: GameState = null
var main_node: Node = null

var _src_city: CityNode = null
var _dst_city: CityNode = null

# top bar
var _lvl_label: Label
var _xp_bar: ProgressBar
var _gold_label: Label
var _gems_label: Label
var _quest_label: Label
var _season_label: Label
var _peace_label: Label
var _zone_label: Label

# modals
var _league_panel: PanelContainer
var _league_info: RichTextLabel
var _top_panel: PanelContainer
var _top_info: RichTextLabel
var _realm_panel: PanelContainer
var _realm_info: RichTextLabel
var _alliance_panel: PanelContainer
var _alliance_info: RichTextLabel
var _recruit_btn: Button
var _tournament_panel: PanelContainer
var _tournament_info: RichTextLabel
var _challenge_btn: Button
var _guide_panel: PanelContainer
var _guide_title: Label
var _guide_body: RichTextLabel
var _guide_prev_btn: Button
var _guide_next_btn: Button
var _guide_progress: Label
var _guide_page: int = 0
var _guide_mode: String = "ref"   # "ref" = reference guide, "tut" = interactive walkthrough
var _tut_hand: Label              # floating hand icon pointing at the target
var _tut_bubble: PanelContainer   # small non-blocking tooltip near the hand
var _tut_bubble_label: Label
var _tut_action_btn: Button       # button inside the bubble for next/start/end
var _tut_progress: Label
var _tut_skip: Button
var _forge_nav_btn: Button
var _context_hints: Dictionary = {}   # feature_key -> shown bool
var _season_overlay: Control

# contextual panel
var _ctx_panel: PanelContainer
var _ctx_title: Label
var _ctx_info: RichTextLabel
var _upgrade_btn: Button
var _ctx_clear_btn: Button
var _attack_flow: Control
var _source_label: Label
var _target_label: Label
var _travel_label: Label
var _slider: HSlider
var _send_btn: Button

# modal panels
var _skill_panel: PanelContainer
var _forge_panel: PanelContainer
var _log_panel: PanelContainer
var _skills_root: VBoxContainer
var _points_label: Label
var _forge_items: VBoxContainer
var _forge_btn: Button
var _forge_stats: Label
var _log_list: VBoxContainer

# toast
var _toast: Label
var _toast_timer: Timer


func attach(state: GameState) -> void:
	game = state
	_build()
	game.log_message.connect(_on_log_message)
	game.warning.connect(toast)
	game.game_over.connect(_on_game_over)
	game.season_ended.connect(_on_season_ended)
	game.alliance_changed.connect(refresh_alliance_panel)
	game.tournament_changed.connect(refresh_tournament_panel)
	game.player.xp_changed.connect(func(_x): refresh_top_bar())
	game.player.gold_changed.connect(func(_g): refresh_top_bar())
	game.player.gems_changed.connect(func(_g): refresh_top_bar())
	game.peace_ended.connect(func(): _peace_label.visible = false)
	refresh_top_bar()
	# Interactive tutorial auto-shows for new players; the "?" button reopens
	# the full reference guide anytime.
	_start_tutorial()


func _build() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_top_bar()
	_build_bottom_bar()
	_build_context_panel()
	_build_skill_panel()
	_build_forge_panel()
	_build_log_panel()
	_build_league_panel()
	_build_top_panel()
	_build_realm_panel()
	_build_alliance_panel()
	_build_tournament_panel()
	_build_guide_panel()
	_build_toast()
	clear_selection()


# ---------------------------------------------------------------- top bar

func _build_top_bar() -> void:
	var bar := PanelContainer.new()
	bar.anchor_left = 0.0
	bar.anchor_top = 0.0
	bar.anchor_right = 1.0
	bar.anchor_bottom = 0.0
	bar.offset_left = 0.0
	bar.offset_top = 0.0
	bar.offset_right = 0.0
	bar.offset_bottom = 56.0
	add_child(bar)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)
	bar.add_child(hb)

	_lvl_label = _label("Niv 1")
	_lvl_label.custom_minimum_size = Vector2(80, 0)
	hb.add_child(_lvl_label)

	_xp_bar = ProgressBar.new()
	_xp_bar.custom_minimum_size = Vector2(120, 18)
	_xp_bar.show_percentage = false
	hb.add_child(_xp_bar)

	_gold_label = _label("Or 0")
	hb.add_child(_gold_label)

	_gems_label = _label("💎 0")
	hb.add_child(_gems_label)

	_season_label = _label("S1 · 2:00", 15, Color(0.7, 0.95, 1.0))
	_season_label.custom_minimum_size = Vector2(170, 0)
	hb.add_child(_season_label)

	_peace_label = _label("☮ PAIX", 15, Color(0.4, 0.9, 0.6))
	hb.add_child(_peace_label)

	_zone_label = _label("🗺 Zone 1/4", 14, Color(0.95, 0.85, 0.55))
	_zone_label.custom_minimum_size = Vector2(150, 0)
	hb.add_child(_zone_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(spacer)

	_quest_label = _label("Quête : conquérir votre zone", 13)
	hb.add_child(_quest_label)

	var b_help := _button("?")
	b_help.custom_minimum_size = Vector2(40, 0)
	b_help.pressed.connect(_open_guide_panel)
	hb.add_child(b_help)


# ---------------------------------------------------------------- bottom bar

func _build_bottom_bar() -> void:
	var bar := PanelContainer.new()
	bar.anchor_left = 0.0
	bar.anchor_top = 1.0
	bar.anchor_right = 1.0
	bar.anchor_bottom = 1.0
	bar.offset_left = 0.0
	bar.offset_top = -58.0
	bar.offset_right = 0.0
	bar.offset_bottom = 0.0
	add_child(bar)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_child(hb)

	# Left cluster: character / progression actions (primary gameplay).
	var left := HBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	hb.add_child(left)

	var b_skills := _button("Compétences")
	b_skills.pressed.connect(_open_skill_panel)
	left.add_child(b_skills)

	var b_forge := _button("Forge")
	b_forge.pressed.connect(_open_forge_panel)
	_forge_nav_btn = b_forge
	left.add_child(b_forge)

	# Visual gap between the two groups.
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(34, 0)
	hb.add_child(gap)

	# Right cluster: meta / social panels.
	var right := HBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	hb.add_child(right)

	var b_log := _button("Journal")
	b_log.pressed.connect(_open_log_panel)
	right.add_child(b_log)

	var b_league := _button("Ligue")
	b_league.pressed.connect(_open_league_panel)
	right.add_child(b_league)

	var b_top := _button("Top")
	b_top.pressed.connect(_open_top_panel)
	right.add_child(b_top)

	var b_realm := _button("Royaumes")
	b_realm.pressed.connect(_open_realm_panel)
	right.add_child(b_realm)

	var b_alliance := _button("Alliances")
	b_alliance.pressed.connect(_open_alliance_panel)
	right.add_child(b_alliance)

	var b_tournament := _button("Tournoi")
	b_tournament.pressed.connect(_open_tournament_panel)
	right.add_child(b_tournament)


# ---------------------------------------------------------------- contextual

func _build_context_panel() -> void:
	_ctx_panel = PanelContainer.new()
	_ctx_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_ctx_panel.offset_bottom = -74
	_ctx_panel.visible = false
	add_child(_ctx_panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	_ctx_panel.add_child(vb)

	_ctx_title = _label("", 20)
	vb.add_child(_ctx_title)

	_ctx_info = RichTextLabel.new()
	_ctx_info.bbcode_enabled = true
	_ctx_info.custom_minimum_size = Vector2(340, 60)
	_ctx_info.fit_content = true
	_ctx_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(_ctx_info)

	_upgrade_btn = _button("Améliorer la ville")
	_upgrade_btn.pressed.connect(_on_upgrade_pressed)
	vb.add_child(_upgrade_btn)

	# attack flow (slider + presets)
	_attack_flow = VBoxContainer.new()
	_attack_flow.add_theme_constant_override("separation", 6)
	vb.add_child(_attack_flow)

	var hb1 := HBoxContainer.new()
	hb1.add_theme_constant_override("separation", 8)
	_attack_flow.add_child(hb1)
	_source_label = _label("Source : -", 14)
	hb1.add_child(_source_label)

	var hb2 := HBoxContainer.new()
	hb2.add_theme_constant_override("separation", 8)
	_attack_flow.add_child(hb2)
	_target_label = _label("Cible : -", 14)
	hb2.add_child(_target_label)

	_travel_label = _label("Temps de trajet : -", 14)
	_attack_flow.add_child(_travel_label)

	_slider = HSlider.new()
	_slider.min_value = 1.0
	_slider.max_value = 100.0
	_slider.value = 100.0
	_slider.step = 1.0
	_slider.custom_minimum_size = Vector2(340, 24)
	_attack_flow.add_child(_slider)

	var hb3 := HBoxContainer.new()
	hb3.add_theme_constant_override("separation", 8)
	_attack_flow.add_child(hb3)
	for p in [25, 50, 75, 100]:
		var b := _button("%d%%" % p)
		b.pressed.connect(_on_preset.bind(p))
		hb3.add_child(b)

	_send_btn = _button("ENVOYER")
	_send_btn.pressed.connect(_on_send_pressed)
	_attack_flow.add_child(_send_btn)

	# Contextual "deselect" so the player can always cancel a selection easily.
	_ctx_clear_btn = _button("Désélectionner")
	_ctx_clear_btn.pressed.connect(_on_clear_pressed)
	vb.add_child(_ctx_clear_btn)


func _position_context_panel() -> void:
	_ctx_panel.reset_size()
	var psize: Vector2 = _ctx_panel.get_combined_minimum_size()
	_ctx_panel.position = Vector2((size.x - psize.x) * 0.5, size.y - psize.y - 74.0)


func show_node_info(c: CityNode) -> void:
	clear_selection()
	_src_city = null
	_dst_city = c
	_ctx_panel.visible = true
	_ctx_clear_btn.visible = true
	_attack_flow.visible = false
	_upgrade_btn.visible = false
	_ctx_title.text = "%s  (Lv %d)" % [c.node_name, c.level]
	_refresh_info(c)
	_position_context_panel()


func show_source_selected(c: CityNode) -> void:
	_src_city = c
	_dst_city = null
	_ctx_panel.visible = true
	_ctx_clear_btn.visible = true
	_attack_flow.visible = false
	_upgrade_btn.visible = false
	_ctx_title.text = "%s  (Lv %d)" % [c.node_name, c.level]
	_refresh_info(c)
	toast("Choisissez une cible (ville neutre ou ennemie) en cliquant dessus.")
	_position_context_panel()
	_tut_trigger("select_self")


func show_attack_bar(src: CityNode, dst: CityNode) -> void:
	_src_city = src
	_dst_city = dst
	_ctx_panel.visible = true
	_ctx_clear_btn.visible = true
	_attack_flow.visible = true
	_upgrade_btn.visible = false
	_ctx_title.text = "Envoyer des troupes"
	_source_label.text = "Source : %s (%d troupes)" % [src.node_name, src.garrison]
	_target_label.text = "Cible : %s — Défense %d" % [dst.node_name, dst.garrison]
	_slider.max_value = float(maxi(1, src.garrison))
	_slider.value = float(src.garrison)
	_update_travel()
	_refresh_info(dst)
	_position_context_panel()
	_tut_trigger("attack_bar")


func _refresh_info(c: CityNode) -> void:
	var own := "Joueur" if c.owner == CityNode.OWNER_PLAYER else ("Ennemi" if c.owner == CityNode.OWNER_ENEMY else "Neutre")
	_ctx_info.text = "[b]Propriétaire :[/b] %s\n[b]Garnison :[/b] %d / %d\n[b]Production :[/b] %.1f t/s\n[b]Défense ville :[/b] +%d%%" % [
		own, c.garrison, c.storage_cap(), c.production_per_sec(), int((c.defense_city_bonus() - 1.0) * 100.0)
	]
	_upgrade_btn.visible = c.owner == CityNode.OWNER_PLAYER
	if _upgrade_btn.visible:
		_upgrade_btn.text = "Améliorer la ville (-%d or)" % game.upgrade_cost(c.id)


func _update_travel() -> void:
	if game == null or _src_city == null or _dst_city == null:
		_travel_label.text = "Temps de trajet : -"
		return
	var t := game.travel_time_between(_src_city.id, _dst_city.id)
	_travel_label.text = "Temps de trajet : %.0f s" % t


func _current_source() -> CityNode:
	return _src_city


# ---------------------------------------------------------------- actions

func _on_upgrade_pressed() -> void:
	var city := _src_city if _src_city != null else _dst_city
	if city == null:
		return
	if game.upgrade_city(city.id):
		_refresh_info(city)
		_tut_trigger("upgrade")
	else:
		toast("Pas assez d'or")


func _on_preset(p: int) -> void:
	_slider.value = _slider.max_value * float(p) / 100.0


func _on_send_pressed() -> void:
	var percent := _slider.value / _slider.max_value
	# forward to main
	main_node.send_troops(percent)
	_tut_trigger("launch")


func _on_clear_pressed() -> void:
	main_node.clear_selection()


func clear_selection() -> void:
	_ctx_panel.visible = false


# ---------------------------------------------------------------- skill tree

func _build_skill_panel() -> void:
	_skill_panel = PanelContainer.new()
	_skill_panel.visible = false
	_skill_panel.set_anchors_preset(Control.PRESET_CENTER)
	_skill_panel.offset_left = -340
	_skill_panel.offset_right = 340
	_skill_panel.offset_top = -320
	_skill_panel.offset_bottom = 320
	add_child(_skill_panel)

	var vb := VBoxContainer.new()
	_skill_panel.add_child(vb)

	var head := HBoxContainer.new()
	vb.add_child(head)
	var title := _label("Arbre de compétences", 22)
	head.add_child(title)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	var close := _button("✕")
	close.pressed.connect(func(): _skill_panel.visible = false)
	head.add_child(close)

	var points := _label("", 16)
	_points_label = points
	vb.add_child(points)

	_skills_root = VBoxContainer.new()
	_skills_root.add_theme_constant_override("separation", 4)
	vb.add_child(_skills_root)

	refresh_skill_panel()


func refresh_skill_panel() -> void:
	if _skills_root == null or game == null:
		return
	for child in _skills_root.get_children():
		child.queue_free()
	_points_label.text = "Points de compétence : %d" % game.player.skill_points

	var branches := [
		[PlayerStats.BRANCH_OFFENSIVE, "⚔ Offensif"],
		[PlayerStats.BRANCH_DEFENSIVE, "🛡 Défensif"],
		[PlayerStats.BRANCH_ECONOMY, "💰 Économie"],
		[PlayerStats.BRANCH_COMMAND, "🎖 Commandement"],
	]
	for branch in branches:
		var lab := _label(branch[1], 18, Color(1, 0.85, 0.4))
		_skills_root.add_child(lab)
		for key in PlayerStats.SKILLS:
			var s: Dictionary = PlayerStats.SKILLS[key]
			if s["branch"] != branch[0]:
				continue
			var row := HBoxContainer.new()
			_skills_root.add_child(row)
			var info := _label("%s  [%d/%d]" % [s["name"], game.player.skill_level(key), s["max"]], 14)
			info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(info)
			var desc := _label(s["desc"], 12, Color(0.8, 0.8, 0.8))
			desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(desc)
			var plus := _button("+")
			plus.disabled = not game.player.can_upgrade_skill(key)
			plus.pressed.connect(_on_upgrade_skill.bind(key))
			row.add_child(plus)


func _on_upgrade_skill(key: String) -> void:
	if game.player.upgrade_skill(key):
		refresh_skill_panel()
		toast("Compétence améliorée !")
		refresh_top_bar()


func _open_skill_panel() -> void:
	_maybe_context_hint("skills", "Compétences : dépensez vos points pour renforcer votre Seigneur (attaque, défense, production…).")
	_forge_panel.visible = false
	_log_panel.visible = false
	_league_panel.visible = false
	_top_panel.visible = false
	_realm_panel.visible = false
	_alliance_panel.visible = false
	_tournament_panel.visible = false
	_guide_panel.visible = false
	refresh_skill_panel()
	_skill_panel.visible = true


# ---------------------------------------------------------------- forge

func _build_forge_panel() -> void:
	_forge_panel = PanelContainer.new()
	_forge_panel.visible = false
	_forge_panel.set_anchors_preset(Control.PRESET_CENTER)
	_forge_panel.offset_left = -360
	_forge_panel.offset_right = 360
	_forge_panel.offset_top = -300
	_forge_panel.offset_bottom = 300
	add_child(_forge_panel)

	var vb := VBoxContainer.new()
	_forge_panel.add_child(vb)

	var head := HBoxContainer.new()
	vb.add_child(head)
	var title := _label("Forge d'équipement", 22)
	head.add_child(title)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	var close := _button("✕")
	close.pressed.connect(func(): _forge_panel.visible = false)
	head.add_child(close)

	var forge_btn := _button("Forger un objet")
	forge_btn.pressed.connect(_on_forge_pressed)
	_forge_btn = forge_btn
	vb.add_child(forge_btn)

	var stats := _label("", 15)
	_forge_stats = stats
	vb.add_child(stats)

	var items := ScrollContainer.new()
	items.custom_minimum_size = Vector2(700, 240)
	items.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(items)
	_forge_items = VBoxContainer.new()
	_forge_items.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	items.add_child(_forge_items)

	refresh_forge_panel()


func refresh_forge_panel() -> void:
	if _forge_panel == null or game == null:
		return
	var cost := game.player.forge_cost()
	_forge_btn.text = "Forger un objet (-%d or, -%d gems)" % [cost, 10 + game.player.inventory.size() * 5]
	_forge_stats.text = game.player.total_stat_text()
	for child in _forge_items.get_children():
		child.queue_free()
	if game.player.inventory.is_empty():
		_forge_items.add_child(_label("Aucun équipement. Forgez votre premier objet !", 13, Color(0.8, 0.8, 0.8)))
	for item in game.player.inventory:
		var txt := _item_line(item)
		_forge_items.add_child(_label(txt, 13, _rarity_color(item["rarity"])))


func _item_line(item: Dictionary) -> String:
	var parts := []
	for k in ["attack", "defense", "production", "speed"]:
		if item.has(k):
			var names := {"attack": "Att", "defense": "Déf", "production": "Prod", "speed": "Vit"}
			parts.append("%s +%d%%" % [names[k], int(item[k] * 100.0)])
	var eq := ""
	var cur = game.player.equipped.get(item["slot"])
	if cur != null and cur == item:
		eq = "  [ÉQUIPÉ]"
	return "%s — %s%s" % [item["name"], "  ".join(parts), eq]


func _rarity_color(r: int) -> Color:
	match r:
		PlayerStats.RARITY_RARE:
			return Color(0.4, 0.7, 1.0)
		PlayerStats.RARITY_EPIC:
			return Color(0.8, 0.5, 1.0)
		PlayerStats.RARITY_LEGENDARY:
			return Color(1.0, 0.75, 0.2)
	return Color(0.9, 0.9, 0.9)


func _on_forge_pressed() -> void:
	var item := game.player.forge(game.player.gold, game.player.gems)
	if item.is_empty():
		toast("Pas assez de ressources pour forger")
	else:
		toast("%s forgé !" % item["name"])
	refresh_forge_panel()


func _open_forge_panel() -> void:
	_maybe_context_hint("forge", "Forge : dépensez vos gemmes 💎 pour forger des équipements qui renforcent votre Seigneur.")
	_skill_panel.visible = false
	_log_panel.visible = false
	_league_panel.visible = false
	_top_panel.visible = false
	_realm_panel.visible = false
	_alliance_panel.visible = false
	_tournament_panel.visible = false
	_guide_panel.visible = false
	refresh_forge_panel()
	_forge_panel.visible = true
	_tut_trigger("forge")


# ---------------------------------------------------------------- log

func _build_log_panel() -> void:
	_log_panel = PanelContainer.new()
	_log_panel.visible = false
	_log_panel.set_anchors_preset(Control.PRESET_CENTER)
	_log_panel.offset_left = -300
	_log_panel.offset_right = 300
	_log_panel.offset_top = -300
	_log_panel.offset_bottom = 300
	add_child(_log_panel)

	var vb := VBoxContainer.new()
	_log_panel.add_child(vb)

	var head := HBoxContainer.new()
	vb.add_child(head)
	var title := _label("Journal de combat", 22)
	head.add_child(title)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	var close := _button("✕")
	close.pressed.connect(func(): _log_panel.visible = false)
	head.add_child(close)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(560, 500)
	vb.add_child(scroll)
	_log_list = VBoxContainer.new()
	_log_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_log_list)


func _on_log_message(text: String) -> void:
	var l := _label(text, 13)
	_log_list.add_child(l)
	# keep newest at top
	_log_list.move_child(l, 0)
	# Trim to 60 entries. Use free() (immediate) — queue_free() would NOT shrink
	# get_child_count() within this loop and would hang forever at >60 entries.
	while _log_list.get_child_count() > 60:
		_log_list.get_child(_log_list.get_child_count() - 1).free()


func _open_log_panel() -> void:
	_skill_panel.visible = false
	_forge_panel.visible = false
	_league_panel.visible = false
	_top_panel.visible = false
	_realm_panel.visible = false
	_alliance_panel.visible = false
	_tournament_panel.visible = false
	_guide_panel.visible = false
	_log_panel.visible = true


# ---------------------------------------------------------------- league / season

func _build_league_panel() -> void:
	_league_panel = PanelContainer.new()
	_league_panel.visible = false
	_league_panel.set_anchors_preset(Control.PRESET_CENTER)
	_league_panel.offset_left = -320
	_league_panel.offset_right = 320
	_league_panel.offset_top = -280
	_league_panel.offset_bottom = 280
	add_child(_league_panel)

	var vb := VBoxContainer.new()
	_league_panel.add_child(vb)

	var head := HBoxContainer.new()
	vb.add_child(head)
	var title := _label("Ligue & saisons", 22)
	head.add_child(title)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	var close := _button("✕")
	close.pressed.connect(func(): _league_panel.visible = false)
	head.add_child(close)

	_league_info = RichTextLabel.new()
	_league_info.bbcode_enabled = true
	_league_info.fit_content = true
	_league_info.custom_minimum_size = Vector2(620, 440)
	vb.add_child(_league_info)


func refresh_league_panel() -> void:
	if _league_panel == null or game == null:
		return
	var rank: int = game.current_rank_index()
	var next_idx := mini(rank + 1, GameState.RANKS.size() - 1)
	var rank_lines := ""
	for i in range(GameState.RANKS.size()):
		var mark := "▶ " if i == rank else "   "
		var need: int = GameState.RANK_MIN_LEVELS[i]
		rank_lines += "%s[b]%s[/b] — %d niveaux de villes\n" % [mark, GameState.RANKS[i], need]
	var pos := "Maximum atteint" if rank >= GameState.RANKS.size() - 1 else \
		"%s (encore %d niveaux)" % [GameState.RANKS[next_idx], GameState.RANK_MIN_LEVELS[next_idx] - game.dominance_score()]
	var mm := int(game.season_remaining / 60.0)
	var ss := int(game.season_remaining) % 60
	_league_info.text = (
		"[b]Saison %d[/b] — fin dans %d:%02d\n"
		+ "Rang actuel : [b]%s[/b]\n"
		+ "Meilleur rang : %s   |   Saisons dominées : %d\n"
		+ "Villes contrôlées : %d   (score %d)\n\n"
		+ "[b]Palmarès des rangs[/b]\n%s\n"
		+ "Prochain palier : %s\n\n"
		+ "À la fin de la saison, la carte repart de zéro mais votre niveau, "
		+ "vos compétences et votre équipement sont conservés."
	) % [game.season_number, mm, ss, GameState.RANKS[rank],
		GameState.RANKS[game.best_rank], game.seasons_won,
		game.player_cities().size(), game.dominance_score(),
		rank_lines, pos]


func _open_league_panel() -> void:
	_maybe_context_hint("league", "Ligue : votre rang selon les villes contrôlées à la fin de la saison.")
	_skill_panel.visible = false
	_forge_panel.visible = false
	_log_panel.visible = false
	_top_panel.visible = false
	_realm_panel.visible = false
	_alliance_panel.visible = false
	_tournament_panel.visible = false
	_guide_panel.visible = false
	refresh_league_panel()
	_league_panel.visible = true


# ---------------------------------------------------------------- top des seigneurs

func _build_top_panel() -> void:
	_top_panel = PanelContainer.new()
	_top_panel.visible = false
	_top_panel.set_anchors_preset(Control.PRESET_CENTER)
	_top_panel.offset_left = -320
	_top_panel.offset_right = 320
	_top_panel.offset_top = -280
	_top_panel.offset_bottom = 280
	add_child(_top_panel)

	var vb := VBoxContainer.new()
	_top_panel.add_child(vb)

	var head := HBoxContainer.new()
	vb.add_child(head)
	var title := _label("Top des Seigneurs", 22)
	head.add_child(title)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	var close := _button("✕")
	close.pressed.connect(func(): _top_panel.visible = false)
	head.add_child(close)

	_top_info = RichTextLabel.new()
	_top_info.bbcode_enabled = true
	_top_info.fit_content = true
	_top_info.custom_minimum_size = Vector2(620, 440)
	vb.add_child(_top_info)


func refresh_top_panel() -> void:
	if _top_panel == null or game == null:
		return
	var seasons_played := maxi(1, game.season_number - 1)
	var hist := ""
	for entry: Dictionary in game.season_history.slice(0, 10):
		hist += "Saison %d : [b]%s[/b] (score %d · %d villes)\n" % [
			entry["season"], GameState.RANKS[entry["rank"]],
			entry["dominance"], entry["cities"],
		]
	if hist == "":
		hist = "Aucune saison terminée pour l'instant."
	_top_info.text = (
		"[b]%s[/b] — Seigneur de %d saisons\n\n"
		+ "Meilleur rang atteint : [b]%s[/b]\n"
		+ "Plus haut score de domination : %d\n"
		+ "Saisons dominées : %d\n"
		+ "Conquêtes totales : %d\n"
		+ "Gemmes gagnées au total : %d\n"
		+ "Tournoi des Seigneurs : %s\n\n"
		+ "[b]Historique des saisons[/b]\n%s\n"
		+ "Chaque saison repart de zéro, mais votre Seigneur progresse pour toujours. "
		+ "Visez le rang le plus haut possible !"
	) % [GameState.RANKS[game.best_rank], seasons_played,
		GameState.RANKS[game.best_rank], game.best_dominance,
		game.seasons_won, game.total_conquests, game.total_gems_earned,
		("🏆 Gagné" if game.tournament_won else "Non"), hist]


func _open_top_panel() -> void:
	_maybe_context_hint("top", "Top des Seigneurs : vos statistiques et l'historique de vos conquêtes.")
	_skill_panel.visible = false
	_forge_panel.visible = false
	_log_panel.visible = false
	_league_panel.visible = false
	_realm_panel.visible = false
	_alliance_panel.visible = false
	_tournament_panel.visible = false
	_guide_panel.visible = false
	refresh_top_panel()
	_top_panel.visible = true


# ---------------------------------------------------------------- royaumes

func _build_realm_panel() -> void:
	_realm_panel = PanelContainer.new()
	_realm_panel.visible = false
	_realm_panel.set_anchors_preset(Control.PRESET_CENTER)
	_realm_panel.offset_left = -340
	_realm_panel.offset_right = 340
	_realm_panel.offset_top = -300
	_realm_panel.offset_bottom = 300
	add_child(_realm_panel)

	var vb := VBoxContainer.new()
	_realm_panel.add_child(vb)

	var head := HBoxContainer.new()
	vb.add_child(head)
	var title := _label("Royaumes", 22)
	head.add_child(title)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	var close := _button("✕")
	close.pressed.connect(func(): _realm_panel.visible = false)
	head.add_child(close)

	_realm_info = RichTextLabel.new()
	_realm_info.bbcode_enabled = true
	_realm_info.fit_content = true
	_realm_info.custom_minimum_size = Vector2(660, 470)
	vb.add_child(_realm_info)


func refresh_realm_panel() -> void:
	if _realm_panel == null or game == null:
		return
	var ladder := ""
	for i in range(GameState.REALMS.size()):
		var realm_name: String = GameState.REALMS[i]
		var mark := "▶ " if i == game.realm else "   "
		if i == GameState.REALMS.size() - 1:
			ladder += "%s👑 [b]%s[/b] — le tournoi ultime\n" % [mark, realm_name]
		else:
			ladder += "%s[b]%s[/b]\n" % [mark, realm_name]
	_realm_info.text = (
		"Votre royaume actuel : [b]%s[/b]   (meilleur : %s)\n\n"
		+ "[b]L'échelle des Royaumes[/b]\n%s\n"
		+ "Règles :\n"
		+ "• Conquérez [b]toutes[/b] les villes avant la fin de la saison → vous êtes [b]promu[/b] "
		+ "au royaume supérieur, où les royaumes ennemis sont plus forts.\n"
		+ "• Si vous êtes vaincu (toutes vos villes perdues) → vous [b]retombez au début[/b] "
		+ "et recommencez l'ascension.\n"
		+ "• Au sommet, le [b]Royaume des Seigneurs[/b] ne garde que les meilleurs.\n\n"
		+ "En multijoueur, chaque royaume sera un serveur distinct : seuls les gagnants "
		+ "montent affronter d'autres gagnants."
	) % [GameState.REALMS[game.realm], GameState.REALMS[game.best_realm], ladder]


func _open_realm_panel() -> void:
	_maybe_context_hint("realm", "Royaumes : conquérez toutes les villes pour monter d'échelon ; échouez et vous retombez.")
	_skill_panel.visible = false
	_forge_panel.visible = false
	_log_panel.visible = false
	_league_panel.visible = false
	_top_panel.visible = false
	_alliance_panel.visible = false
	_tournament_panel.visible = false
	_guide_panel.visible = false
	refresh_realm_panel()
	_realm_panel.visible = true


# ---------------------------------------------------------------- alliances

func _build_alliance_panel() -> void:
	_alliance_panel = PanelContainer.new()
	_alliance_panel.visible = false
	_alliance_panel.set_anchors_preset(Control.PRESET_CENTER)
	_alliance_panel.offset_left = -340
	_alliance_panel.offset_right = 340
	_alliance_panel.offset_top = -280
	_alliance_panel.offset_bottom = 280
	add_child(_alliance_panel)

	var vb := VBoxContainer.new()
	_alliance_panel.add_child(vb)

	var head := HBoxContainer.new()
	vb.add_child(head)
	var title := _label("Alliances", 22)
	head.add_child(title)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	var close := _button("✕")
	close.pressed.connect(func(): _alliance_panel.visible = false)
	head.add_child(close)

	_alliance_info = RichTextLabel.new()
	_alliance_info.bbcode_enabled = true
	_alliance_info.fit_content = true
	_alliance_info.custom_minimum_size = Vector2(660, 420)
	vb.add_child(_alliance_info)

	_recruit_btn = _button("Recruter un Seigneur (%d or)" % GameState.ALLY_COST_GOLD)
	_recruit_btn.pressed.connect(_on_recruit_pressed)
	vb.add_child(_recruit_btn)


func refresh_alliance_panel() -> void:
	if _alliance_panel == null or game == null:
		return
	var list := ""
	if game.allies.is_empty():
		list = "Aucun allié pour l'instant. Recrutez un seigneur pour renforcer votre camp."
	else:
		for ally: Dictionary in game.allies:
			var home := game.ally_home_city(ally)
			var home_txt := "sans cité" if home == null else "%s (Lv %d)" % [home.node_name, home.level]
			list += "• [b]%s[/b] — %s\n" % [ally.get("name", "?"), home_txt]
	_alliance_info.text = (		"Seigneurs alliés : %d/%d\n\n[b]Vos alliés[/b]\n%s\n"
		+ "Les alliés contrôlent des cités, produisent des troupes et attaquent "
		+ "les royaumes ennemis à vos côtés.\n"
		+ "Recruter coûte %d or. Chaque allié ajoute une cité amie à votre domination."
	) % [game.allies.size(), GameState.MAX_ALLIES, list, GameState.ALLY_COST_GOLD]
	var can_recruit: bool = game.allies.size() < GameState.MAX_ALLIES and game.player.gold >= GameState.ALLY_COST_GOLD
	_recruit_btn.disabled = not can_recruit


func _open_alliance_panel() -> void:
	_maybe_context_hint("alliance", "Alliances : recrutez des seigneurs alliés (en or) ; ils combattent à vos côtés.")
	_skill_panel.visible = false
	_forge_panel.visible = false
	_log_panel.visible = false
	_league_panel.visible = false
	_top_panel.visible = false
	_realm_panel.visible = false
	_tournament_panel.visible = false
	_guide_panel.visible = false
	refresh_alliance_panel()
	_alliance_panel.visible = true


func _on_recruit_pressed() -> void:
	var ok: bool = game.recruit_ally()
	if ok:
		toast("Un seigneur rejoint votre alliance !")
	else:
		toast("Pas assez d'or pour recruter")
	refresh_alliance_panel()


# ---------------------------------------------------------------- tournoi

func _build_tournament_panel() -> void:
	_tournament_panel = PanelContainer.new()
	_tournament_panel.visible = false
	_tournament_panel.set_anchors_preset(Control.PRESET_CENTER)
	_tournament_panel.offset_left = -340
	_tournament_panel.offset_right = 340
	_tournament_panel.offset_top = -300
	_tournament_panel.offset_bottom = 300
	add_child(_tournament_panel)

	var vb := VBoxContainer.new()
	_tournament_panel.add_child(vb)

	var head := HBoxContainer.new()
	vb.add_child(head)
	var title := _label("Tournoi des Seigneurs", 22)
	head.add_child(title)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	var close := _button("✕")
	close.pressed.connect(func(): _tournament_panel.visible = false)
	head.add_child(close)

	_tournament_info = RichTextLabel.new()
	_tournament_info.bbcode_enabled = true
	_tournament_info.fit_content = true
	_tournament_info.custom_minimum_size = Vector2(660, 440)
	vb.add_child(_tournament_info)

	_challenge_btn = _button("Lancer le défi")
	_challenge_btn.pressed.connect(_on_challenge_pressed)
	vb.add_child(_challenge_btn)


func refresh_tournament_panel() -> void:
	if _tournament_panel == null or game == null:
		return
	if not game.tournament_available():
		_tournament_info.text = (
			"Atteignez le [b]Royaume des Seigneurs[/b] (le sommet de l'échelle) "
			+ "pour entrer dans le Tournoi.\n\n"
			+ "Conquérez toutes les villes jusqu'au dernier royaume pour défier "
			+ "les meilleurs champions et régner."
		)
		_challenge_btn.disabled = true
		return
	var champ_idx: int = mini(game.tournament_wins, GameState.TOURNAMENT_CHAMPIONS.size() - 1)
	var champ_name: String = GameState.TOURNAMENT_CHAMPIONS[champ_idx]
	var force: int = game.total_player_force()
	var def: int = game.champion_defense(champ_idx)
	var progress := ""
	for i in range(GameState.TOURNAMENT_CHAMPIONS.size()):
		var done := i < game.tournament_wins
		var mark := "✔ " if done else ("▶ " if i == game.tournament_wins else "  ")
		var nm: String = GameState.TOURNAMENT_CHAMPIONS[i]
		progress += "%s[b]%s[/b]\n" % [mark, nm]
	var status := ""
	if game.tournament_won:
		status = "🏆 [b]VOUS RÉGNEZ SUR LE ROYAUME DES SEIGNEURS ![/b]"
	elif game.tournament_wins >= GameState.TOURNAMENT_CHAMPIONS.size():
		status = "🏆 Tournoi remporté !"
	else:
		status = "Champion actuel : [b]%s[/b]  (défi %d/%d)\nForce de votre armée : %d  |  Défense requise : %d" % [
			champ_name, game.tournament_wins + 1, GameState.TOURNAMENT_CHAMPIONS.size(), force, def]
	_tournament_info.text = (
		"[b]Le Tournoi du Seigneur des Royaumes[/b]\n\n"
		+ "Vous êtes au sommet de l'échelle ! Vainquez les %d champions pour régner.\n\n"
		+ "[b]Champions[/b]\n%s\n%s\n\n"
		+ "Perdre un duel vous fait retomber d'un royaume : il faudra remonter et retenter."
	) % [GameState.TOURNAMENT_CHAMPIONS.size(), progress, status]
	_challenge_btn.disabled = game.tournament_won


func _open_tournament_panel() -> void:
	_maybe_context_hint("tournament", "Tournoi : au sommet des Royaumes, battez les champions pour régner.")
	_skill_panel.visible = false
	_forge_panel.visible = false
	_log_panel.visible = false
	_league_panel.visible = false
	_top_panel.visible = false
	_realm_panel.visible = false
	_alliance_panel.visible = false
	_guide_panel.visible = false
	refresh_tournament_panel()
	_tournament_panel.visible = true


func _on_challenge_pressed() -> void:
	var won: bool = game.challenge_champion()
	if won:
		if game.tournament_won:
			toast("🏆 Vous régnez sur le Royaume des Seigneurs !")
		else:
			toast("Champion vaincu ! +%d gemmes" % GameState.TOURNAMENT_WIN_GEMS)
	else:
		toast("Défaite… vous retombez d'un royaume")
	refresh_tournament_panel()


# ---------------------------------------------------------------- guide / tutoriel

func _build_guide_panel() -> void:
	# Reference guide (reopenable with "?"): a readable centered modal.
	_guide_panel = PanelContainer.new()
	_guide_panel.visible = false
	_guide_panel.set_anchors_preset(Control.PRESET_CENTER)
	_guide_panel.offset_left = -370
	_guide_panel.offset_right = 370
	_guide_panel.offset_top = -250
	_guide_panel.offset_bottom = 250
	add_child(_guide_panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	_guide_panel.add_child(vb)
	var head := HBoxContainer.new()
	vb.add_child(head)
	_guide_title = _label("Guide", 22)
	head.add_child(_guide_title)
	var hsp := Control.new()
	hsp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(hsp)
	var close := _button("✕")
	close.pressed.connect(_close_guide)
	head.add_child(close)
	_guide_body = RichTextLabel.new()
	_guide_body.bbcode_enabled = true
	_guide_body.fit_content = true
	_guide_body.custom_minimum_size = Vector2(720, 330)
	vb.add_child(_guide_body)
	_guide_progress = _label("", 14, Color(0.7, 0.8, 0.9))
	_guide_progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_guide_progress)
	var nav := HBoxContainer.new()
	vb.add_child(nav)
	var prev := _button("◀ Précédent")
	prev.pressed.connect(_guide_prev)
	nav.add_child(prev)
	var nsp := Control.new()
	nsp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nav.add_child(nsp)
	var next := _button("Suivant ▶")
	next.pressed.connect(_guide_next)
	nav.add_child(next)
	_guide_prev_btn = prev
	_guide_next_btn = next

	# --- Non-intrusive tutorial overlay: floating hand + small bubble ---
	_tut_bubble = PanelContainer.new()
	_tut_bubble.visible = false
	add_child(_tut_bubble)
	var bvb := VBoxContainer.new()
	bvb.add_theme_constant_override("separation", 6)
	_tut_bubble.add_child(bvb)
	var bhead := HBoxContainer.new()
	bvb.add_child(bhead)
	_tut_progress = _label("1/8", 12, Color(0.75, 0.85, 0.95))
	bhead.add_child(_tut_progress)
	var bhsp := Control.new()
	bhsp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bhead.add_child(bhsp)
	_tut_skip = _button("✕")
	_tut_skip.custom_minimum_size = Vector2(0, 26)
	_tut_skip.pressed.connect(_close_guide)
	bhead.add_child(_tut_skip)
	_tut_bubble_label = _label("", 14)
	_tut_bubble_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tut_bubble_label.custom_minimum_size = Vector2(280, 0)
	bvb.add_child(_tut_bubble_label)
	_tut_action_btn = _button("Commencer ▶")
	_tut_action_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_tut_action_btn.pressed.connect(_guide_next)
	bvb.add_child(_tut_action_btn)

	_tut_hand = _label("👇", 42, Color(1.0, 0.85, 0.2))
	_tut_hand.visible = false
	add_child(_tut_hand)


func _guide_steps() -> Array:
	return [
		{"t": "Bienvenue, Seigneur !", "b": "Bienvenue dans Empire of Lords. Votre objectif : [b]dominer la carte[/b], [b]monter dans les Royaumes[/b] et finalement [b]régner[/b] au Tournoi du Seigneur des Royaumes. Ce guide vous explique tout."},
		{"t": "Les cités", "b": "La carte est faite de cités. Les [color=#4aa8ff]bleues[/color] sont [b]à vous[/b], les [color=#ff6a5a]rouges[/color] aux [b]ennemis[/b], les [color=#aaaaaa]grises[/color] sont [b]neutres[/b] (à conquérir) et les [color=#3fd6a8]turquoise[/color] appartiennent à vos [b]alliés[/b]. Cliquez une cité pour voir ses infos."},
		{"t": "La production de troupes", "b": "Chaque cité [b]produit des troupes[/b] en continu (sa garnison augmente avec le temps). Plus une cité est de [b]niveau élevé[/b], plus elle produit vite et plus elle stocke. Gardez toujours une réserve de défense !"},
		{"t": "Améliorer vos cités", "b": "Avec de l'[b]or[/b], améliorez vos cités (bouton Améliorer). Chaque niveau augmente la production, le stockage et la défense. C'est le cœur de votre croissance."},
		{"t": "Attaquer : choisir la source", "b": "Pour attaquer : [b]1) cliquez une de vos cités[/b] (elle devient la source). 2) Cliquez ensuite une cité cible. 3) Choisissez le [b]pourcentage de troupes[/b] à envoyer avec le curseur, puis [b]ENVOYER[/b]."},
		{"t": "Le combat (déterministe)", "b": "Pas de hasard ! Le résultat dépend de la formule : Force d'attaque = Troupes × (1 + BonusHéros). Force de défense = (Garnison × (1+BonusDéf)) × (1+Niveau×5%). Si vous êtes plus fort, vous [b]conquérez[/b] la cité. Sinon, vous perdez des troupes. Le temps de trajet compte : l'ennemi peut contre-attaquer entre-temps."},
		{"t": "L'or et les gemmes", "b": "L'[b]or[/b] (économies) sert à améliorer les cités et recruter des alliés. Les [b]gemmes 💎[/b] sont la monnaie précieuse, gagnées en fin de saison et au tournoi, utilisées à la Forge."},
		{"t": "Les compétences", "b": "Votre Seigneur gagne de l'XP en combattant et monte de niveau. Dans l'onglet [b]Compétences[/b], dépensez les points de compétence pour renforcer : attaque, défense, production, rapidité, pillage…"},
		{"t": "La Forge", "b": "Dans [b]Forge[/b], dépensez des gemmes pour forger des équipements (4 raretés). Ils s'équipent automatiquement et renforcent votre Seigneur d'une saison à l'autre."},
		{"t": "Les Alliances", "b": "Dans [b]Alliances[/b], recrutez des seigneurs alliés (coût en or). Ils contrôlent des cités, attaquent les ennemis à vos côtés et comptent pour votre domination."},
		{"t": "Ligue & Saisons", "b": "Chaque [b]saison[/b] dure un temps fixe. À la fin, la carte [b]repart de zéro[/b] mais votre [b]Seigneur progresse pour toujours[/b] (niveau, compétences, équipement, gemmes). Votre rang de Ligue dépend des villes contrôlées."},
		{"t": "Les Royaumes", "b": "L'échelle des [b]Royaumes[/b] : Cendres → Bronze → Argent → Or → Platine → Diamant → Seigneur des Royaumes. [b]Conquérez toutes les villes[/b] pour être [b]promu[/b] (les ennemis sont plus forts). [b]Échouez[/b] et vous [b]retombez[/b] pour recommencer l'ascension."},
		{"t": "Le Tournoi", "b": "Au sommet (Royaume des Seigneurs), le [b]Tournoi[/b] vous fait affronter 5 champions de plus en plus forts. Vainquez-les pour [b]régner[/b] ! Perdre un duel vous fait redescendre d'un royaume."},
		{"t": "Astuces de conquête", "b": "Conseils : commencez par conquérir les cités [b]neutres[/b] proches et faibles. Ne videz jamais une cité (gardez une garnison de défense). Améliorez votre capitale en priorité. Recrutez des alliés tôt. Rejouez des saisons pour accumuler gemmes et équipement, puis montez de Royaume."},
	]


func _tutorial_steps() -> Array:
	return [
		{"t": "Bienvenue", "b": "Bienvenue ! Pendant le tutoriel la paix est garantie : personne ne peut vous attaquer. Commençons.", "target": null, "btn": "Commencer ▶"},
		{"t": "Sélectionnez votre cité", "b": "Cliquez sur votre cité Fort-Sud (toit bleu) pour la sélectionner.", "target": 0, "wait": "select_self", "btn": ""},
		{"t": "La production", "b": "Bien ! Votre cité produit des troupes en continu (regardez la garnison monter).", "target": 0, "btn": "Suivant ▶"},
		{"t": "Améliorez votre cité", "b": "Cliquez sur « Améliorer la ville » : coûte de l'or, booste production, stockage et défense.", "target": "upgrade", "wait": "upgrade", "btn": ""},
		{"t": "L'or et les gemmes", "b": "Ouvrez la Forge (bouton en bas) pour découvrir où dépenser vos gemmes.", "target": "forge", "wait": "forge", "btn": ""},
		{"t": "Prêt à conquérir", "b": "Cliquez Fort-Sud (source) puis une cité neutre grise comme Pic-Aigu pour la viser.", "target": 0, "wait": "attack_bar", "btn": ""},
		{"t": "Envoyez vos troupes", "b": "Réglez le curseur (gardez une réserve) puis cliquez ENVOYER pour conquérir.", "target": "send", "wait": "launch", "btn": ""},
		{"t": "Vous êtes prêt !", "b": "La paix est levée : les ennemis peuvent attaquer. Bonne conquête, Seigneur !", "target": null, "btn": "Terminer ✕", "end_peace": true},
	]


func _current_guide_steps() -> Array:
	return _tutorial_steps() if _guide_mode == "tut" else _guide_steps()


func _hide_all_panels() -> void:
	_skill_panel.visible = false
	_forge_panel.visible = false
	_log_panel.visible = false
	_league_panel.visible = false
	_top_panel.visible = false
	_realm_panel.visible = false
	_alliance_panel.visible = false
	_tournament_panel.visible = false


func _hide_tut_overlay() -> void:
	if _tut_hand != null:
		_tut_hand.visible = false
	if _tut_bubble != null:
		_tut_bubble.visible = false


func _open_guide_panel() -> void:
	_hide_all_panels()
	_guide_mode = "ref"
	_guide_page = 0
	_hide_tut_overlay()
	_render_guide()
	_guide_panel.visible = true


func _start_tutorial() -> void:
	_hide_all_panels()
	_guide_mode = "tut"
	_guide_page = 0
	_guide_panel.visible = false
	_guide_prev_btn.visible = false
	_guide_next_btn.visible = false
	_render_tut()


func _render_guide() -> void:
	var steps := _guide_steps()
	_guide_page = clampi(_guide_page, 0, steps.size() - 1)
	var step: Dictionary = steps[_guide_page]
	_guide_title.text = step.get("t", "Guide")
	_guide_body.text = step.get("b", "")
	_guide_progress.text = "%d / %d" % [_guide_page + 1, steps.size()]
	_guide_prev_btn.visible = true
	_guide_prev_btn.disabled = _guide_page == 0
	_guide_next_btn.visible = true
	_guide_next_btn.text = "Terminer ✔" if _guide_page == steps.size() - 1 else "Suivant ▶"


func _tut_target_pos(step: Dictionary) -> Vector2:
	var target: Variant = step.get("target")
	if target is int and target >= 0 and main_node != null:
		return main_node.city_screen_pos(target)
	match str(target):
		"upgrade": return _btn_center(_upgrade_btn)
		"forge": return _btn_center(_forge_nav_btn)
		"send": return _btn_center(_send_btn)
	return Vector2(-1.0, -1.0)


func _btn_center(b: Control) -> Vector2:
	if b == null or not b.is_inside_tree() or not b.visible:
		return Vector2(-1.0, -1.0)
	return b.get_global_rect().get_center()


func _render_tut() -> void:
	if _guide_mode != "tut":
		return
	if _tut_bubble == null:
		return
	_hide_all_panels()  # keep the map free
	# Keep the tutorial overlay always on top so no panel can cover it.
	_tut_bubble.move_to_front()
	_tut_hand.move_to_front()
	var steps := _tutorial_steps()
	_guide_page = clampi(_guide_page, 0, steps.size() - 1)
	var step: Dictionary = steps[_guide_page]
	_tut_bubble_label.text = step.get("b", "")
	_tut_progress.text = "%d/%d" % [_guide_page + 1, steps.size()]
	var waiting: bool = str(step.get("wait", "")) != ""
	_tut_action_btn.visible = not waiting
	_tut_action_btn.text = str(step.get("btn", "Suivant ▶"))
	# Hand floats right above the click target.
	var hp := _tut_target_pos(step)
	if hp.x > 0.0:
		_tut_hand.visible = true
		_tut_hand.position = Vector2(hp.x - _tut_hand.size.x / 2.0, hp.y - 50.0)
	else:
		_tut_hand.visible = false
	# Small bubble just above the hand, clamped so it never hides the map.
	var bsz := _tut_bubble.get_combined_minimum_size()
	var bpos := Vector2(hp.x - bsz.x / 2.0, hp.y - 50.0 - bsz.y - 14.0)
	if hp.x <= 0.0:
		bpos = Vector2(60, 110)
	bpos.x = clampf(bpos.x, 8.0, 1280.0 - bsz.x - 8.0)
	bpos.y = clampf(bpos.y, 74.0, 720.0 - bsz.y - 8.0)
	_tut_bubble.position = bpos
	_tut_bubble.visible = true


func _enter_guide_step() -> void:
	if _guide_mode != "tut":
		return
	var steps := _tutorial_steps()
	var step: Dictionary = steps[_guide_page]
	if step.get("end_peace", false) and game != null:
		game.end_peace()
	# Start the attack step fresh (clear any lingering source selection) so the
	# player genuinely picks a source city, then a target.
	if str(step.get("wait", "")) == "attack_bar" and main_node != null:
		main_node.clear_selection()


func _guide_next() -> void:
	var steps := _current_guide_steps()
	if _guide_page >= steps.size() - 1:
		_finish_guide()
	else:
		_guide_page += 1
		_enter_guide_step()
		if _guide_mode == "tut":
			_render_tut()
		else:
			_render_guide()


func _guide_prev() -> void:
	if _guide_page > 0:
		_guide_page -= 1
		if _guide_mode == "tut":
			_render_tut()
		else:
			_render_guide()


func _tut_trigger(kind: String) -> void:
	if _guide_mode != "tut":
		return
	var steps := _tutorial_steps()
	if _guide_page >= steps.size():
		return
	var step: Dictionary = steps[_guide_page]
	if str(step.get("wait", "")) == kind:
		_guide_next()


func _finish_guide() -> void:
	_hide_tut_overlay()
	_guide_panel.visible = false
	if _guide_mode == "tut" and game != null and game.peace:
		game.end_peace()
	_guide_mode = "ref"


func _close_guide() -> void:
	_hide_tut_overlay()
	_guide_panel.visible = false
	# Closing the tutorial during the peace phase lifts it (player chose to play).
	if _guide_mode == "tut" and game != null and game.peace:
		game.end_peace()
	_guide_mode = "ref"


# One-time contextual hints when the player discovers a new feature (non-blocking).
func _maybe_context_hint(key: String, text: String) -> void:
	if _guide_mode == "tut":
		return  # let the guided walkthrough finish first
	if _context_hints.has(key):
		return
	_context_hints[key] = true
	toast(text)


func _on_season_ended(rank_index: int, gems_reward: int, realm: int, realm_result: String) -> void:
	if _season_overlay != null:
		_season_overlay.queue_free()
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	_season_overlay = overlay

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.04, 0.1, 0.85)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -300
	panel.offset_right = 300
	panel.offset_top = -190
	panel.offset_bottom = 190
	overlay.add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vb)

	var t1 := _label("Saison %d terminée !" % (game.season_number - 1), 30, Color(1, 0.9, 0.4))
	t1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t1)

	var promoted: bool = realm_result.begins_with("Promu") or realm_result.begins_with("Vous régnez")
	var t_realm := _label(realm_result, 20, Color(1, 0.75, 0.3) if promoted else Color(0.9, 0.6, 0.6))
	t_realm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t_realm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t_realm.custom_minimum_size = Vector2(520, 40)
	vb.add_child(t_realm)

	var t2 := _label("Royaume actuel : %s   ·   Rang : %s" % [GameState.REALMS[realm], GameState.RANKS[rank_index]], 18, Color.WHITE)
	t2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t2)

	var t3 := _label("Récompense : +%d gemmes" % gems_reward, 20, Color(0.6, 0.9, 1.0))
	t3.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t3)

	var t4 := _label("La carte repart de zéro — votre niveau, vos compétences et votre équipement sont conservés.", 14, Color(0.8, 0.85, 0.9))
	t4.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t4.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t4.custom_minimum_size = Vector2(540, 40)
	vb.add_child(t4)

	var cont := _button("Continuer (Saison %d)" % game.season_number)
	cont.pressed.connect(func():
		overlay.visible = false
		overlay.queue_free()
		_season_overlay = null
	)
	vb.add_child(cont)


# ---------------------------------------------------------------- toast & refresh

func _build_toast() -> void:
	_toast = Label.new()
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.offset_top = 70
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_font_size_override("font_size", 18)
	_toast.add_theme_color_override("font_color", Color(1, 0.95, 0.6))
	_toast.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_toast.add_theme_constant_override("outline_size", 4)
	_toast.visible = false
	add_child(_toast)
	_toast_timer = Timer.new()
	_toast_timer.one_shot = true
	_toast_timer.timeout.connect(func(): _toast.visible = false)
	add_child(_toast_timer)


func toast(text: String) -> void:
	_toast.text = text
	_toast.visible = true
	_toast_timer.start(2.2)


func on_zone_discovered(zone_index: int) -> void:
	# A new territory ruled by an evolved AI lord has been discovered.
	if game == null or zone_index >= game.zones.size():
		return
	var z: Dictionary = game.zones[zone_index]
	toast("🗺 Nouvelle zone : %s — conquérez-la pour découvrir la suivante !" % z["name"])
	var banner := Label.new()
	var msg: String = "🗺 DÉCOUVERTE : %s\nDirigée par %s (Niv %d) — restez sur vos gardes !" % [z["name"], z["lord"], z["lord_level"]]
	banner.text = msg
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.set_anchors_preset(Control.PRESET_CENTER)
	banner.offset_top = -150
	banner.offset_bottom = -90
	banner.add_theme_font_size_override("font_size", 26)
	banner.add_theme_color_override("font_color", Color(0.98, 0.85, 0.5))
	banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	banner.add_theme_constant_override("outline_size", 6)
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(banner)
	var tw := create_tween()
	tw.tween_interval(3.2)
	tw.tween_callback(banner.queue_free)
	refresh_top_bar()


func _on_game_over() -> void:
	var overlay := ColorRect.new()
	overlay.color = Color(0.1, 0.02, 0.02, 0.8)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	var title := Label.new()
	title.text = "VOUS AVEZ ÉTÉ VAINCU"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_preset(Control.PRESET_CENTER)
	title.offset_top = -40
	title.offset_bottom = 40
	title.add_theme_font_size_override("font_size", 46)
	title.add_theme_color_override("font_color", Color(1, 0.35, 0.3))
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	title.add_theme_constant_override("outline_size", 6)
	overlay.add_child(title)
	var sub := Label.new()
	sub.text = "Toutes vos villes sont tombées. Relancez la partie pour repartir."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.set_anchors_preset(Control.PRESET_CENTER)
	sub.offset_top = 40
	sub.offset_bottom = 80
	sub.add_theme_font_size_override("font_size", 20)
	sub.add_theme_color_override("font_color", Color(1, 0.9, 0.9))
	overlay.add_child(sub)
	var btn := Button.new()
	btn.text = "Rejouer"
	btn.set_anchors_preset(Control.PRESET_CENTER)
	btn.offset_left = -100
	btn.offset_right = 100
	btn.offset_top = 120
	btn.offset_bottom = 164
	btn.add_theme_font_size_override("font_size", 22)
	btn.pressed.connect(func() -> void: get_tree().reload_current_scene())
	overlay.add_child(btn)
	toast("Vous avez été vaincu !")


func refresh_top_bar() -> void:
	if game == null:
		return
	_lvl_label.text = "Niv %d" % game.player.level
	_xp_bar.max_value = float(game.player.xp_to_next())
	_xp_bar.value = float(game.player.xp)
	_gold_label.text = "Or %d" % game.player.gold
	_gems_label.text = "💎 %d" % game.player.gems
	var mm := int(game.season_remaining / 60.0)
	var ss := int(game.season_remaining) % 60
	_season_label.text = "S%d · %d:%02d · %s" % [game.season_number, mm, ss, GameState.RANKS[game.current_rank_index()]]
	# Evolving-world zone indicator: front zone being conquered + next lord.
	if game.zones.size() > 0:
		if game._zone_front < game.zones.size():
			var z: Dictionary = game.zones[game._zone_front]
			var total: int = game.zones.size()
			if z["lord"] == "":
				_zone_label.text = "🗺 Zone %d/%d · %s" % [game._zone_front + 1, total, z["name"]]
			else:
				_zone_label.text = "🗺 Zone %d/%d · vs %s" % [game._zone_front + 1, total, z["lord"]]
		else:
			_zone_label.text = "🗺 Seigneur des Royaumes — monde conquis"
	# Live quest objective: clear the current frontier zone to be promoted.
	if game.zones.size() > 0 and game._zone_front < game.zones.size():
		var zq: Dictionary = game.zones[game._zone_front]
		if zq["lord"] == "":
			_quest_label.text = "Quête : conquérir la zone « %s »" % zq["name"]
		else:
			_quest_label.text = "Quête : vaincre %s (%s)" % [zq["lord"], zq["name"]]
	# update upgrade button cost if visible
	if _upgrade_btn.visible and _src_city != null:
		_upgrade_btn.text = "Améliorer la ville (-%d or)" % game.upgrade_cost(_src_city.id)
	elif _upgrade_btn.visible and _dst_city != null:
		_upgrade_btn.text = "Améliorer la ville (-%d or)" % game.upgrade_cost(_dst_city.id)


# ---------------------------------------------------------------- helpers

func _label(text: String, font_size: int = 15, color: Color = Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 34)
	return b
