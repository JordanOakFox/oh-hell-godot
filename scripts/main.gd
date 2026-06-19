extends Control

const STARTING_NAMES := ["Player 1", "Player 2", "Player 3", "Player 4"]
const GAME_VERSION := "0.2.24"
const ANIMAL_IDS := ["bunny", "lizard", "lion", "tiger", "bear", "fox", "dog", "cat"]
const BOT_PERSONALITY_IDS := ["casual", "smart", "ruthless"]
const BOT_PERSONALITY_NAMES := {
	"casual": "Casual",
	"smart": "Smart",
	"ruthless": "Ruthless",
}
const ANIMAL_NAMES := {
	"bunny": "Bunny",
	"lizard": "Lizard",
	"lion": "Lion",
	"tiger": "Tiger",
	"bear": "Bear",
	"fox": "Fox",
	"dog": "Dog",
	"cat": "Cat",
}
const DEFAULT_SERVER_ADDRESS := "147.224.130.79:24567"
const PUBLIC_LOBBIES := [
	{"name": "Family Table", "address": "147.224.130.79:24567"},
	{"name": "Practice Table", "address": "147.224.130.79:24569"},
	{"name": "Big Table", "address": "147.224.130.79:24570"},
]
const DEFAULT_MAX_CARDS := 7
const DEFAULT_PLAYERS := 4
const DEFAULT_MAP_ID := "living_room"
const MAP_IDS := ["pirate", "space", "living_room", "jungle"]
const MAP_NAMES := {
	"pirate": "Pirate Ship",
	"space": "In Space",
	"living_room": "Living Room",
	"jungle": "Jungle",
}

const CardButtonScript := preload("res://scripts/card_button.gd")
const FeltBackgroundScript := preload("res://scripts/felt_background.gd")
const FireworksOverlayScript := preload("res://scripts/fireworks_overlay.gd")
const TableView3DScript := preload("res://scripts/table_view_3d.gd")
const MUSIC_PATHS := {
	"menu": "res://assets/music/menu_theme.ogg",
	"pirate": "res://assets/music/pirate_theme.ogg",
	"space": "res://assets/music/space_theme.ogg",
	"living_room": "res://assets/music/menu_theme.ogg",
	"jungle": "res://assets/music/jungle_theme.ogg",
}
const SUIT_SYMBOLS := {"S": "♠", "H": "♥", "D": "♦", "C": "♣"}
const SUIT_COLORS := {
	"S": Color("#171717"),
	"H": Color("#c8322b"),
	"D": Color("#e86f22"),
	"C": Color("#2367c7"),
}

var state: Dictionary = {}
var view_state: Dictionary = {}
var local_hand: Array = []
var my_seat := 0
var seat_peers: Array = []
var lobby_player_count := DEFAULT_PLAYERS
var lobby_max_cards := DEFAULT_MAX_CARDS
var lobby_map_index := MAP_IDS.find(DEFAULT_MAP_ID)
var server_port := Net.DEFAULT_PORT
var local_player_name := "Player"
var local_profile_id := ""
var recorded_game_ids := {}
var rng := RandomNumberGenerator.new()
var last_hand_signature := ""
var last_shuffle_round_key := ""
var bot_action_key := ""
var bot_turn_serial := 0
var hovered_3d_card_index := -1
var dedicated_server := false
var version_warning := ""
var advanced_network_visible := false
var settings_visible := false
var rules_visible := false
var round_history_visible := false
var scoreboard_visible := false
var last_sound_serial := 0
var lobby_avatar_send_timer := 0.0
var last_lobby_avatar_signature := ""
var end_game_confirm_until := 0

var title_label: Label
var version_label: Label
var status_label: Label
var table_label: Label
var player_hud_panel: PanelContainer
var left_stats_label: Label
var scoreboard_grid: GridContainer
var net_row: HBoxContainer
var advanced_net_row: HBoxContainer
var advanced_network_button: Button
var mute_button: Button
var sfx_mute_button: Button
var settings_button: Button
var rules_button: Button
var settings_panel: PanelContainer
var music_volume_slider: HSlider
var music_volume_label: Label
var sfx_volume_slider: HSlider
var sfx_volume_label: Label
var animal_picker: OptionButton
var bot_personality_picker: OptionButton
var rules_panel: PanelContainer
var history_button: Button
var end_game_button: Button
var turn_banner_panel: PanelContainer
var turn_banner_label: Label
var round_history_panel: PanelContainer
var round_history_label: Label
var settings_row: HBoxContainer
var map_row: HBoxContainer
var map_name_label: Label
var right_info_panel: VBoxContainer
var right_info_frame: PanelContainer
var right_info_label: Label
var trump_card_panel: PanelContainer
var trump_card_rank_label: Label
var trump_card_suit_label: Label
var trump_name_label: Label
var seat_info_label: Label
var trick_box: HBoxContainer
var hand_box: Control
var action_box: HBoxContainer
var address_input: LineEdit
var name_input: LineEdit
var online_lobby_picker: OptionButton
var player_count_spin: SpinBox
var max_cards_spin: SpinBox
var discovered_game_picker: OptionButton
var discovered_games: Array = []
var fireworks_overlay: Control
var table_view_3d: Control
var music_player: AudioStreamPlayer
var sfx_player: AudioStreamPlayer
var music_streams := {}
var sfx_streams := {}
var current_music_key := ""

func _ready() -> void:
	rng.randomize()
	local_player_name = Profile.display_name()
	local_profile_id = Profile.profile_id()
	_build_ui()
	Net.connection_changed.connect(_set_status)
	Net.discovered_games_changed.connect(_on_discovered_games_changed)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	_create_offline_lobby()
	_apply_command_line_mode()

func _process(delta: float) -> void:
	_update_lobby_avatar_sync(delta)
	_sync_end_game_button()
	if turn_banner_panel and turn_banner_panel.visible:
		var pulse := 0.72 + absf(sin(Time.get_ticks_msec() / 140.0)) * 0.28
		turn_banner_panel.modulate = Color(1, 1, 1, pulse)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if _handle_escape_pressed():
			return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_M:
		_toggle_mute_shortcut()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_I:
		_request_hidden_emote()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_TAB:
		_toggle_scoreboard()
		return
	if view_state.is_empty() or view_state.get("phase", "") != "playing":
		_set_3d_card_hover(-1)
		return
	if int(view_state.get("active_player", -1)) != my_seat:
		_set_3d_card_hover(-1)
		return
	if table_view_3d and table_view_3d.has_method("is_mouse_look_enabled") and table_view_3d.is_mouse_look_enabled():
		_set_3d_card_hover(-1)
		return
	if (event is InputEventMouseMotion or event is InputEventMouseButton) and _mouse_over_command_ui(event.position):
		_set_3d_card_hover(-1)
		return
	if (event is InputEventScreenTouch or event is InputEventScreenDrag) and _mouse_over_command_ui(event.position):
		_set_3d_card_hover(-1)
		return

	if event is InputEventMouseMotion:
		_set_3d_card_hover(_legal_3d_card_index_at(event.position))
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var index := _legal_3d_card_index_at(event.position)
		if index >= 0 and index < local_hand.size():
			_set_3d_card_hover(-1)
			_submit_card(local_hand[index])
	elif event is InputEventScreenDrag:
		_set_3d_card_hover(_legal_3d_card_index_at(event.position))
	elif event is InputEventScreenTouch:
		if event.pressed:
			_set_3d_card_hover(_legal_3d_card_index_at(event.position))
		else:
			var touch_index := _legal_3d_card_index_at(event.position)
			if touch_index >= 0 and touch_index < local_hand.size():
				_set_3d_card_hover(-1)
				_submit_card(local_hand[touch_index])

func _build_ui() -> void:
	table_view_3d = TableView3DScript.new()
	table_view_3d.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(table_view_3d)

	music_player = AudioStreamPlayer.new()
	music_player.bus = "Master"
	add_child(music_player)
	_apply_audio_settings()

	sfx_player = AudioStreamPlayer.new()
	sfx_player.bus = "Master"
	add_child(sfx_player)

	fireworks_overlay = FireworksOverlayScript.new()
	fireworks_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(fireworks_overlay)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 12)
	root.offset_left = 24
	root.offset_top = 18
	root.offset_right = -24
	root.offset_bottom = -18
	add_child(root)

	title_label = Label.new()
	title_label.text = "Oh Hell"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 42)
	title_label.add_theme_color_override("font_color", Color("#f0d28a"))
	root.add_child(title_label)

	version_label = Label.new()
	version_label.text = "v%s" % GAME_VERSION
	version_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	version_label.add_theme_font_size_override("font_size", 14)
	version_label.add_theme_color_override("font_color", Color("#f7f1e399"))
	root.add_child(version_label)

	net_row = HBoxContainer.new()
	net_row.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(net_row)

	name_input = LineEdit.new()
	name_input.text = local_player_name
	name_input.placeholder_text = "Your name"
	name_input.custom_minimum_size = Vector2(160, 0)
	name_input.text_changed.connect(_on_name_changed)
	net_row.add_child(name_input)

	online_lobby_picker = OptionButton.new()
	online_lobby_picker.custom_minimum_size = Vector2(210, 0)
	for lobby in PUBLIC_LOBBIES:
		var label := "%s" % str(lobby.get("name", "Public Lobby"))
		online_lobby_picker.add_item(label)
		online_lobby_picker.set_item_metadata(online_lobby_picker.item_count - 1, lobby)
	net_row.add_child(online_lobby_picker)

	var online_button := Button.new()
	online_button.text = "Play Online"
	online_button.custom_minimum_size = Vector2(132, 0)
	online_button.pressed.connect(_on_play_online_pressed)
	net_row.add_child(online_button)

	advanced_network_button = Button.new()
	advanced_network_button.text = "Advanced"
	advanced_network_button.pressed.connect(_on_advanced_network_pressed)
	net_row.add_child(advanced_network_button)

	mute_button = Button.new()
	mute_button.pressed.connect(_on_mute_pressed)
	net_row.add_child(mute_button)

	settings_button = Button.new()
	settings_button.text = "Settings"
	settings_button.pressed.connect(_on_settings_pressed)
	net_row.add_child(settings_button)

	rules_button = Button.new()
	rules_button.text = "Rules"
	rules_button.pressed.connect(_on_rules_pressed)
	net_row.add_child(rules_button)

	advanced_net_row = HBoxContainer.new()
	advanced_net_row.alignment = BoxContainer.ALIGNMENT_CENTER
	advanced_net_row.visible = false
	root.add_child(advanced_net_row)

	var host_button := Button.new()
	host_button.text = "Host Local"
	host_button.pressed.connect(_on_host_pressed)
	advanced_net_row.add_child(host_button)

	address_input = LineEdit.new()
	address_input.text = DEFAULT_SERVER_ADDRESS
	address_input.placeholder_text = "Server IP or IP:port"
	address_input.custom_minimum_size = Vector2(190, 0)
	advanced_net_row.add_child(address_input)

	var join_button := Button.new()
	join_button.text = "Join Address"
	join_button.pressed.connect(_on_join_pressed)
	advanced_net_row.add_child(join_button)

	discovered_game_picker = OptionButton.new()
	discovered_game_picker.custom_minimum_size = Vector2(220, 0)
	discovered_game_picker.add_item("Scanning for games...")
	advanced_net_row.add_child(discovered_game_picker)

	var join_found_button := Button.new()
	join_found_button.text = "Join LAN"
	join_found_button.pressed.connect(_on_join_found_pressed)
	advanced_net_row.add_child(join_found_button)

	settings_panel = PanelContainer.new()
	settings_panel.visible = false
	settings_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	settings_panel.add_theme_stylebox_override("panel", _panel_style(Color("#16251fe8"), Color("#f0d28a66"), 8, 1))
	root.add_child(settings_panel)

	var settings_margin := MarginContainer.new()
	settings_margin.add_theme_constant_override("margin_left", 14)
	settings_margin.add_theme_constant_override("margin_top", 10)
	settings_margin.add_theme_constant_override("margin_right", 14)
	settings_margin.add_theme_constant_override("margin_bottom", 10)
	settings_panel.add_child(settings_margin)

	var settings_box := VBoxContainer.new()
	settings_box.custom_minimum_size = Vector2(360, 0)
	settings_box.add_theme_constant_override("separation", 8)
	settings_margin.add_child(settings_box)

	var settings_title := Label.new()
	settings_title.text = "Settings"
	settings_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	settings_title.add_theme_font_size_override("font_size", 18)
	settings_title.add_theme_color_override("font_color", Color("#f0d28a"))
	settings_box.add_child(settings_title)

	music_volume_label = Label.new()
	music_volume_label.add_theme_color_override("font_color", Color("#f7f1e3"))
	settings_box.add_child(music_volume_label)

	music_volume_slider = HSlider.new()
	music_volume_slider.min_value = 0.0
	music_volume_slider.max_value = 100.0
	music_volume_slider.step = 1.0
	music_volume_slider.value = Profile.music_volume() * 100.0
	music_volume_slider.value_changed.connect(_on_music_volume_changed)
	settings_box.add_child(music_volume_slider)

	sfx_volume_label = Label.new()
	sfx_volume_label.add_theme_color_override("font_color", Color("#f7f1e3"))
	settings_box.add_child(sfx_volume_label)

	sfx_volume_slider = HSlider.new()
	sfx_volume_slider.min_value = 0.0
	sfx_volume_slider.max_value = 100.0
	sfx_volume_slider.step = 1.0
	sfx_volume_slider.value = Profile.sfx_volume() * 100.0
	sfx_volume_slider.value_changed.connect(_on_sfx_volume_changed)
	settings_box.add_child(sfx_volume_slider)

	sfx_mute_button = Button.new()
	sfx_mute_button.pressed.connect(_on_sfx_mute_pressed)
	settings_box.add_child(sfx_mute_button)

	var animal_label := Label.new()
	animal_label.text = "Animal"
	animal_label.add_theme_color_override("font_color", Color("#f7f1e3"))
	settings_box.add_child(animal_label)

	animal_picker = OptionButton.new()
	for animal_id in ANIMAL_IDS:
		animal_picker.add_item(str(ANIMAL_NAMES.get(animal_id, animal_id.capitalize())))
		animal_picker.set_item_metadata(animal_picker.item_count - 1, animal_id)
	animal_picker.selected = max(ANIMAL_IDS.find(Profile.animal()), 0)
	animal_picker.item_selected.connect(_on_animal_selected)
	settings_box.add_child(animal_picker)

	var bot_label := Label.new()
	bot_label.text = "Bot Style"
	bot_label.add_theme_color_override("font_color", Color("#f7f1e3"))
	settings_box.add_child(bot_label)

	bot_personality_picker = OptionButton.new()
	for bot_id in BOT_PERSONALITY_IDS:
		bot_personality_picker.add_item(str(BOT_PERSONALITY_NAMES.get(bot_id, bot_id.capitalize())))
		bot_personality_picker.set_item_metadata(bot_personality_picker.item_count - 1, bot_id)
	bot_personality_picker.selected = max(BOT_PERSONALITY_IDS.find(Profile.bot_personality()), 0)
	bot_personality_picker.item_selected.connect(_on_bot_personality_selected)
	settings_box.add_child(bot_personality_picker)

	_update_audio_labels()

	rules_panel = PanelContainer.new()
	rules_panel.visible = false
	rules_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	rules_panel.add_theme_stylebox_override("panel", _panel_style(Color("#16251ff0"), Color("#f0d28a66"), 8, 1))
	root.add_child(rules_panel)

	var rules_margin := MarginContainer.new()
	rules_margin.add_theme_constant_override("margin_left", 16)
	rules_margin.add_theme_constant_override("margin_top", 12)
	rules_margin.add_theme_constant_override("margin_right", 16)
	rules_margin.add_theme_constant_override("margin_bottom", 12)
	rules_panel.add_child(rules_margin)

	var rules_text := Label.new()
	rules_text.custom_minimum_size = Vector2(560, 0)
	rules_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rules_text.add_theme_font_size_override("font_size", 15)
	rules_text.add_theme_color_override("font_color", Color("#f7f1e3"))
	rules_text.text = "How to play\nBid how many tricks you think you will win this round. Bids are secret until everyone locks in.\n\nYou must follow the led suit if you can. If you cannot, you may play any card. Trump cards beat other suits, and higher cards win within the same suit.\n\nHit your bid exactly to score 10 plus your bid. Miss your bid and score 0 for that round."
	rules_margin.add_child(rules_text)

	round_history_panel = PanelContainer.new()
	round_history_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	round_history_panel.offset_left = 18
	round_history_panel.offset_top = 126
	round_history_panel.offset_right = 388
	round_history_panel.offset_bottom = 514
	round_history_panel.visible = false
	round_history_panel.add_theme_stylebox_override("panel", _panel_style(Color("#16251ff0"), Color("#f0d28a66"), 8, 1))
	add_child(round_history_panel)

	var round_history_margin := MarginContainer.new()
	round_history_margin.add_theme_constant_override("margin_left", 14)
	round_history_margin.add_theme_constant_override("margin_top", 12)
	round_history_margin.add_theme_constant_override("margin_right", 14)
	round_history_margin.add_theme_constant_override("margin_bottom", 12)
	round_history_panel.add_child(round_history_margin)

	round_history_label = Label.new()
	round_history_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	round_history_label.add_theme_font_size_override("font_size", 14)
	round_history_label.add_theme_color_override("font_color", Color("#f7f1e3"))
	round_history_margin.add_child(round_history_label)

	history_button = Button.new()
	history_button.set_anchors_preset(Control.PRESET_TOP_LEFT)
	history_button.offset_left = 18
	history_button.offset_top = 86
	history_button.offset_right = 132
	history_button.offset_bottom = 120
	history_button.text = "History"
	history_button.visible = false
	_style_command_button(history_button)
	history_button.pressed.connect(_toggle_round_history)
	add_child(history_button)

	end_game_button = Button.new()
	end_game_button.set_anchors_preset(Control.PRESET_TOP_LEFT)
	end_game_button.offset_left = 18
	end_game_button.offset_top = 128
	end_game_button.offset_right = 132
	end_game_button.offset_bottom = 162
	end_game_button.text = "End Game"
	end_game_button.visible = false
	_style_command_button(end_game_button)
	end_game_button.pressed.connect(_request_end_game)
	add_child(end_game_button)

	turn_banner_panel = PanelContainer.new()
	turn_banner_panel.anchor_left = 0.5
	turn_banner_panel.anchor_top = 0.0
	turn_banner_panel.anchor_right = 0.5
	turn_banner_panel.anchor_bottom = 0.0
	turn_banner_panel.offset_left = -190
	turn_banner_panel.offset_top = 78
	turn_banner_panel.offset_right = 190
	turn_banner_panel.offset_bottom = 122
	turn_banner_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	turn_banner_panel.add_theme_stylebox_override("panel", _panel_style(Color("#171f18f0"), Color("#ffe18fcc"), 8, 2))
	turn_banner_panel.visible = false
	add_child(turn_banner_panel)

	var turn_banner_margin := MarginContainer.new()
	turn_banner_margin.add_theme_constant_override("margin_left", 14)
	turn_banner_margin.add_theme_constant_override("margin_top", 7)
	turn_banner_margin.add_theme_constant_override("margin_right", 14)
	turn_banner_margin.add_theme_constant_override("margin_bottom", 7)
	turn_banner_panel.add_child(turn_banner_margin)

	turn_banner_label = Label.new()
	turn_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	turn_banner_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	turn_banner_label.add_theme_font_size_override("font_size", 21)
	turn_banner_label.add_theme_color_override("font_color", Color("#ffe18f"))
	turn_banner_label.add_theme_color_override("font_shadow_color", Color("#050807"))
	turn_banner_label.add_theme_constant_override("shadow_offset_x", 2)
	turn_banner_label.add_theme_constant_override("shadow_offset_y", 2)
	turn_banner_margin.add_child(turn_banner_label)

	settings_row = HBoxContainer.new()
	settings_row.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(settings_row)

	var players_label := Label.new()
	players_label.text = "Players"
	players_label.add_theme_color_override("font_color", Color("#f7f1e3"))
	settings_row.add_child(players_label)

	player_count_spin = SpinBox.new()
	player_count_spin.min_value = 2
	player_count_spin.max_value = 10
	player_count_spin.step = 1
	player_count_spin.value = lobby_player_count
	player_count_spin.custom_minimum_size = Vector2(72, 0)
	player_count_spin.value_changed.connect(_on_player_count_changed)
	settings_row.add_child(player_count_spin)

	var cards_label := Label.new()
	cards_label.text = "Max cards"
	cards_label.add_theme_color_override("font_color", Color("#f7f1e3"))
	settings_row.add_child(cards_label)

	max_cards_spin = SpinBox.new()
	max_cards_spin.min_value = 1
	max_cards_spin.max_value = GameRules.max_allowed_cards(lobby_player_count)
	max_cards_spin.step = 1
	max_cards_spin.value = lobby_max_cards
	max_cards_spin.custom_minimum_size = Vector2(72, 0)
	max_cards_spin.value_changed.connect(_on_max_cards_changed)
	settings_row.add_child(max_cards_spin)

	map_row = HBoxContainer.new()
	map_row.alignment = BoxContainer.ALIGNMENT_CENTER
	map_row.add_theme_constant_override("separation", 8)
	root.add_child(map_row)

	var map_left_button := Button.new()
	map_left_button.text = "<"
	map_left_button.pressed.connect(_on_previous_map_pressed)
	map_row.add_child(map_left_button)

	var map_title_label := Label.new()
	map_title_label.text = "Map"
	map_title_label.add_theme_color_override("font_color", Color("#f7f1e3"))
	map_row.add_child(map_title_label)

	map_name_label = Label.new()
	map_name_label.text = _selected_map_name()
	map_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	map_name_label.add_theme_font_size_override("font_size", 18)
	map_name_label.add_theme_color_override("font_color", Color("#f0d28a"))
	map_name_label.custom_minimum_size = Vector2(180, 0)
	map_row.add_child(map_name_label)

	var map_right_button := Button.new()
	map_right_button.text = ">"
	map_right_button.pressed.connect(_on_next_map_pressed)
	map_row.add_child(map_right_button)

	status_label = Label.new()
	status_label.text = Profile.stats_line()
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_color_override("font_color", Color("#f7f1e3"))
	root.add_child(status_label)

	var play_row := HBoxContainer.new()
	play_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	play_row.add_theme_constant_override("separation", 16)
	root.add_child(play_row)

	player_hud_panel = PanelContainer.new()
	player_hud_panel.anchor_left = 0.5
	player_hud_panel.anchor_top = 0.5
	player_hud_panel.anchor_right = 0.5
	player_hud_panel.anchor_bottom = 0.5
	player_hud_panel.offset_left = -260
	player_hud_panel.offset_top = -230
	player_hud_panel.offset_right = 260
	player_hud_panel.offset_bottom = 230
	player_hud_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	player_hud_panel.add_theme_stylebox_override("panel", _panel_style(Color("#0e151af7"), Color("#f0d28add"), 8, 2))
	player_hud_panel.visible = false
	add_child(player_hud_panel)

	var player_hud_margin := MarginContainer.new()
	player_hud_margin.add_theme_constant_override("margin_left", 24)
	player_hud_margin.add_theme_constant_override("margin_top", 20)
	player_hud_margin.add_theme_constant_override("margin_right", 24)
	player_hud_margin.add_theme_constant_override("margin_bottom", 18)
	player_hud_panel.add_child(player_hud_margin)

	var scoreboard_box := VBoxContainer.new()
	scoreboard_box.add_theme_constant_override("separation", 14)
	player_hud_margin.add_child(scoreboard_box)

	left_stats_label = Label.new()
	left_stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left_stats_label.add_theme_font_size_override("font_size", 16)
	left_stats_label.add_theme_color_override("font_color", Color("#f7f1e3"))
	left_stats_label.add_theme_color_override("font_shadow_color", Color("#050807"))
	left_stats_label.add_theme_constant_override("shadow_offset_x", 1)
	left_stats_label.add_theme_constant_override("shadow_offset_y", 1)
	left_stats_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scoreboard_box.add_child(left_stats_label)

	scoreboard_grid = GridContainer.new()
	scoreboard_grid.columns = 4
	scoreboard_grid.add_theme_constant_override("h_separation", 28)
	scoreboard_grid.add_theme_constant_override("v_separation", 8)
	scoreboard_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scoreboard_box.add_child(scoreboard_grid)

	var center_column := VBoxContainer.new()
	center_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center_column.add_theme_constant_override("separation", 10)
	play_row.add_child(center_column)

	table_label = Label.new()
	table_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	table_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	table_label.add_theme_font_size_override("font_size", 18)
	table_label.add_theme_color_override("font_color", Color("#f7f1e3"))
	table_label.add_theme_color_override("font_shadow_color", Color("#17110c"))
	table_label.add_theme_constant_override("shadow_offset_x", 2)
	table_label.add_theme_constant_override("shadow_offset_y", 2)
	table_label.clip_text = true
	table_label.custom_minimum_size = Vector2(0, 68)
	center_column.add_child(table_label)

	trick_box = HBoxContainer.new()
	trick_box.alignment = BoxContainer.ALIGNMENT_CENTER
	trick_box.add_theme_constant_override("separation", 18)
	trick_box.custom_minimum_size = Vector2(0, 96)
	trick_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center_column.add_child(trick_box)

	action_box = HBoxContainer.new()
	action_box.alignment = BoxContainer.ALIGNMENT_CENTER
	action_box.add_theme_constant_override("separation", 8)
	center_column.add_child(action_box)

	right_info_frame = PanelContainer.new()
	right_info_frame.custom_minimum_size = Vector2(230, 0)
	right_info_frame.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	right_info_frame.add_theme_stylebox_override("panel", _panel_style(Color("#16251fcc"), Color("#f0d28a55"), 8, 1))
	play_row.add_child(right_info_frame)

	var right_info_margin := MarginContainer.new()
	right_info_margin.add_theme_constant_override("margin_left", 14)
	right_info_margin.add_theme_constant_override("margin_top", 12)
	right_info_margin.add_theme_constant_override("margin_right", 14)
	right_info_margin.add_theme_constant_override("margin_bottom", 12)
	right_info_frame.add_child(right_info_margin)

	right_info_panel = VBoxContainer.new()
	right_info_panel.custom_minimum_size = Vector2(190, 0)
	right_info_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_info_panel.add_theme_constant_override("separation", 12)
	right_info_margin.add_child(right_info_panel)

	right_info_label = Label.new()
	right_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right_info_label.add_theme_font_size_override("font_size", 16)
	right_info_label.add_theme_color_override("font_color", Color("#f7f1e3"))
	right_info_panel.add_child(right_info_label)

	trump_card_panel = PanelContainer.new()
	trump_card_panel.custom_minimum_size = Vector2(118, 158)
	trump_card_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var trump_card_style := StyleBoxFlat.new()
	trump_card_style.bg_color = Color("#fffaf0")
	trump_card_style.border_color = Color("#17110c")
	trump_card_style.set_border_width_all(3)
	trump_card_style.set_corner_radius_all(7)
	trump_card_panel.add_theme_stylebox_override("panel", trump_card_style)
	right_info_panel.add_child(trump_card_panel)

	var trump_card_margin := MarginContainer.new()
	trump_card_margin.add_theme_constant_override("margin_left", 8)
	trump_card_margin.add_theme_constant_override("margin_top", 6)
	trump_card_margin.add_theme_constant_override("margin_right", 8)
	trump_card_margin.add_theme_constant_override("margin_bottom", 6)
	trump_card_panel.add_child(trump_card_margin)

	var trump_card_column := VBoxContainer.new()
	trump_card_column.alignment = BoxContainer.ALIGNMENT_CENTER
	trump_card_column.add_theme_constant_override("separation", 4)
	trump_card_margin.add_child(trump_card_column)

	trump_card_rank_label = Label.new()
	trump_card_rank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	trump_card_rank_label.add_theme_font_size_override("font_size", 24)
	trump_card_column.add_child(trump_card_rank_label)

	trump_card_suit_label = Label.new()
	trump_card_suit_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	trump_card_suit_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	trump_card_suit_label.add_theme_font_size_override("font_size", 58)
	trump_card_suit_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	trump_card_column.add_child(trump_card_suit_label)

	trump_name_label = Label.new()
	trump_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	trump_name_label.add_theme_font_size_override("font_size", 18)
	trump_name_label.add_theme_color_override("font_color", Color("#f7f1e3"))
	right_info_panel.add_child(trump_name_label)

	seat_info_label = Label.new()
	seat_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	seat_info_label.add_theme_font_size_override("font_size", 16)
	seat_info_label.add_theme_color_override("font_color", Color("#f7f1e3"))
	right_info_panel.add_child(seat_info_label)

	hand_box = Control.new()
	hand_box.custom_minimum_size = Vector2(0, 178)
	hand_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(hand_box)

func _panel_style(fill: Color, border: Color, radius: int, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.shadow_color = Color("#00000055")
	style.shadow_size = 8
	style.shadow_offset = Vector2(0, 3)
	return style

func _style_command_button(button: Button, accent := false) -> void:
	button.add_theme_font_size_override("font_size", 16)
	button.add_theme_color_override("font_color", Color("#fff8df"))
	button.add_theme_color_override("font_hover_color", Color("#ffffff"))
	button.add_theme_stylebox_override("normal", _panel_style(Color("#3b2b1ce6") if not accent else Color("#7a4d1fe8"), Color("#f0d28a88"), 5, 1))
	button.add_theme_stylebox_override("hover", _panel_style(Color("#514024ee") if not accent else Color("#9b672bee"), Color("#ffe18fcc"), 5, 1))
	button.add_theme_stylebox_override("pressed", _panel_style(Color("#24180fe8"), Color("#ffe18f"), 5, 1))
	button.add_theme_stylebox_override("disabled", _panel_style(Color("#24272099"), Color("#f0d28a33"), 5, 1))

func _on_host_pressed() -> void:
	_read_lobby_inputs()
	server_port = _command_line_int("--port", server_port, 1, 65535)
	var err := Net.host(server_port)
	if err != OK:
		_set_status("Host failed: %s" % error_string(err))
		return
	my_seat = 0
	seat_peers = _new_seat_peers(lobby_player_count)
	_create_lobby("Hosting. Waiting for players...")
	Net.start_advertising(_discovery_info())

func _on_play_online_pressed() -> void:
	address_input.text = _selected_public_lobby_address()
	_on_join_pressed()

func _selected_public_lobby_address() -> String:
	if online_lobby_picker:
		var index := online_lobby_picker.selected
		if index >= 0:
			var metadata = online_lobby_picker.get_item_metadata(index)
			if typeof(metadata) == TYPE_DICTIONARY:
				return str(metadata.get("address", DEFAULT_SERVER_ADDRESS))
	return DEFAULT_SERVER_ADDRESS

func _on_advanced_network_pressed() -> void:
	advanced_network_visible = not advanced_network_visible
	_sync_advanced_network_visibility()

func _on_settings_pressed() -> void:
	settings_visible = not settings_visible
	_sync_settings_visibility()

func _sync_settings_visibility() -> void:
	if settings_button:
		settings_button.text = "Hide Settings" if settings_visible else "Settings"
	if settings_panel:
		var active_game: bool = view_state.get("phase", "") in ["bidding", "playing", "trick_end", "round_end"]
		settings_panel.visible = settings_visible and not active_game

func _on_rules_pressed() -> void:
	rules_visible = not rules_visible
	_sync_rules_visibility()

func _sync_rules_visibility() -> void:
	if rules_button:
		rules_button.text = "Hide Rules" if rules_visible else "Rules"
	if rules_panel:
		var active_game: bool = view_state.get("phase", "") in ["bidding", "playing", "trick_end", "round_end"]
		rules_panel.visible = rules_visible and not active_game

func _on_mute_pressed() -> void:
	_toggle_mute_shortcut()

func _toggle_mute_shortcut() -> void:
	var muted := not (Profile.music_muted() and Profile.sfx_muted())
	Profile.set_music_muted(muted)
	Profile.set_sfx_muted(muted)
	_apply_audio_settings()
	if not muted:
		_play_sfx("click")

func _handle_escape_pressed() -> bool:
	var handled := false
	if table_view_3d and table_view_3d.has_method("is_mouse_look_enabled") and table_view_3d.is_mouse_look_enabled():
		if table_view_3d.has_method("release_mouse_look"):
			table_view_3d.release_mouse_look()
		handled = true
	if settings_visible:
		settings_visible = false
		handled = true
	if rules_visible:
		rules_visible = false
		handled = true
	if round_history_visible:
		round_history_visible = false
		handled = true
	if scoreboard_visible:
		scoreboard_visible = false
		handled = true
	if handled:
		_sync_settings_visibility()
		_sync_rules_visibility()
		_sync_round_history_visibility()
		_sync_scoreboard_visibility()
		_set_3d_card_hover(-1)
		_play_sfx("click")
	return handled

func _on_music_volume_changed(value: float) -> void:
	Profile.set_music_volume(value / 100.0)
	if value > 0.0 and Profile.music_muted():
		Profile.set_music_muted(false)
	_apply_audio_settings()

func _on_sfx_volume_changed(value: float) -> void:
	Profile.set_sfx_volume(value / 100.0)
	if value > 0.0 and Profile.sfx_muted():
		Profile.set_sfx_muted(false)
	_update_audio_labels()
	_play_sfx("click")

func _on_sfx_mute_pressed() -> void:
	var muted := not Profile.sfx_muted()
	Profile.set_sfx_muted(muted)
	_update_audio_labels()
	if not muted:
		_play_sfx("click")

func _on_animal_selected(index: int) -> void:
	if not animal_picker or index < 0:
		return
	Profile.set_animal(str(animal_picker.get_item_metadata(index)))
	_update_local_profile_on_table()
	_play_sfx("click")

func _on_bot_personality_selected(index: int) -> void:
	if not bot_personality_picker or index < 0:
		return
	Profile.set_bot_personality(str(bot_personality_picker.get_item_metadata(index)))
	if state.get("phase", "") == "lobby" and _can_edit_lobby_settings():
		_request_bot_personality(Profile.bot_personality())
	_play_sfx("click")

func _apply_audio_settings() -> void:
	if not music_player:
		return
	var volume := Profile.music_volume()
	music_player.volume_db = -80.0 if Profile.music_muted() or volume <= 0.0 else linear_to_db(volume)
	_update_audio_labels()

func _update_audio_labels() -> void:
	if mute_button:
		mute_button.text = "Unmute" if Profile.music_muted() and Profile.sfx_muted() else "Mute"
	if music_volume_label:
		music_volume_label.text = "Music Volume: %d%%" % roundi(Profile.music_volume() * 100.0)
	if sfx_volume_label:
		sfx_volume_label.text = "SFX Volume: %d%%" % roundi(Profile.sfx_volume() * 100.0)
	if sfx_mute_button:
		sfx_mute_button.text = "Unmute SFX" if Profile.sfx_muted() else "Mute SFX"

func _sync_advanced_network_visibility() -> void:
	if advanced_network_button:
		advanced_network_button.text = "Hide Advanced" if advanced_network_visible else "Advanced"
	if advanced_net_row:
		var active_game: bool = view_state.get("phase", "") in ["bidding", "playing", "trick_end", "round_end"]
		advanced_net_row.visible = advanced_network_visible and not active_game

func _start_dedicated_server() -> void:
	dedicated_server = true
	lobby_player_count = _command_line_int("--players", DEFAULT_PLAYERS, 2, 10)
	lobby_max_cards = _command_line_int("--cards", DEFAULT_MAX_CARDS, 1, GameRules.max_allowed_cards(lobby_player_count))
	server_port = _command_line_int("--port", Net.DEFAULT_PORT, 1, 65535)
	var map_arg := _command_line_value("--map")
	if not map_arg.is_empty():
		lobby_map_index = _map_index_for_id(map_arg)
	local_player_name = "Dedicated Server"
	var err := Net.host(server_port)
	if err != OK:
		push_error("Dedicated server failed: %s" % error_string(err))
		get_tree().quit(1)
		return
	my_seat = -1
	seat_peers = _new_seat_peers(lobby_player_count)
	_create_lobby("Dedicated server online. Players can join.")
	Net.start_advertising(_discovery_info())
	print("Oh Hell dedicated server listening on port %d" % server_port)

func _on_join_pressed() -> void:
	_read_local_profile_input()
	var address := address_input.text.strip_edges()
	if address.is_empty():
		address = DEFAULT_SERVER_ADDRESS
	var endpoint := _parse_join_endpoint(address, _command_line_int("--port", Net.DEFAULT_PORT, 1, 65535))
	var err := Net.join(endpoint["address"], endpoint["port"])
	if err != OK:
		_set_status("Could not start connection: %s" % error_string(err))
	else:
		Net.stop_discovery()
		_create_client_waiting_view()

func _apply_command_line_mode() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--server"):
		_start_dedicated_server()
	elif args.has("--host"):
		_on_host_pressed()
	elif args.has("--join"):
		var address_arg := _command_line_value("--address")
		if not address_arg.is_empty():
			address_input.text = address_arg
		_on_join_pressed()

func _command_line_value(name: String) -> String:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size()):
		var arg := str(args[i])
		if arg.begins_with("%s=" % name):
			return arg.split("=", true, 1)[1]
		if arg == name and i + 1 < args.size():
			return str(args[i + 1])
	return ""

func _command_line_int(name: String, fallback: int, minimum: int, maximum: int) -> int:
	var value := _command_line_value(name)
	if value.is_valid_int():
		return clampi(int(value), minimum, maximum)
	return fallback

func _parse_join_endpoint(text: String, fallback_port: int) -> Dictionary:
	var endpoint := text.strip_edges()
	var port := fallback_port
	var address := endpoint
	if endpoint.count(":") == 1:
		var parts := endpoint.split(":", false, 1)
		if parts.size() == 2 and str(parts[1]).is_valid_int():
			address = str(parts[0]).strip_edges()
			port = clampi(int(parts[1]), 1, 65535)
	if address.is_empty():
		address = "127.0.0.1"
	return {"address": address, "port": port}

func _create_offline_lobby() -> void:
	my_seat = 0
	seat_peers = _new_seat_peers(lobby_player_count)
	_create_lobby("Offline preview. Host a game or join a host.")
	state["menu_preview"] = true
	view_state["menu_preview"] = true
	_publish_state()
	Net.start_discovery()

func _create_client_waiting_view() -> void:
	view_state = {
		"phase": "connecting",
		"map_id": _selected_map_id(),
		"names": _default_names(lobby_player_count),
		"profiles": _default_profiles(lobby_player_count),
		"num_players": lobby_player_count,
		"sequence": [DEFAULT_MAX_CARDS],
		"round_index": 0,
		"dealer": lobby_player_count - 1,
		"scores": _filled_array(lobby_player_count, 0),
		"bids": _filled_array(lobby_player_count, null),
		"bid_submitted": _filled_array(lobby_player_count, false),
		"tricks_won": _filled_array(lobby_player_count, 0),
		"trump": "",
		"trump_card": {},
		"trick": [],
		"led_suit": null,
		"leader": 0,
		"active_player": -1,
		"connected": _filled_array(lobby_player_count, false),
		"bots": _filled_array(lobby_player_count, false),
		"lobby_avatars": _default_lobby_avatars(lobby_player_count),
		"bot_personality": Profile.bot_personality(),
		"ready": _filled_array(lobby_player_count, false),
		"play_again": _filled_array(lobby_player_count, false),
		"standings": [],
		"winners": [],
		"round_history": [],
		"sound_event": {},
		"emote_event": {},
		"message": "Connecting to host...",
	}
	local_hand = []
	_render()

func _create_lobby(message: String) -> void:
	var names := _default_names(lobby_player_count)
	var profiles := _default_profiles(lobby_player_count)
	names[0] = local_player_name
	profiles[0] = Profile.public_profile()
	state = {
		"phase": "lobby",
		"map_id": _selected_map_id(),
		"names": names,
		"profiles": profiles,
		"num_players": lobby_player_count,
		"max_cards": lobby_max_cards,
		"sequence": GameRules.down_up_sequence(lobby_max_cards),
		"round_index": 0,
		"dealer": lobby_player_count - 1,
		"scores": _filled_array(lobby_player_count, 0),
		"hands": _empty_hands(lobby_player_count),
		"bids": _filled_array(lobby_player_count, null),
		"bid_submitted": _filled_array(lobby_player_count, false),
		"tricks_won": _filled_array(lobby_player_count, 0),
		"trump": "",
		"trump_card": {},
		"trick": [],
		"led_suit": null,
		"leader": 0,
		"active_player": -1,
		"connected": _connected_seats(),
		"bots": _filled_array(lobby_player_count, false),
		"lobby_avatars": _default_lobby_avatars(lobby_player_count),
		"bot_personality": Profile.bot_personality(),
		"ready": _lobby_ready_seats(),
		"play_again": _filled_array(lobby_player_count, false),
		"standings": [],
		"winners": [],
		"round_history": [],
		"sound_event": {},
		"emote_event": {},
		"message": message,
	}
	_publish_state()
	if multiplayer.multiplayer_peer and multiplayer.is_server():
		Net.update_advertisement(_discovery_info())

func _start_match(names: Array, max_cards: int) -> void:
	if multiplayer.multiplayer_peer and not multiplayer.is_server():
		return
	var selected_map := str(state.get("map_id", _selected_map_id()))

	state = {
		"phase": "bidding",
		"map_id": selected_map,
		"names": names,
		"profiles": state["profiles"].duplicate(true),
		"num_players": names.size(),
		"max_cards": max_cards,
		"sequence": GameRules.down_up_sequence(max_cards),
		"round_index": 0,
		"dealer": names.size() - 1,
		"scores": [],
		"hands": [],
		"bids": [],
		"bid_submitted": [],
		"tricks_won": [],
		"trump": "",
		"trump_card": {},
		"trick": [],
		"led_suit": null,
		"leader": 0,
		"active_player": -1,
		"connected": _connected_seats(),
		"bots": state.get("bots", _filled_array(names.size(), false)).duplicate(true),
		"bot_personality": str(state.get("bot_personality", Profile.bot_personality())),
		"ready": _lobby_ready_seats(),
		"play_again": _filled_array(names.size(), false),
		"standings": [],
		"winners": [],
		"round_history": [],
		"sound_event": {},
		"emote_event": {},
		"message": "",
	}
	state["scores"].resize(names.size())
	state["scores"].fill(0)
	_begin_round()

func _begin_round() -> void:
	var round_size: int = state["sequence"][state["round_index"]]
	var deal := GameRules.deal_round(state["num_players"], round_size, rng)
	state["hands"] = deal["hands"]
	state["trump"] = deal["trump"]
	state["trump_card"] = deal["trump_card"]
	state["bids"] = []
	state["bids"].resize(state["num_players"])
	state["bids"].fill(null)
	state["bid_submitted"] = []
	state["bid_submitted"].resize(state["num_players"])
	state["bid_submitted"].fill(false)
	state["tricks_won"] = []
	state["tricks_won"].resize(state["num_players"])
	state["tricks_won"].fill(0)
	state["trick"] = []
	state["played_cards"] = []
	state["led_suit"] = null
	state["leader"] = (state["dealer"] + 1) % state["num_players"]
	state["active_player"] = -1
	state["phase"] = "bidding"
	state["message"] = "Choose your secret bid."
	_set_sound_event("deal")
	_advance_bot_turn_serial()
	_publish_state()
	_schedule_bot_action()

func _publish_state() -> void:
	if multiplayer.multiplayer_peer and multiplayer.is_server():
		for seat in range(state["num_players"]):
			if not state["connected"][seat] or _is_bot_seat(seat):
				continue
			var peer_id := _peer_for_seat(seat)
			_receive_private_state.rpc_id(peer_id, _public_state(), state["hands"][seat], seat)
	else:
		var hand := []
		if state.has("hands") and my_seat < state["hands"].size():
			hand = state["hands"][my_seat]
		_receive_private_state(_public_state(), hand, my_seat)

@rpc("authority", "call_local", "reliable")
func _receive_private_state(public_state: Dictionary, hand: Array, seat: int) -> void:
	view_state = public_state
	var server_version := str(public_state.get("server_version", GAME_VERSION))
	version_warning = ""
	if server_version != GAME_VERSION:
		version_warning = "Version warning: you have v%s, server has v%s." % [GAME_VERSION, server_version]
	if not multiplayer.multiplayer_peer or not multiplayer.is_server():
		state = public_state
	local_hand = hand
	my_seat = seat
	_handle_sound_event(public_state.get("sound_event", {}))
	_render()

func _update_lobby_avatar_sync(delta: float) -> void:
	if view_state.is_empty() or str(view_state.get("phase", "")) != "lobby":
		return
	if my_seat < 0:
		return
	if not table_view_3d or not table_view_3d.has_method("get_lobby_avatar_state"):
		return
	lobby_avatar_send_timer -= delta
	if lobby_avatar_send_timer > 0.0:
		return
	lobby_avatar_send_timer = 0.16
	var avatar_state: Dictionary = table_view_3d.get_lobby_avatar_state()
	var signature := "%.2f:%.2f:%.1f" % [
		float(avatar_state.get("x", 0.0)),
		float(avatar_state.get("z", 0.0)),
		float(avatar_state.get("yaw", 0.0)),
	]
	if signature == last_lobby_avatar_signature:
		return
	last_lobby_avatar_signature = signature
	if multiplayer.multiplayer_peer and not multiplayer.is_server():
		_server_update_lobby_avatar.rpc_id(1, avatar_state)
	else:
		_apply_lobby_avatar_update(my_seat, avatar_state)

@rpc("any_peer", "unreliable")
func _server_update_lobby_avatar(avatar_state: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	_apply_lobby_avatar_update(_seat_for_peer(multiplayer.get_remote_sender_id()), avatar_state)

func _apply_lobby_avatar_update(seat: int, avatar_state: Dictionary) -> void:
	if state.get("phase", "") != "lobby":
		return
	var player_count := int(state.get("num_players", 0))
	if seat < 0 or seat >= player_count:
		return
	if not state.has("lobby_avatars") or not (state["lobby_avatars"] is Array) or state["lobby_avatars"].size() != player_count:
		state["lobby_avatars"] = _default_lobby_avatars(player_count)
	state["lobby_avatars"][seat] = {
		"x": clampf(float(avatar_state.get("x", 0.0)), -5.75, 5.75),
		"z": clampf(float(avatar_state.get("z", 0.0)), -5.65, 4.6),
		"yaw": fposmod(float(avatar_state.get("yaw", 180.0)), 360.0),
	}
	_publish_state()

func _public_state() -> Dictionary:
	var public := state.duplicate(true)
	public["server_version"] = GAME_VERSION
	public.erase("hands")
	if public["phase"] == "bidding":
		var hidden_bids := []
		hidden_bids.resize(state["num_players"])
		hidden_bids.fill(null)
		public["bids"] = hidden_bids
		public["message"] = _bidding_message()
	return public

func _bidding_message() -> String:
	var count := 0
	for submitted in state["bid_submitted"]:
		if submitted:
			count += 1
	return "Secret bidding: %d / %d bids locked." % [count, state["num_players"]]

func _render() -> void:
	if view_state.is_empty():
		return
	lobby_map_index = _map_index_for_id(str(view_state.get("map_id", _selected_map_id())))
	lobby_player_count = int(view_state.get("num_players", lobby_player_count))
	lobby_max_cards = int(view_state.get("max_cards", lobby_max_cards))
	_sync_lobby_settings_controls()
	if map_name_label:
		map_name_label.text = _selected_map_name()
	var active_game: bool = view_state.get("phase", "") in ["bidding", "playing", "trick_end", "round_end"]
	var overlay_phase: bool = view_state.get("phase", "") in ["bidding", "playing", "trick_end", "round_end", "game_end"]
	if title_label:
		title_label.visible = view_state.get("phase", "") in ["connecting", "lobby", "game_end"]
	if version_label:
		version_label.visible = title_label and title_label.visible
	if net_row:
		net_row.visible = not active_game
	_sync_advanced_network_visibility()
	_sync_settings_visibility()
	_sync_rules_visibility()
	if settings_row:
		settings_row.visible = not active_game
	if map_row:
		map_row.visible = not active_game
	if status_label:
		status_label.visible = not active_game
	if table_view_3d:
		table_view_3d.set_table_state(view_state, my_seat)
		table_view_3d.set_player_hand(local_hand)
		if table_view_3d.has_method("set_emote_event"):
			table_view_3d.set_emote_event(view_state.get("emote_event", {}))
		_update_music()
	if history_button:
		history_button.visible = overlay_phase
		history_button.text = "Hide History" if round_history_visible else "History"
	if end_game_button:
		end_game_button.visible = _can_request_end_game()
		_sync_end_game_button()
	_sync_scoreboard_visibility()
	_sync_round_history_visibility()
	_sync_turn_banner()
	if fireworks_overlay:
		fireworks_overlay.set_celebrating(view_state.get("phase", "") == "game_end")
	if view_state["phase"] == "connecting":
		table_label.add_theme_font_size_override("font_size", 18)
		trick_box.visible = true
		hand_box.visible = true
		player_hud_panel.visible = false
		right_info_frame.visible = false
		round_history_visible = false
		scoreboard_visible = false
		_sync_scoreboard_visibility()
		_sync_round_history_visibility()
		_sync_turn_banner()
		left_stats_label.text = ""
		right_info_label.text = ""
		table_label.text = view_state["message"]
		_render_trick()
		_render_actions()
		_render_hand()
		return
	if view_state["phase"] == "lobby":
		trick_box.visible = false
		hand_box.visible = false
		player_hud_panel.visible = false
		right_info_frame.visible = false
		round_history_visible = false
		scoreboard_visible = false
		_sync_scoreboard_visibility()
		_sync_round_history_visibility()
		_sync_turn_banner()
		left_stats_label.text = ""
		right_info_label.text = ""
		_render_lobby()
		return
	if view_state["phase"] == "game_end":
		table_label.add_theme_font_size_override("font_size", 18)
		trick_box.visible = true
		hand_box.visible = true
		player_hud_panel.visible = false
		right_info_frame.visible = false
		_render_game_end()
		return

	trick_box.visible = true
	hand_box.visible = true
	_sync_scoreboard_visibility()
	right_info_frame.visible = true
	table_label.add_theme_font_size_override("font_size", 18)
	var round_size: int = view_state["sequence"][view_state["round_index"]]
	right_info_label.text = "ROUND %d / %d\nCards: %d\n\nTRUMP" % [
		view_state["round_index"] + 1,
		view_state["sequence"].size(),
		round_size,
	]
	seat_info_label.text = "Seat %d\n%s" % [
		my_seat + 1,
		view_state["names"][my_seat],
	]
	_render_trump_symbol()
	if player_hud_panel.visible:
		_render_scoreboard_panel()
	table_label.text = _game_prompt_text()

	_render_trick()
	_render_actions()
	_render_hand()

func _render_game_end() -> void:
	var winner_text := "Game Over"
	if view_state["winners"].size() == 1:
		winner_text = "Winner: %s" % view_state["winners"][0]
	elif view_state["winners"].size() > 1:
		winner_text = "Winners: %s" % ", ".join(view_state["winners"])

	var text := "%s\n\nFinal Leaderboard\n" % winner_text
	for row in view_state["standings"]:
		text += "%d. %s  |  %d pts  |  exact %d  |  missed %d  |  best +%d\n" % [
			int(row["place"]),
			row["name"],
			int(row["score"]),
			int(row.get("made", 0)),
			int(row.get("missed", 0)),
			int(row.get("best_round", 0)),
		]
	text += "\nPress Play Again when everyone wants another table.\n%s" % view_state["message"]
	left_stats_label.text = ""
	right_info_label.text = ""
	table_label.add_theme_font_size_override("font_size", 22)
	table_label.text = text
	_render_trick()
	_render_actions()
	_render_hand()

func _render_trump_symbol() -> void:
	var trump := str(view_state.get("trump", ""))
	var trump_card: Dictionary = view_state.get("trump_card", {})
	var rank_text := "?"
	if trump_card.has("rank"):
		rank_text = _rank_text(int(trump_card["rank"]))
	var suit_symbol: String = SUIT_SYMBOLS.get(trump, trump)
	var color: Color = SUIT_COLORS.get(trump, Color("#17110c"))
	trump_card_rank_label.text = "%s%s" % [rank_text, suit_symbol]
	trump_card_rank_label.add_theme_color_override("font_color", color)
	trump_card_suit_label.text = suit_symbol
	trump_card_suit_label.add_theme_color_override("font_color", color)
	var trump_name: String = GameRules.SUIT_NAMES.get(trump, trump)
	trump_name_label.text = "%s of %s" % [rank_text, trump_name] if trump_card.has("rank") else trump_name
	trump_name_label.add_theme_color_override("font_color", SUIT_COLORS.get(trump, Color("#f7f1e3")))
	trump_card_panel.tooltip_text = "Trump card: %s" % trump_name_label.text

func _rank_text(rank: int) -> String:
	return str(GameRules.RANK_NAMES.get(rank, rank))

func _discovery_info() -> Dictionary:
	var connected_count := _connected_count()
	if state.is_empty() or state.get("phase", "") != "lobby":
		connected_count = 0
	return {
		"name": "%s's table" % local_player_name,
		"players": connected_count,
		"max_players": lobby_player_count,
		"max_cards": lobby_max_cards,
		"port": server_port,
		"map_id": _selected_map_id(),
		"map_name": _selected_map_name(),
		"phase": state.get("phase", "lobby"),
	}

func _render_lobby() -> void:
	left_stats_label.text = ""
	right_info_label.text = ""
	table_label.add_theme_font_size_override("font_size", 16)
	var connected_count := _view_connected_count()
	var ready_count := 0
	for seat in range(view_state["num_players"]):
		var is_bot := view_state.has("bots") and bool(view_state["bots"][seat])
		if is_bot or (view_state["connected"][seat] and view_state["ready"][seat]):
			ready_count += 1
	var text := "Multiplayer Lobby\n\n"
	text += "Table Host: %s\n" % _lobby_host_name()
	text += "Table: %d players  |  %d max cards  |  %s\n" % [
		view_state["num_players"],
		view_state["max_cards"],
		MAP_NAMES.get(str(view_state.get("map_id", _selected_map_id())), _selected_map_name()),
	]
	text += "Bots: %s  |  Ready: %d / %d  |  Connected: %d / %d\n" % [
		str(BOT_PERSONALITY_NAMES.get(str(view_state.get("bot_personality", "smart")), "Smart")),
		ready_count,
		view_state["num_players"],
		connected_count,
		view_state["num_players"],
	]
	text += "You: Seat %d, %s\n" % [my_seat + 1, view_state["names"][my_seat]]
	if multiplayer.multiplayer_peer and multiplayer.is_server():
		var addresses := Net.local_join_addresses(server_port)
		if addresses.is_empty():
			text += "Local join: network IP not found\n"
		else:
			text += "Local join: %s\n" % ", ".join(addresses)
	text += "\nSeats\n"
	for i in range(view_state["num_players"]):
		var status := "waiting"
		if view_state.has("bots") and view_state["bots"][i]:
			status = "bot"
		elif view_state["connected"][i]:
			status = "ready" if view_state["ready"][i] else "not ready"
		var host_badge := " host" if i == _table_host_seat_from_view() else ""
		var you_badge := " you" if i == my_seat else ""
		text += "%2d. %-18s %s%s%s\n" % [i + 1, str(view_state["names"][i]), status, host_badge, you_badge]
	if not version_warning.is_empty():
		text += "\n%s\n" % version_warning
	text += "\n%s" % _lobby_help_text()
	if not str(view_state["message"]).is_empty():
		text += "\n\n%s" % view_state["message"]
	table_label.text = text
	_render_trick()
	_render_actions()
	_render_hand()

func _lobby_help_text() -> String:
	if _view_lobby_can_start():
		return "Everyone is ready. Start Game when the table is set.\nControls: WASD move  |  Right-drag look  |  Esc closes panels."
	if view_state["connected"][my_seat] and not view_state["ready"][my_seat]:
		return "Choose your animal/settings, then press Ready.\nControls: WASD move  |  Right-drag look  |  M mute."
	return "Waiting for seats to fill and players to ready up.\nControls: WASD move  |  Right-drag look  |  Esc closes panels."

func _render_trick() -> void:
	for child in trick_box.get_children():
		child.queue_free()

	if view_state["trick"].is_empty():
		if view_state["phase"] != "bidding":
			var empty := Label.new()
			empty.text = "Table is clear"
			empty.add_theme_font_size_override("font_size", 22)
			empty.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
			trick_box.add_child(empty)
		return

	for play in view_state["trick"]:
		var stack := VBoxContainer.new()
		stack.alignment = BoxContainer.ALIGNMENT_CENTER
		var name := Label.new()
		name.text = view_state["names"][int(play["player"])]
		name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name.add_theme_color_override("font_color", Color("#f0d28a"))
		stack.add_child(name)
		var card_view = CardButtonScript.new()
		card_view.setup(play["card"])
		card_view.disabled = true
		stack.add_child(card_view)
		trick_box.add_child(stack)

func _render_actions() -> void:
	for child in action_box.get_children():
		child.queue_free()

	if view_state["phase"] == "lobby":
		var connected_count := _view_connected_count()
		if view_state["connected"][my_seat]:
			var ready_button := Button.new()
			ready_button.text = "Unready" if view_state["ready"][my_seat] else "Ready"
			_style_command_button(ready_button, not view_state["ready"][my_seat])
			ready_button.pressed.connect(_request_toggle_ready)
			action_box.add_child(ready_button)

		if multiplayer.multiplayer_peer and (multiplayer.is_server() or _view_can_request_start()):
			var start_button := Button.new()
			start_button.text = "Start Game"
			start_button.disabled = not _view_lobby_can_start()
			_style_command_button(start_button, true)
			start_button.pressed.connect(_request_start_game)
			action_box.add_child(start_button)

		var waiting := Label.new()
		var ready_count := _view_ready_count()
		waiting.text = "Players: %d / %d   Ready: %d / %d" % [
			connected_count,
			view_state["num_players"],
			ready_count,
			connected_count,
		]
		waiting.add_theme_color_override("font_color", Color("#f7f1e3"))
		action_box.add_child(waiting)
	elif view_state["phase"] == "connecting":
		var waiting := Label.new()
		waiting.text = "Joining table..."
		waiting.add_theme_color_override("font_color", Color("#f7f1e3"))
		action_box.add_child(waiting)
	elif view_state["phase"] == "bidding":
		if view_state["bid_submitted"][my_seat]:
			var waiting := Label.new()
			waiting.text = "Bid locked. Waiting for the table..."
			waiting.add_theme_color_override("font_color", Color("#f7f1e3"))
			action_box.add_child(waiting)
			return
		var round_size: int = view_state["sequence"][view_state["round_index"]]
		for amount in range(round_size + 1):
			var button := Button.new()
			button.text = str(amount)
			button.set_meta("bid", amount)
			_style_command_button(button, true)
			button.pressed.connect(_on_bid_button_pressed.bind(button))
			action_box.add_child(button)
	elif view_state["phase"] == "trick_end":
		var waiting := Label.new()
		waiting.text = "Next trick starts in a moment..."
		waiting.add_theme_color_override("font_color", Color("#f7f1e3"))
		action_box.add_child(waiting)
	elif view_state["phase"] == "round_end":
		var next_round := Button.new()
		next_round.text = "Next round"
		_style_command_button(next_round, true)
		next_round.pressed.connect(_request_next_round)
		action_box.add_child(next_round)
		var auto_note := Label.new()
		auto_note.text = "Auto-continues after 10 seconds."
		auto_note.add_theme_color_override("font_color", Color("#f7f1e3"))
		action_box.add_child(auto_note)
	elif view_state["phase"] == "game_end":
		var play_again := Button.new()
		play_again.text = "Waiting..." if view_state["play_again"][my_seat] else "Play Again"
		play_again.disabled = view_state["play_again"][my_seat]
		_style_command_button(play_again, true)
		play_again.pressed.connect(_request_play_again)
		action_box.add_child(play_again)

		var waiting := Label.new()
		waiting.text = "Play again: %d / %d" % [_play_again_count(), view_state["num_players"]]
		waiting.add_theme_color_override("font_color", Color("#f7f1e3"))
		action_box.add_child(waiting)

func _render_hand() -> void:
	var hand_signature := _hand_signature(local_hand)

	for child in hand_box.get_children():
		child.queue_free()

	last_hand_signature = hand_signature

func _legal_3d_card_index_at(mouse_position: Vector2) -> int:
	if not table_view_3d or not table_view_3d.has_method("pick_hand_card"):
		return -1
	var index: int = table_view_3d.pick_hand_card(mouse_position, get_viewport_rect().size)
	if index < 0 or index >= local_hand.size():
		return -1
	if not GameRules.is_legal_card(local_hand, view_state["led_suit"], local_hand[index]):
		return -1
	return index

func _set_3d_card_hover(index: int) -> void:
	if hovered_3d_card_index == index:
		return
	hovered_3d_card_index = index
	if table_view_3d and table_view_3d.has_method("set_hovered_hand_index"):
		table_view_3d.set_hovered_hand_index(index)

func _mouse_over_command_ui(position: Vector2) -> bool:
	for control in [action_box, history_button, end_game_button, player_hud_panel, round_history_panel, name_input, online_lobby_picker, advanced_network_button, mute_button, settings_button, rules_button, settings_panel, rules_panel, address_input, player_count_spin, max_cards_spin, discovered_game_picker, bot_personality_picker]:
		if control and control.visible:
			var rect := Rect2(control.global_position, control.size)
			if rect.has_point(position):
				return true
	return false

func _render_shuffle_stack() -> void:
	var stack := Control.new()
	stack.custom_minimum_size = Vector2(132, 124)
	trick_box.add_child(stack)

	for i in range(3):
		var back = CardButtonScript.new()
		back.setup({}, true)
		back.disabled = true
		back.mouse_filter = Control.MOUSE_FILTER_IGNORE
		back.position = Vector2(25 + i * 9, 8 + i * 3)
		back.rotation_degrees = -8 + i * 6
		back.pivot_offset = Vector2(37, 53)
		stack.add_child(back)

	var label := Label.new()
	label.text = "Shuffling / dealing"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.65))
	label.position = Vector2(0, 102)
	label.custom_minimum_size = Vector2(132, 20)
	stack.add_child(label)

	var round_key := "%s:%s:%s" % [str(view_state.get("round_index", -1)), str(view_state.get("sequence", [])), _hand_signature(local_hand)]
	if round_key == last_shuffle_round_key:
		return
	last_shuffle_round_key = round_key
	_animate_shuffle_stack(stack)

func _animate_shuffle_stack(stack: Control) -> void:
	for i in range(min(3, stack.get_child_count())):
		var card := stack.get_child(i) as Control
		if not card:
			continue
		var target_position := card.position
		var target_rotation := card.rotation_degrees
		card.position = target_position + Vector2(-28 + i * 18, -10)
		card.rotation_degrees = target_rotation - 14 + i * 8
		card.modulate.a = 0.0
		var tween := create_tween()
		tween.set_trans(Tween.TRANS_BACK)
		tween.set_ease(Tween.EASE_OUT)
		tween.tween_interval(i * 0.08)
		tween.tween_property(card, "modulate:a", 1.0, 0.16)
		tween.parallel().tween_property(card, "position", target_position, 0.32)
		tween.parallel().tween_property(card, "rotation_degrees", target_rotation, 0.32)

func _animate_card_dealt(button: Control, index: int) -> void:
	var target_position := button.position
	var target_scale := button.scale
	var target_rotation := button.rotation_degrees
	button.position = target_position + Vector2(0, -86)
	button.scale = Vector2(0.72, 0.72)
	button.rotation_degrees = rng.randf_range(-14.0, 14.0)
	button.modulate.a = 0.0

	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_interval(index * 0.055)
	tween.tween_property(button, "modulate:a", 1.0, 0.12)
	tween.parallel().tween_property(button, "position", target_position, 0.34)
	tween.parallel().tween_property(button, "scale", target_scale, 0.34)
	tween.parallel().tween_property(button, "rotation_degrees", target_rotation, 0.34)

func _hand_signature(hand: Array) -> String:
	var parts: Array = []
	for card in hand:
		parts.append("%s%s" % [str(card.get("suit", "")), str(card.get("rank", ""))])
	return "|".join(parts)

func _view_connected_count() -> int:
	if not view_state.has("connected"):
		return 0
	var count := 0
	for connected in view_state["connected"]:
		if connected:
			count += 1
	return count

func _view_ready_count() -> int:
	if not view_state.has("ready") or not view_state.has("connected"):
		return 0
	var count := 0
	var connected: Array = view_state.get("connected", [])
	var ready: Array = view_state.get("ready", [])
	for seat in range(min(connected.size(), ready.size())):
		if bool(connected[seat]) and bool(ready[seat]):
			count += 1
	return count

func _view_lobby_can_start() -> bool:
	if view_state.is_empty() or view_state["phase"] != "lobby":
		return false
	var human_count := 0
	for i in range(view_state["num_players"]):
		var is_bot := view_state.has("bots") and bool(view_state["bots"][i])
		if is_bot:
			continue
		if not view_state["connected"][i]:
			continue
		human_count += 1
		if not view_state["ready"][i]:
			return false
	return human_count > 0

func _view_can_request_start() -> bool:
	if view_state.is_empty() or view_state.get("phase", "") != "lobby":
		return false
	for seat in range(view_state["num_players"]):
		if view_state["connected"][seat] and not (view_state.has("bots") and bool(view_state["bots"][seat])):
			return seat == my_seat
	return false

func _lobby_host_name() -> String:
	if view_state.is_empty():
		return "Waiting"
	for seat in range(view_state["num_players"]):
		if view_state["connected"][seat] and not (view_state.has("bots") and bool(view_state["bots"][seat])):
			return str(view_state["names"][seat])
	return "Waiting"

func _table_host_seat_from_view() -> int:
	if view_state.is_empty():
		return -1
	for seat in range(view_state["num_players"]):
		if view_state["connected"][seat] and not (view_state.has("bots") and bool(view_state["bots"][seat])):
			return seat
	return -1

func _play_again_count() -> int:
	if not view_state.has("play_again"):
		return 0
	var count := 0
	for voted in view_state["play_again"]:
		if voted:
			count += 1
	return count

func _toggle_round_history() -> void:
	round_history_visible = not round_history_visible
	_sync_round_history_visibility()
	_play_sfx("click")

func _toggle_scoreboard() -> void:
	var phase := str(view_state.get("phase", ""))
	if not (phase in ["bidding", "playing", "trick_end", "round_end"]):
		return
	scoreboard_visible = not scoreboard_visible
	_sync_scoreboard_visibility()
	_play_sfx("click")

func _sync_scoreboard_visibility() -> void:
	if not player_hud_panel:
		return
	var phase := str(view_state.get("phase", ""))
	var can_show := phase in ["bidding", "playing", "trick_end", "round_end"]
	player_hud_panel.visible = scoreboard_visible and can_show
	if player_hud_panel.visible and left_stats_label:
		_render_scoreboard_panel()
	elif left_stats_label:
		left_stats_label.text = ""
		if scoreboard_grid:
			for child in scoreboard_grid.get_children():
				child.queue_free()

func _sync_turn_banner() -> void:
	if not turn_banner_panel or not turn_banner_label or view_state.is_empty():
		return
	var phase := str(view_state.get("phase", ""))
	var should_show := false
	var text := ""
	var submitted: Array = view_state.get("bid_submitted", [])
	if phase == "playing" and int(view_state.get("active_player", -1)) == my_seat:
		should_show = true
		text = "YOUR TURN - PLAY A CARD"
	elif phase == "bidding" and my_seat < submitted.size() and not bool(submitted[my_seat]):
		should_show = true
		text = "YOUR BID - CHOOSE A NUMBER"
	turn_banner_panel.visible = should_show
	turn_banner_panel.modulate = Color.WHITE
	turn_banner_label.text = text

func _game_prompt_text() -> String:
	var phase := str(view_state.get("phase", ""))
	if phase == "bidding":
		var submitted: Array = view_state.get("bid_submitted", [])
		if my_seat < submitted.size() and not bool(submitted[my_seat]):
			return "Choose your bid. Your bid stays hidden until everyone locks in."
		return "%s\nWaiting for the rest of the table." % str(view_state.get("message", ""))
	if phase == "playing":
		var active := int(view_state.get("active_player", -1))
		if active == my_seat:
			var led_value = view_state.get("led_suit", null)
			if led_value == null:
				return "Your turn. Lead the trick with any legal card."
			var led := str(led_value)
			if led.is_empty():
				return "Your turn. Lead the trick with any legal card."
			return "Your turn. Follow %s if you can." % GameRules.SUIT_NAMES.get(led, led)
		var names: Array = view_state.get("names", [])
		if active >= 0 and active < names.size():
			return "Waiting for %s to play." % str(names[active])
	if phase == "trick_end":
		return "%s\nNext trick starts automatically." % str(view_state.get("message", ""))
	if phase == "round_end":
		return "%s\n%s\nNext round starts automatically in 10 seconds." % [
			str(view_state.get("message", "")),
			_round_end_summary_text(),
		]
	return str(view_state.get("message", ""))

func _round_end_summary_text() -> String:
	var bids: Array = view_state.get("bids", [])
	var tricks: Array = view_state.get("tricks_won", [])
	if my_seat < 0 or my_seat >= bids.size() or my_seat >= tricks.size() or bids[my_seat] == null:
		return "Round results are in."
	var bid := int(bids[my_seat])
	var won := int(tricks[my_seat])
	var delta := 10 + bid if bid == won else 0
	var result := "Made it" if bid == won else "Busted"
	return "%s: you bid %d and won %d trick%s. +%d points this round." % [
		result,
		bid,
		won,
		"" if won == 1 else "s",
		delta,
	]

func _sync_round_history_visibility() -> void:
	if not round_history_panel:
		return
	var phase := str(view_state.get("phase", ""))
	var can_show := phase in ["bidding", "playing", "trick_end", "round_end", "game_end"]
	round_history_panel.visible = round_history_visible and can_show
	if history_button:
		history_button.text = "Hide History" if round_history_visible else "History"
	if round_history_panel.visible and round_history_label:
		round_history_label.text = _round_history_text()

func _scoreboard_text() -> String:
	var names: Array = view_state.get("names", [])
	var scores: Array = view_state.get("scores", [])
	var bids: Array = view_state.get("bids", [])
	var submitted: Array = view_state.get("bid_submitted", [])
	var tricks: Array = view_state.get("tricks_won", [])
	var active := int(view_state.get("active_player", -1))
	var phase := str(view_state.get("phase", ""))
	var round_number := int(view_state.get("round_index", 0)) + 1
	var round_sequence: Array = view_state.get("sequence", [])
	var round_total := round_sequence.size()
	var round_cards := 0
	if round_number - 1 < round_sequence.size():
		round_cards = int(round_sequence[round_number - 1])
	var lines := [
		"SCOREBOARD",
		"Round %d / %d    Cards %d" % [round_number, round_total, round_cards],
		"",
		"   PLAYER               PTS   BID   TRICKS",
	]
	for seat in range(names.size()):
		var name := _scoreboard_name(str(names[seat]), seat)
		var points := int(scores[seat]) if seat < scores.size() else 0
		var bid_text := _scoreboard_bid_text(seat, bids, submitted, phase)
		var trick_count := int(tricks[seat]) if seat < tricks.size() else 0
		var marker := ">" if seat == active else " "
		lines.append("%s  %s %s   %s   %s" % [
			marker,
			_pad_right(name, 18),
			_pad_left(str(points), 3),
			_pad_left(bid_text, 3),
			_pad_left(str(trick_count), 5),
		])
	lines.append("")
	lines.append("Press Tab to close.")
	return "\n".join(lines)

func _render_scoreboard_panel() -> void:
	if not left_stats_label or not scoreboard_grid:
		return
	for child in scoreboard_grid.get_children():
		child.queue_free()
	var names: Array = view_state.get("names", [])
	var scores: Array = view_state.get("scores", [])
	var bids: Array = view_state.get("bids", [])
	var submitted: Array = view_state.get("bid_submitted", [])
	var tricks: Array = view_state.get("tricks_won", [])
	var active := int(view_state.get("active_player", -1))
	var phase := str(view_state.get("phase", ""))
	var round_number := int(view_state.get("round_index", 0)) + 1
	var round_sequence: Array = view_state.get("sequence", [])
	var round_total := round_sequence.size()
	var round_cards := 0
	if round_number - 1 < round_sequence.size():
		round_cards = int(round_sequence[round_number - 1])
	left_stats_label.text = "SCOREBOARD\nRound %d / %d    Cards %d" % [round_number, round_total, round_cards]
	_add_scoreboard_cell("PLAYER", true, HORIZONTAL_ALIGNMENT_LEFT)
	_add_scoreboard_cell("PTS", true)
	_add_scoreboard_cell("BID", true)
	_add_scoreboard_cell("TRICKS", true)
	for seat in range(names.size()):
		var name := _scoreboard_name(str(names[seat]), seat)
		if seat == active:
			name = "> " + name
		else:
			name = "  " + name
		var points := int(scores[seat]) if seat < scores.size() else 0
		var bid_text := _scoreboard_bid_text(seat, bids, submitted, phase)
		var trick_count := int(tricks[seat]) if seat < tricks.size() else 0
		_add_scoreboard_cell(name, false, HORIZONTAL_ALIGNMENT_LEFT, seat == active)
		_add_scoreboard_cell(str(points), false, HORIZONTAL_ALIGNMENT_CENTER, seat == active)
		_add_scoreboard_cell(bid_text, false, HORIZONTAL_ALIGNMENT_CENTER, seat == active)
		_add_scoreboard_cell(str(trick_count), false, HORIZONTAL_ALIGNMENT_CENTER, seat == active)
	_add_scoreboard_hint()

func _add_scoreboard_cell(text: String, header := false, align := HORIZONTAL_ALIGNMENT_CENTER, active := false) -> void:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = align
	label.custom_minimum_size = Vector2(170 if align == HORIZONTAL_ALIGNMENT_LEFT else 58, 0)
	label.add_theme_font_size_override("font_size", 18 if header else 20)
	label.add_theme_color_override("font_color", Color("#ffe18f") if active else Color("#f7f1e3"))
	label.add_theme_color_override("font_shadow_color", Color("#050807"))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	scoreboard_grid.add_child(label)

func _add_scoreboard_hint() -> void:
	var spacer_count := 4 - (scoreboard_grid.get_child_count() % 4)
	if spacer_count < 4:
		for _i in range(spacer_count):
			_add_scoreboard_cell("")
	var hint := Label.new()
	hint.text = "Press Tab or Esc to close."
	hint.add_theme_font_size_override("font_size", 18)
	hint.add_theme_color_override("font_color", Color("#f7f1e3"))
	hint.add_theme_color_override("font_shadow_color", Color("#050807"))
	hint.add_theme_constant_override("shadow_offset_x", 1)
	hint.add_theme_constant_override("shadow_offset_y", 1)
	scoreboard_grid.add_child(hint)

func _scoreboard_name(name: String, seat: int) -> String:
	var label := name
	if seat == my_seat:
		label += " (You)"
	if label.length() > 18:
		return label.substr(0, 17) + "."
	return label

func _pad_right(value: String, width: int) -> String:
	var output := value
	while output.length() < width:
		output += " "
	return output

func _pad_left(value: String, width: int) -> String:
	var output := value
	while output.length() < width:
		output = " " + output
	return output

func _scoreboard_bid_text(seat: int, bids: Array, submitted: Array, phase: String) -> String:
	if phase == "bidding":
		if seat < submitted.size() and bool(submitted[seat]):
			return "in"
		return "..."
	if seat < bids.size() and bids[seat] != null:
		return str(bids[seat])
	return "-"

func _round_history_text() -> String:
	var history: Array = view_state.get("round_history", [])
	var names: Array = view_state.get("names", [])
	if history.is_empty():
		return "Round History\n\nNo completed rounds yet."
	var text := "Round History\n"
	for summary in history:
		var round_number := int(summary.get("round_index", 0)) + 1
		var bids: Array = summary.get("bids", [])
		var tricks: Array = summary.get("tricks_won", [])
		var deltas := GameRules.score_deltas(bids, tricks)
		var exact_count := 0
		for seat in range(min(names.size(), bids.size())):
			if int(bids[seat]) == int(tricks[seat]):
				exact_count += 1
		text += "\nRound %d  |  exact bids: %d / %d\n" % [round_number, exact_count, min(names.size(), bids.size())]
		for seat in range(min(names.size(), bids.size())):
			var made := int(bids[seat]) == int(tricks[seat])
			text += "%-16s bid %d, took %d, %s" % [
				str(names[seat]),
				int(bids[seat]),
				int(tricks[seat]),
				"+%d" % int(deltas[seat]) if made else "miss",
			]
			if seat < names.size() - 1:
				text += "\n"
	return text

func _selected_map_id() -> String:
	return MAP_IDS[lobby_map_index % MAP_IDS.size()]

func _music_key_for_state() -> String:
	if view_state.is_empty():
		return "menu"
	if bool(view_state.get("menu_preview", false)):
		return "menu"
	var phase := str(view_state.get("phase", ""))
	if phase in ["connecting", "lobby", "game_end"]:
		return "menu"
	return str(view_state.get("map_id", DEFAULT_MAP_ID))

func _update_music() -> void:
	if not music_player:
		return
	var key := _music_key_for_state()
	if key == current_music_key and music_player.playing:
		return
	current_music_key = key
	var stream = _music_stream_for_key(key)
	if not stream:
		return
	music_player.stream = stream
	music_player.play()

func _music_stream_for_key(key: String):
	if music_streams.has(key):
		return music_streams[key]
	var path := str(MUSIC_PATHS.get(key, MUSIC_PATHS["menu"]))
	var stream = load(path)
	if not stream:
		stream = AudioStreamOggVorbis.load_from_file(path)
	if stream is AudioStreamOggVorbis:
		stream.loop = true
	if not stream and key != "menu":
		stream = _music_stream_for_key("menu")
	music_streams[key] = stream
	return stream

func _set_sound_event(name: String, seat := -1) -> void:
	if state.is_empty():
		return
	var serial := int(state.get("sound_serial", 0)) + 1
	state["sound_serial"] = serial
	state["sound_event"] = {"name": name, "serial": serial, "seat": seat}

func _request_hidden_emote() -> void:
	if view_state.is_empty():
		return
	if not (view_state.get("phase", "") in ["bidding", "playing", "trick_end", "round_end", "game_end"]):
		return
	if my_seat < 0:
		return
	if multiplayer.multiplayer_peer and not multiplayer.is_server():
		_server_hidden_emote.rpc_id(1)
	else:
		_apply_hidden_emote(my_seat)

@rpc("any_peer", "reliable")
func _server_hidden_emote() -> void:
	if not multiplayer.is_server():
		return
	_apply_hidden_emote(_seat_for_peer(multiplayer.get_remote_sender_id()))

func _apply_hidden_emote(seat: int) -> void:
	if state.is_empty() or seat < 0 or seat >= int(state.get("num_players", 0)):
		return
	if not (state.get("phase", "") in ["bidding", "playing", "trick_end", "round_end", "game_end"]):
		return
	var serial := int(state.get("emote_serial", 0)) + 1
	state["emote_serial"] = serial
	state["emote_event"] = {"name": "middle_finger", "serial": serial, "seat": seat}
	_set_sound_event("click", seat)
	_publish_state()

func _handle_sound_event(event) -> void:
	if typeof(event) != TYPE_DICTIONARY:
		return
	var serial := int(event.get("serial", 0))
	if serial <= 0 or serial <= last_sound_serial:
		return
	last_sound_serial = serial
	_play_sfx(str(event.get("name", "")))

func _play_sfx(name: String) -> void:
	if not sfx_player:
		return
	if Profile.sfx_muted():
		return
	var volume := Profile.sfx_volume()
	if volume <= 0.0:
		return
	var stream = _sfx_stream_for_name(name)
	if not stream:
		return
	sfx_player.stream = stream
	sfx_player.volume_db = linear_to_db(volume)
	sfx_player.play()

func _sfx_stream_for_name(name: String):
	if sfx_streams.has(name):
		return sfx_streams[name]
	var freq := 540.0
	var duration := 0.10
	match name:
		"click":
			freq = 720.0
			duration = 0.045
		"bid":
			freq = 620.0
			duration = 0.075
		"card":
			freq = 390.0
			duration = 0.085
		"deal":
			freq = 500.0
			duration = 0.16
		"trick":
			freq = 780.0
			duration = 0.18
		"round":
			freq = 660.0
			duration = 0.22
		"game":
			freq = 880.0
			duration = 0.32
	var stream := _make_tone_stream(freq, duration)
	sfx_streams[name] = stream
	return stream

func _make_tone_stream(freq: float, duration: float) -> AudioStreamWAV:
	var mix_rate := 22050
	var frames := int(float(mix_rate) * duration)
	var data := PackedByteArray()
	data.resize(frames * 2)
	for i in range(frames):
		var t := float(i) / float(mix_rate)
		var fade := minf(1.0, float(frames - i) / maxf(float(frames) * 0.22, 1.0))
		var sample := int(sin(TAU * freq * t) * 11000.0 * fade)
		data.encode_s16(i * 2, sample)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = mix_rate
	stream.stereo = false
	stream.data = data
	return stream

func _selected_map_name() -> String:
	var map_id := _selected_map_id()
	return str(MAP_NAMES.get(map_id, map_id))

func _map_index_for_id(map_id: String) -> int:
	var index := MAP_IDS.find(map_id)
	return 0 if index == -1 else index

func _on_previous_map_pressed() -> void:
	_change_lobby_map(-1)

func _on_next_map_pressed() -> void:
	_change_lobby_map(1)

func _change_lobby_map(direction: int) -> void:
	lobby_map_index = posmod(lobby_map_index + direction, MAP_IDS.size())
	if map_name_label:
		map_name_label.text = _selected_map_name()
	if not _can_edit_lobby_settings():
		lobby_map_index = _map_index_for_id(str(view_state.get("map_id", _selected_map_id())))
		if map_name_label:
			map_name_label.text = _selected_map_name()
		_set_status("The table host chooses the map.")
		return
	if multiplayer.multiplayer_peer:
		_request_lobby_map(_selected_map_id())
	elif not multiplayer.multiplayer_peer:
		_create_offline_lobby()

func _read_lobby_inputs() -> void:
	_read_local_profile_input()
	lobby_player_count = int(player_count_spin.value)
	lobby_max_cards = int(max_cards_spin.value)
	lobby_max_cards = clampi(lobby_max_cards, 1, GameRules.max_allowed_cards(lobby_player_count))

func _read_local_profile_input() -> void:
	local_player_name = name_input.text.strip_edges()
	if local_player_name.is_empty():
		local_player_name = "Player"
	Profile.set_display_name(local_player_name)
	local_player_name = Profile.display_name()
	_update_local_profile_on_table()

func _update_local_profile_on_table() -> void:
	if state.is_empty():
		return
	if multiplayer.multiplayer_peer and not multiplayer.is_server():
		_server_register_profile.rpc_id(1, Profile.public_profile())
		return
	if my_seat >= 0 and my_seat < int(state.get("num_players", 0)):
		state["profiles"][my_seat] = Profile.public_profile()
		state["names"][my_seat] = Profile.display_name()
		_publish_state()

func _can_edit_lobby_settings() -> bool:
	if not multiplayer.multiplayer_peer:
		return true
	if multiplayer.is_server():
		return not dedicated_server
	return _view_can_request_start()

func _sync_lobby_settings_controls() -> void:
	if player_count_spin:
		player_count_spin.editable = _can_edit_lobby_settings()
		player_count_spin.set_block_signals(true)
		player_count_spin.value = lobby_player_count
		player_count_spin.set_block_signals(false)
	if max_cards_spin:
		max_cards_spin.editable = _can_edit_lobby_settings()
		max_cards_spin.set_block_signals(true)
		max_cards_spin.max_value = GameRules.max_allowed_cards(lobby_player_count)
		max_cards_spin.value = clampi(lobby_max_cards, 1, GameRules.max_allowed_cards(lobby_player_count))
		max_cards_spin.set_block_signals(false)
	if bot_personality_picker:
		bot_personality_picker.disabled = not _can_edit_lobby_settings()
		var bot_index := BOT_PERSONALITY_IDS.find(str(view_state.get("bot_personality", Profile.bot_personality())))
		bot_personality_picker.set_block_signals(true)
		bot_personality_picker.selected = max(bot_index, 0)
		bot_personality_picker.set_block_signals(false)

func _on_name_changed(new_text: String) -> void:
	local_player_name = new_text.strip_edges()
	if local_player_name.is_empty():
		local_player_name = "Player"
	Profile.set_display_name(local_player_name)
	local_player_name = Profile.display_name()
	if state.get("phase", "") == "lobby":
		_update_local_profile_on_table()

func _on_player_count_changed(value: float) -> void:
	if not _can_edit_lobby_settings():
		_sync_lobby_settings_controls()
		return
	lobby_player_count = int(value)
	var allowed := GameRules.max_allowed_cards(lobby_player_count)
	max_cards_spin.max_value = allowed
	if max_cards_spin.value > allowed:
		max_cards_spin.value = allowed
	lobby_max_cards = int(max_cards_spin.value)
	if multiplayer.multiplayer_peer:
		_request_lobby_settings(lobby_player_count, lobby_max_cards)
	elif not multiplayer.multiplayer_peer:
		_create_offline_lobby()

func _on_max_cards_changed(value: float) -> void:
	if not _can_edit_lobby_settings():
		_sync_lobby_settings_controls()
		return
	lobby_max_cards = int(value)
	if multiplayer.multiplayer_peer:
		_request_lobby_settings(lobby_player_count, lobby_max_cards)
	elif not multiplayer.multiplayer_peer:
		_create_offline_lobby()

func _request_lobby_settings(player_count: int, max_cards: int) -> void:
	if multiplayer.multiplayer_peer and not multiplayer.is_server():
		_server_update_lobby_settings.rpc_id(1, player_count, max_cards)
	else:
		_resize_host_lobby(player_count, max_cards)

@rpc("any_peer", "reliable")
func _server_update_lobby_settings(player_count: int, max_cards: int) -> void:
	if not multiplayer.is_server() or not dedicated_server:
		return
	if state.get("phase", "") != "lobby":
		return
	var sender_seat := _seat_for_peer(multiplayer.get_remote_sender_id())
	if sender_seat != _first_connected_human_seat():
		return
	_resize_host_lobby(player_count, max_cards)

func _request_lobby_map(map_id: String) -> void:
	if multiplayer.multiplayer_peer and not multiplayer.is_server():
		_server_update_lobby_map.rpc_id(1, map_id)
	else:
		_apply_lobby_map(map_id)

@rpc("any_peer", "reliable")
func _server_update_lobby_map(map_id: String) -> void:
	if not multiplayer.is_server() or not dedicated_server:
		return
	if state.get("phase", "") != "lobby":
		return
	var sender_seat := _seat_for_peer(multiplayer.get_remote_sender_id())
	if sender_seat != _first_connected_human_seat():
		return
	_apply_lobby_map(map_id)

func _apply_lobby_map(map_id: String) -> void:
	lobby_map_index = _map_index_for_id(map_id)
	if map_name_label:
		map_name_label.text = _selected_map_name()
	if state.has("map_id") and state.get("phase", "") == "lobby":
		state["map_id"] = _selected_map_id()
		_publish_state()
		if multiplayer.multiplayer_peer and multiplayer.is_server():
			Net.update_advertisement(_discovery_info())
	elif not multiplayer.multiplayer_peer:
		_create_offline_lobby()

func _request_bot_personality(personality: String) -> void:
	if multiplayer.multiplayer_peer and not multiplayer.is_server():
		_server_update_bot_personality.rpc_id(1, personality)
	else:
		_apply_bot_personality(personality)

@rpc("any_peer", "reliable")
func _server_update_bot_personality(personality: String) -> void:
	if not multiplayer.is_server() or not dedicated_server:
		return
	if state.get("phase", "") != "lobby":
		return
	var sender_seat := _seat_for_peer(multiplayer.get_remote_sender_id())
	if sender_seat != _first_connected_human_seat():
		return
	_apply_bot_personality(personality)

func _apply_bot_personality(personality: String) -> void:
	if not BOT_PERSONALITY_IDS.has(personality):
		personality = "smart"
	if state.has("bot_personality") and state.get("phase", "") == "lobby":
		state["bot_personality"] = personality
		state["message"] = "Bot style changed to %s." % str(BOT_PERSONALITY_NAMES.get(personality, "Smart"))
		_publish_state()
	elif not multiplayer.multiplayer_peer:
		_create_offline_lobby()

func _resize_host_lobby(player_count: int, max_cards: int) -> void:
	player_count = clampi(player_count, 2, 10)
	max_cards = clampi(max_cards, 1, GameRules.max_allowed_cards(player_count))
	lobby_player_count = player_count
	lobby_max_cards = max_cards

	var old_names: Array = state.get("names", []).duplicate(true)
	var old_profiles: Array = state.get("profiles", []).duplicate(true)
	var old_ready: Array = state.get("ready", []).duplicate(true)
	var old_bots: Array = state.get("bots", []).duplicate(true)
	var old_lobby_avatars: Array = state.get("lobby_avatars", []).duplicate(true)
	var old_peers: Array = seat_peers.duplicate(true)
	seat_peers = _new_seat_peers(player_count)

	var first_preserved_seat := 0 if dedicated_server else 1
	for seat in range(first_preserved_seat, player_count):
		if seat < old_peers.size():
			seat_peers[seat] = old_peers[seat]

	state["num_players"] = player_count
	state["max_cards"] = max_cards
	state["sequence"] = GameRules.down_up_sequence(max_cards)
	state["names"] = _default_names(player_count)
	state["profiles"] = _default_profiles(player_count)
	state["bots"] = _filled_array(player_count, false)
	state["lobby_avatars"] = _default_lobby_avatars(player_count)
	state["ready"] = _filled_array(player_count, false)
	for seat in range(player_count):
		if seat < old_names.size():
			state["names"][seat] = old_names[seat]
		if seat < old_profiles.size():
			state["profiles"][seat] = old_profiles[seat]
		if seat < old_bots.size() and int(seat_peers[seat]) == 0:
			state["bots"][seat] = old_bots[seat]
		if seat < old_lobby_avatars.size() and typeof(old_lobby_avatars[seat]) == TYPE_DICTIONARY:
			state["lobby_avatars"][seat] = old_lobby_avatars[seat]
		if seat < old_ready.size() and int(seat_peers[seat]) != 0:
			state["ready"][seat] = old_ready[seat]
	state["connected"] = _connected_seats()
	state["message"] = "Table changed to %d players, %d max cards." % [player_count, max_cards]
	_publish_state()
	Net.update_advertisement(_discovery_info())

func _on_discovered_games_changed(games: Array) -> void:
	discovered_games = games
	discovered_game_picker.clear()
	if discovered_games.is_empty():
		discovered_game_picker.add_item("No games found")
		return
	for i in range(discovered_games.size()):
		var game: Dictionary = discovered_games[i]
		var label := "%s  %s  %d/%d" % [
			game.get("name", "Oh Hell table"),
			game.get("address", ""),
			int(game.get("players", 0)),
			int(game.get("max_players", 0)),
		]
		discovered_game_picker.add_item(label)
		discovered_game_picker.set_item_metadata(i, game)

func _on_join_found_pressed() -> void:
	if discovered_games.is_empty():
		_set_status("No LAN games found yet.")
		return
	var index := discovered_game_picker.selected
	if index < 0 or index >= discovered_games.size():
		_set_status("Choose a discovered game first.")
		return
	var game: Dictionary = discovered_games[index]
	address_input.text = "%s:%d" % [str(game.get("address", "")), int(game.get("port", Net.DEFAULT_PORT))]
	_on_join_pressed()

func _on_bid_button_pressed(button: Button) -> void:
	_submit_bid(int(button.get_meta("bid")))

func _on_card_button_pressed(button: Button) -> void:
	_submit_card(button.get_meta("card"))

func _submit_bid(amount: int) -> void:
	if multiplayer.multiplayer_peer and not multiplayer.is_server():
		_server_submit_bid.rpc_id(1, amount)
	else:
		_apply_bid(my_seat, amount)

@rpc("any_peer", "reliable")
func _server_submit_bid(amount: int) -> void:
	_apply_bid(_seat_for_peer(multiplayer.get_remote_sender_id()), amount)

func _apply_bid(seat: int, amount: int) -> void:
	if state["phase"] != "bidding":
		return
	if seat < 0 or seat >= state["num_players"]:
		return
	if state["bid_submitted"][seat]:
		return
	var round_size: int = state["sequence"][state["round_index"]]
	if amount < 0 or amount > round_size:
		return
	state["bids"][seat] = amount
	state["bid_submitted"][seat] = true
	if _all_bids_in():
		state["phase"] = "playing"
		state["active_player"] = state["leader"]
		state["message"] = "%s leads." % state["names"][state["leader"]]
		_set_sound_event("bid", seat)
		_advance_bot_turn_serial()
	else:
		state["message"] = _bidding_message()
		_set_sound_event("bid", seat)
	_publish_state()
	_schedule_bot_action()

func _all_bids_in() -> bool:
	for submitted in state["bid_submitted"]:
		if not submitted:
			return false
	return true

func _submit_card(card: Dictionary) -> void:
	if multiplayer.multiplayer_peer and not multiplayer.is_server():
		_server_submit_card.rpc_id(1, card)
	else:
		_apply_card(my_seat, card)

@rpc("any_peer", "reliable")
func _server_submit_card(card: Dictionary) -> void:
	_apply_card(_seat_for_peer(multiplayer.get_remote_sender_id()), card)

func _apply_card(seat: int, card: Dictionary) -> void:
	if seat != state["active_player"] or state["phase"] != "playing":
		return
	if not GameRules.is_legal_card(state["hands"][seat], state["led_suit"], card):
		return

	state["hands"][seat] = GameRules.remove_card(state["hands"][seat], card)
	if state["trick"].is_empty():
		state["led_suit"] = card["suit"]
	state["trick"].append({"player": seat, "card": card})
	if not state.has("played_cards"):
		state["played_cards"] = []
	state["played_cards"].append(card.duplicate(true))
	_set_sound_event("card", seat)

	if state["trick"].size() == state["num_players"]:
		var winner := GameRules.trick_winner(state["trick"], state["led_suit"], state["trump"])
		state["leader"] = winner
		state["active_player"] = winner
		state["phase"] = "trick_end"
		state["message"] = "%s wins the trick and leads next." % state["names"][winner]
		_set_sound_event("trick", winner)
		_publish_state()
		_schedule_auto_continue_after_trick(state["round_index"], winner)
		return
	else:
		state["active_player"] = (seat + 1) % state["num_players"]
		state["message"] = "%s, play a card." % state["names"][state["active_player"]]
		_advance_bot_turn_serial()
	_publish_state()
	_schedule_bot_action()

func _schedule_auto_continue_after_trick(round_index: int, winner: int) -> void:
	await get_tree().create_timer(2.0).timeout
	if state["phase"] != "trick_end":
		return
	if state["round_index"] != round_index:
		return
	if state["active_player"] != winner:
		return
	_continue_after_trick()

func _request_continue_after_trick() -> void:
	if multiplayer.multiplayer_peer and not multiplayer.is_server():
		_server_continue_after_trick.rpc_id(1)
	else:
		_continue_after_trick()

@rpc("any_peer", "reliable")
func _server_continue_after_trick() -> void:
	_continue_after_trick()

func _continue_after_trick() -> void:
	if state["phase"] != "trick_end":
		return
	var winner: int = state["active_player"]
	state["tricks_won"][winner] += 1
	state["trick"] = []
	state["led_suit"] = null
	state["leader"] = winner
	if state["hands"][winner].is_empty():
		_record_round_history()
		var deltas := GameRules.score_deltas(state["bids"], state["tricks_won"])
		for i in range(state["num_players"]):
			state["scores"][i] += deltas[i]
		state["phase"] = "round_end"
		state["message"] = "Round over."
		_set_sound_event("round")
	else:
		state["phase"] = "playing"
		state["active_player"] = state["leader"]
		state["message"] = "%s leads." % state["names"][state["leader"]]
		_advance_bot_turn_serial()
	_publish_state()
	if state.get("phase", "") == "round_end":
		_schedule_auto_next_round_after_round_end(state["round_index"])
	_schedule_bot_action()

func _advance_bot_turn_serial() -> void:
	bot_turn_serial += 1
	bot_action_key = ""

func _request_next_round() -> void:
	if multiplayer.multiplayer_peer and not multiplayer.is_server():
		_server_next_round.rpc_id(1)
	else:
		_next_round()

@rpc("any_peer", "reliable")
func _server_next_round() -> void:
	_next_round()

func _next_round() -> void:
	if state.get("phase", "") != "round_end":
		return
	state["round_index"] += 1
	state["dealer"] = (state["dealer"] + 1) % state["num_players"]
	if state["round_index"] >= state["sequence"].size():
		_end_game()
		return
	_begin_round()

func _schedule_auto_next_round_after_round_end(round_index: int) -> void:
	await get_tree().create_timer(10.0).timeout
	if state.get("phase", "") != "round_end":
		return
	if int(state.get("round_index", -1)) != round_index:
		return
	_next_round()

func _schedule_bot_action() -> void:
	if not multiplayer.multiplayer_peer or not multiplayer.is_server():
		return
	if state.is_empty():
		return
	if state.get("phase", "") == "bidding":
		for seat in range(state["num_players"]):
			if _is_bot_seat(seat) and not state["bid_submitted"][seat]:
				_queue_bot_bid(seat)
				return
	elif state.get("phase", "") == "playing":
		var seat := int(state["active_player"])
		if _is_bot_seat(seat):
			_queue_bot_card(seat)

func _queue_bot_bid(seat: int) -> void:
	var key := "bid:%d:%d:%d" % [bot_turn_serial, int(state["round_index"]), seat]
	if bot_action_key == key:
		return
	bot_action_key = key
	await get_tree().create_timer(rng.randf_range(0.7, 1.25)).timeout
	if bot_action_key != key or state.get("phase", "") != "bidding":
		return
	if not _is_bot_seat(seat) or state["bid_submitted"][seat]:
		return
	_apply_bid(seat, _bot_choose_bid(seat))

func _queue_bot_card(seat: int) -> void:
	var key := "card:%d:%d:%d:%d" % [bot_turn_serial, int(state["round_index"]), state["trick"].size(), seat]
	if bot_action_key == key:
		return
	bot_action_key = key
	await get_tree().create_timer(rng.randf_range(0.8, 1.45)).timeout
	if bot_action_key != key or state.get("phase", "") != "playing":
		return
	if int(state["active_player"]) != seat or not _is_bot_seat(seat):
		return
	_apply_card(seat, _bot_choose_card(seat))

func _bot_choose_bid(seat: int) -> int:
	var hand: Array = state["hands"][seat]
	var round_size: int = state["sequence"][state["round_index"]]
	var estimate := 0.0
	for card in hand:
		estimate += _bot_bid_value(card, hand)
	if round_size <= 2 and estimate > 0.65:
		estimate += 0.15
	elif round_size >= 5:
		estimate -= 0.2
	match _bot_personality():
		"casual":
			estimate += rng.randf_range(-0.65, 0.65)
		"ruthless":
			estimate += 0.18
			estimate += rng.randf_range(-0.12, 0.18)
		_:
			estimate += rng.randf_range(-0.28, 0.28)
	return clampi(roundi(estimate), 0, round_size)

func _bot_choose_card(seat: int) -> Dictionary:
	var legal: Array = GameRules.legal_cards(state["hands"][seat], state["led_suit"])
	if legal.is_empty():
		return state["hands"][seat][0]
	if _bot_personality() == "casual" and rng.randf() < 0.18:
		return legal[rng.randi_range(0, legal.size() - 1)]
	var target: int = maxi(0, int(state["bids"][seat]) - int(state["tricks_won"][seat]))
	var remaining_after_play: int = maxi(0, state["hands"][seat].size() - 1)
	var must_chase: bool = target >= state["hands"][seat].size()
	var wants_trick: bool = target > 0
	if _bot_personality() == "ruthless" and target > 0 and remaining_after_play <= target:
		must_chase = true

	if state["trick"].is_empty():
		return _bot_choose_lead_card(legal, target, remaining_after_play, must_chase)
	return _bot_choose_follow_card(legal, target, remaining_after_play, wants_trick, must_chase)

func _bot_card_power(card: Dictionary) -> int:
	var power := int(card["rank"])
	if card["suit"] == state["trump"]:
		power += 20
	elif state["led_suit"] != null and card["suit"] == state["led_suit"]:
		power += 8
	return power

func _bot_bid_value(card: Dictionary, hand: Array) -> float:
	var rank := int(card["rank"])
	var threats := _bot_threat_count(card, hand)
	var value := 0.0
	if card["suit"] == state["trump"]:
		value = 0.95 if threats == 0 else 0.78 if threats <= 1 else 0.52 if rank >= 11 else 0.28
	else:
		value = 0.82 if threats == 0 and rank >= 13 else 0.62 if threats <= 1 and rank >= 12 else 0.35 if rank >= 11 else 0.08
		var lower_same := _bot_count_lower_owned_in_suit(card, hand)
		value += minf(0.18, float(lower_same) * 0.06)
	return clampf(value, 0.0, 1.0)

func _bot_choose_lead_card(legal: Array, target: int, remaining_after_play: int, must_chase: bool) -> Dictionary:
	var likely_winners := legal.filter(func(card): return _bot_lead_win_score(card) >= 0.62)
	var safe_losers := legal.filter(func(card): return _bot_lead_win_score(card) < 0.42)
	if must_chase:
		return _bot_pick_highest(likely_winners if not likely_winners.is_empty() else legal)
	if target <= 0:
		return _bot_pick_safest_lead(safe_losers if not safe_losers.is_empty() else legal)
	if target > remaining_after_play:
		return _bot_pick_highest(likely_winners if not likely_winners.is_empty() else legal)
	if not likely_winners.is_empty():
		return _bot_pick_lowest_winner(likely_winners)
	return _bot_pick_safest_lead(legal)

func _bot_choose_follow_card(legal: Array, target: int, remaining_after_play: int, wants_trick: bool, must_chase: bool) -> Dictionary:
	var winning := legal.filter(func(card): return _bot_beats_current_trick(card))
	var losing := legal.filter(func(card): return not _bot_beats_current_trick(card))
	var last_to_act := _players_after_active() == 0
	if must_chase:
		if winning.is_empty():
			return _bot_pick_discard(losing if not losing.is_empty() else legal)
		return _bot_pick_lowest_current_winner(winning) if last_to_act else _bot_pick_best_contested_winner(winning)
	if wants_trick:
		if winning.is_empty():
			return _bot_pick_discard(losing if not losing.is_empty() else legal)
		if target > remaining_after_play:
			return _bot_pick_best_contested_winner(winning)
		return _bot_pick_lowest_current_winner(winning)
	if not losing.is_empty():
		return _bot_pick_highest_loser(losing)
	return _bot_pick_lowest_current_winner(winning)

func _bot_pick_highest(cards: Array) -> Dictionary:
	cards.sort_custom(func(a, b): return _bot_card_absolute_power(a) > _bot_card_absolute_power(b))
	return _bot_pick_from_top(cards, 2)

func _bot_pick_lowest_winner(cards: Array) -> Dictionary:
	cards.sort_custom(func(a, b):
		var a_score := _bot_lead_win_score(a)
		var b_score := _bot_lead_win_score(b)
		if absf(a_score - b_score) > 0.08:
			return a_score < b_score
		return _bot_card_absolute_power(a) < _bot_card_absolute_power(b)
	)
	return _bot_pick_from_top(cards, 2)

func _bot_pick_safest_lead(cards: Array) -> Dictionary:
	cards.sort_custom(func(a, b):
		var a_score := _bot_lead_win_score(a)
		var b_score := _bot_lead_win_score(b)
		if absf(a_score - b_score) > 0.08:
			return a_score < b_score
		return _bot_card_absolute_power(a) < _bot_card_absolute_power(b)
	)
	return _bot_pick_from_top(cards, 2)

func _bot_pick_lowest_current_winner(cards: Array) -> Dictionary:
	cards.sort_custom(func(a, b): return _bot_card_absolute_power(a) < _bot_card_absolute_power(b))
	return _bot_pick_from_top(cards, 2)

func _bot_pick_best_contested_winner(cards: Array) -> Dictionary:
	cards.sort_custom(func(a, b):
		var a_risk := _bot_overtake_risk(a)
		var b_risk := _bot_overtake_risk(b)
		if absf(a_risk - b_risk) > 0.05:
			return a_risk < b_risk
		return _bot_card_absolute_power(a) < _bot_card_absolute_power(b)
	)
	return _bot_pick_from_top(cards, 2)

func _bot_pick_highest_loser(cards: Array) -> Dictionary:
	cards.sort_custom(func(a, b): return _bot_card_absolute_power(a) > _bot_card_absolute_power(b))
	return _bot_pick_from_top(cards, 2)

func _bot_pick_discard(cards: Array) -> Dictionary:
	cards.sort_custom(func(a, b):
		var a_safety := _bot_discard_priority(a)
		var b_safety := _bot_discard_priority(b)
		if a_safety != b_safety:
			return a_safety < b_safety
		return _bot_card_absolute_power(a) < _bot_card_absolute_power(b)
	)
	return _bot_pick_from_top(cards, 2)

func _bot_pick_from_top(cards: Array, spread: int) -> Dictionary:
	if cards.is_empty():
		return {}
	match _bot_personality():
		"casual":
			spread += 2
		"ruthless":
			spread = 1
	var limit: int = mini(cards.size() - 1, spread - 1)
	return cards[rng.randi_range(0, limit)]

func _bot_personality() -> String:
	var personality := str(state.get("bot_personality", Profile.bot_personality()))
	return personality if BOT_PERSONALITY_IDS.has(personality) else "smart"

func _bot_beats_current_trick(card: Dictionary) -> bool:
	if state["trick"].is_empty():
		return true
	var best: Dictionary = state["trick"][0]
	for play in state["trick"]:
		if GameRules.beats(play["card"], best["card"], state["led_suit"], state["trump"]):
			best = play
	return GameRules.beats(card, best["card"], state["led_suit"], state["trump"])

func _bot_lead_win_score(card: Dictionary) -> float:
	var threats := _bot_threat_count(card, state["hands"][int(state["active_player"])])
	var base := 1.0 - clampf(float(threats) / 5.0, 0.0, 0.95)
	if card["suit"] == state["trump"]:
		base += 0.18
	elif _bot_count_unseen_suit(state["trump"]) > 0:
		base -= 0.12
	base += float(int(card["rank"]) - 8) * 0.035
	return clampf(base, 0.0, 1.0)

func _bot_overtake_risk(card: Dictionary) -> float:
	var players_after := _players_after_active()
	if players_after <= 0:
		return 0.0
	var threats := _bot_threat_count(card, state["hands"][int(state["active_player"])])
	return clampf(float(threats * players_after) / 12.0, 0.0, 1.0)

func _bot_discard_priority(card: Dictionary) -> int:
	if state["led_suit"] != null and card["suit"] != state["led_suit"] and card["suit"] != state["trump"]:
		return 0
	if card["suit"] != state["trump"]:
		return 1
	return 2

func _bot_card_absolute_power(card: Dictionary) -> int:
	var power := int(card["rank"])
	if card["suit"] == state["trump"]:
		power += 100
	return power

func _bot_threat_count(card: Dictionary, own_hand: Array) -> int:
	var threats := 0
	for unseen in _bot_unseen_cards(own_hand):
		if GameRules.beats(unseen, card, str(card["suit"]), state["trump"]):
			threats += 1
	return threats

func _bot_count_unseen_suit(suit: String) -> int:
	var count := 0
	for card in _bot_unseen_cards(state["hands"][int(state["active_player"])]):
		if card["suit"] == suit:
			count += 1
	return count

func _bot_count_lower_owned_in_suit(card: Dictionary, hand: Array) -> int:
	var count := 0
	for owned in hand:
		if owned["suit"] == card["suit"] and int(owned["rank"]) < int(card["rank"]):
			count += 1
	return count

func _bot_unseen_cards(own_hand: Array) -> Array:
	var cards := GameRules.build_deck()
	var visible: Array = own_hand.duplicate(true)
	visible.append_array(state.get("played_cards", []))
	for play in state.get("trick", []):
		visible.append(play["card"])
	if state.get("trump_card", {}).has("suit"):
		visible.append(state["trump_card"])
	return cards.filter(func(card):
		for seen in visible:
			if GameRules.same_card(card, seen):
				return false
		return true
	)

func _players_after_active() -> int:
	return maxi(0, int(state["num_players"]) - int(state["trick"].size()) - 1)

func _record_round_history() -> void:
	if not state.has("round_history"):
		state["round_history"] = []
	var hit: Array = []
	for i in range(state["num_players"]):
		hit.append(int(state["bids"][i]) == int(state["tricks_won"][i]))
	state["round_history"].append({
		"round_index": state["round_index"],
		"bids": state["bids"].duplicate(true),
		"tricks_won": state["tricks_won"].duplicate(true),
		"hit": hit,
	})

func _end_game() -> void:
	var standings := _build_standings()
	var winners: Array = []
	var top_score := int(standings[0]["score"])
	for row in standings:
		if int(row["score"]) == top_score:
			winners.append(row["name"])
	var game_id := _make_game_id()
	state["phase"] = "game_end"
	state["active_player"] = -1
	state["trick"] = []
	state["led_suit"] = null
	state["play_again"] = _filled_array(state["num_players"], false)
	state["standings"] = standings
	state["winners"] = winners
	state["game_id"] = game_id
	state["message"] = "Everyone can vote to play again."
	_set_sound_event("game")
	_publish_state()
	_publish_game_results(game_id, winners)

func _build_standings() -> Array:
	var rows: Array = []
	for i in range(state["num_players"]):
		var made := 0
		var missed := 0
		var best_round := 0
		for round_summary in state.get("round_history", []):
			if round_summary["hit"][i]:
				made += 1
				best_round = maxi(best_round, 10 + int(round_summary["bids"][i]))
			else:
				missed += 1
		rows.append({
			"name": state["names"][i],
			"score": state["scores"][i],
			"made": made,
			"missed": missed,
			"best_round": best_round,
		})
	rows.sort_custom(func(a, b): return int(a["score"]) > int(b["score"]))
	var place := 0
	var shown_place := 0
	var last_score = null
	for row in rows:
		place += 1
		var score := int(row["score"])
		if last_score == null or score != int(last_score):
			shown_place = place
			last_score = score
		row["place"] = shown_place
	return rows

func _publish_game_results(game_id: String, winners: Array) -> void:
	for seat in range(state["num_players"]):
		if not state["connected"][seat] or _is_bot_seat(seat):
			continue
		var result := _game_result_for_seat(seat, game_id, winners)
		var peer_id := _peer_for_seat(seat)
		_receive_game_result.rpc_id(peer_id, result)

func _game_result_for_seat(seat: int, game_id: String, winners: Array) -> Dictionary:
	var bid_hits := 0
	var bid_misses := 0
	for round_summary in state.get("round_history", []):
		if round_summary["hit"][seat]:
			bid_hits += 1
		else:
			bid_misses += 1
	return {
		"game_id": game_id,
		"score": int(state["scores"][seat]),
		"won": winners.has(state["names"][seat]),
		"bid_hits": bid_hits,
		"bid_misses": bid_misses,
	}

@rpc("authority", "call_local", "reliable")
func _receive_game_result(result: Dictionary) -> void:
	var game_id := str(result.get("game_id", ""))
	if recorded_game_ids.has(game_id):
		return
	recorded_game_ids[game_id] = true
	Profile.record_game_result(
		int(result.get("score", 0)),
		bool(result.get("won", false)),
		int(result.get("bid_hits", 0)),
		int(result.get("bid_misses", 0))
	)
	_set_status(Profile.stats_line())

func _peer_for_seat(seat: int) -> int:
	if seat == 0 and not dedicated_server:
		return 1
	return int(seat_peers[seat])

func _seat_for_peer(peer_id: int) -> int:
	if peer_id == 1 and not dedicated_server:
		return 0
	return seat_peers.find(peer_id)

func _on_connected_to_server() -> void:
	_server_register_profile.rpc_id(1, Profile.public_profile())

func _on_connection_failed() -> void:
	_create_client_waiting_view()
	view_state["message"] = "Could not reach the server. Check the address, your internet, or try again."
	_render()

@rpc("any_peer", "reliable")
func _server_register_profile(profile: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	var seat := _seat_for_peer(peer_id)
	var profile_id := str(profile.get("id", ""))
	var reconnect_seat := _seat_for_profile_id(profile_id)
	if reconnect_seat < 0 and seat >= 0 and seat < state.get("profiles", []).size():
		var current_profile = state["profiles"][seat]
		if typeof(current_profile) == TYPE_DICTIONARY and not profile_id.is_empty() and str(current_profile.get("id", "")) == profile_id:
			reconnect_seat = seat
	if reconnect_seat >= 0 and reconnect_seat != seat:
		if seat >= 0 and seat < seat_peers.size():
			seat_peers[seat] = 0
		seat = reconnect_seat
		seat_peers[seat] = peer_id
		if state.has("bots"):
			state["bots"][seat] = false
	if seat < 0 or seat >= state["num_players"]:
		return
	var clean_name := str(profile.get("display_name", "")).strip_edges()
	if clean_name.is_empty():
		clean_name = "Player %d" % [seat + 1]
	state["names"][seat] = clean_name.substr(0, 18)
	state["profiles"][seat] = {
		"id": profile_id,
		"display_name": state["names"][seat],
		"animal": _clean_animal_id(str(profile.get("animal", "fox"))),
		"games_played": int(profile.get("games_played", 0)),
		"wins": int(profile.get("wins", 0)),
	}
	state["connected"] = _connected_seats()
	state["ready"] = _lobby_ready_seats()
	state["message"] = "%s rejoined seat %d." % [state["names"][seat], seat + 1] if reconnect_seat >= 0 else "%s joined seat %d." % [state["names"][seat], seat + 1]
	_publish_state()

func _request_toggle_ready() -> void:
	if multiplayer.multiplayer_peer and not multiplayer.is_server():
		_server_toggle_ready.rpc_id(1)
	else:
		_apply_toggle_ready(my_seat)

@rpc("any_peer", "reliable")
func _server_toggle_ready() -> void:
	if not multiplayer.is_server():
		return
	_apply_toggle_ready(_seat_for_peer(multiplayer.get_remote_sender_id()))

func _apply_toggle_ready(seat: int) -> void:
	if state.get("phase", "") != "lobby":
		return
	if seat < 0 or seat >= state["num_players"]:
		return
	if not state["connected"][seat]:
		return
	state["ready"][seat] = not state["ready"][seat]
	state["message"] = "%s is %s." % [state["names"][seat], "ready" if state["ready"][seat] else "not ready"]
	_publish_state()

func _request_start_game() -> void:
	if multiplayer.multiplayer_peer and not multiplayer.is_server():
		_server_start_game.rpc_id(1)
	else:
		_host_start_game()

@rpc("any_peer", "reliable")
func _server_start_game() -> void:
	if not multiplayer.is_server():
		return
	var sender_seat := _seat_for_peer(multiplayer.get_remote_sender_id())
	if dedicated_server and sender_seat != _first_connected_human_seat():
		return
	_host_start_game()

func _host_start_game() -> void:
	if not multiplayer.is_server():
		return
	if state.get("phase", "") != "lobby":
		return
	if not _lobby_can_start():
		state["message"] = "Connected players must be ready before starting."
		_publish_state()
		return
	_fill_empty_seats_with_bots()
	Net.stop_discovery()
	_start_match(state["names"].duplicate(true), state["max_cards"])

func _first_connected_human_seat() -> int:
	if state.is_empty():
		return -1
	for seat in range(state["num_players"]):
		if seat < seat_peers.size() and int(seat_peers[seat]) != 0 and not _is_bot_seat(seat):
			return seat
	return -1

func _seat_for_profile_id(profile_id: String) -> int:
	if profile_id.is_empty() or not state.has("profiles"):
		return -1
	for seat in range(min(state["profiles"].size(), seat_peers.size())):
		if int(seat_peers[seat]) != 0:
			continue
		if _is_bot_seat(seat):
			continue
		var profile = state["profiles"][seat]
		if typeof(profile) == TYPE_DICTIONARY and str(profile.get("id", "")) == profile_id:
			return seat
	return -1

func _fill_empty_seats_with_bots() -> void:
	var bots: Array = state.get("bots", _filled_array(state["num_players"], false))
	bots.resize(state["num_players"])
	for seat in range(state["num_players"]):
		if int(seat_peers[seat]) == 0:
			bots[seat] = true
			state["names"][seat] = "Bot %d" % seat
			state["profiles"][seat] = {
				"id": "bot-%d" % seat,
				"display_name": state["names"][seat],
				"animal": ANIMAL_IDS[seat % ANIMAL_IDS.size()],
				"games_played": 0,
				"wins": 0,
			}
		else:
			bots[seat] = false
	state["bots"] = bots
	state["connected"] = _connected_seats()
	state["ready"] = _lobby_ready_seats()

func _can_request_end_game() -> bool:
	if view_state.is_empty():
		return false
	if not (view_state.get("phase", "") in ["bidding", "playing", "trick_end", "round_end"]):
		return false
	if multiplayer.multiplayer_peer and multiplayer.is_server() and not dedicated_server:
		return true
	return my_seat == _table_host_seat_from_view()

func _sync_end_game_button() -> void:
	if not end_game_button:
		return
	var confirming := Time.get_ticks_msec() < end_game_confirm_until
	end_game_button.text = "Confirm End" if confirming else "End Game"

func _request_end_game() -> void:
	var now := Time.get_ticks_msec()
	if now >= end_game_confirm_until:
		end_game_confirm_until = now + 2800
		_sync_end_game_button()
		_set_status("Press Confirm End to stop this game.")
		_play_sfx("click")
		return
	end_game_confirm_until = 0
	_sync_end_game_button()
	if multiplayer.multiplayer_peer and not multiplayer.is_server():
		_server_end_game.rpc_id(1)
	else:
		_apply_end_game_request(my_seat)

@rpc("any_peer", "reliable")
func _server_end_game() -> void:
	if not multiplayer.is_server():
		return
	_apply_end_game_request(_seat_for_peer(multiplayer.get_remote_sender_id()))

func _apply_end_game_request(seat: int) -> void:
	if not (state.get("phase", "") in ["bidding", "playing", "trick_end", "round_end"]):
		return
	if dedicated_server and seat != _first_connected_human_seat():
		return
	if not dedicated_server and seat != 0:
		return
	_return_to_lobby("Game ended by table host. Ready up to start again.")

func _request_play_again() -> void:
	if multiplayer.multiplayer_peer and not multiplayer.is_server():
		_server_play_again.rpc_id(1)
	else:
		_apply_play_again(my_seat)

@rpc("any_peer", "reliable")
func _server_play_again() -> void:
	if not multiplayer.is_server():
		return
	_apply_play_again(_seat_for_peer(multiplayer.get_remote_sender_id()))

func _apply_play_again(seat: int) -> void:
	if state.get("phase", "") != "game_end":
		return
	if seat < 0 or seat >= state["num_players"]:
		return
	state["play_again"][seat] = true
	if _all_play_again_votes_in():
		_return_to_lobby_after_game()
	else:
		state["message"] = "Waiting for everyone to choose Play Again."
		_publish_state()

func _all_play_again_votes_in() -> bool:
	for seat in range(state["num_players"]):
		if state["connected"][seat] and not _is_bot_seat(seat) and not state["play_again"][seat]:
			return false
	return true

func _return_to_lobby_after_game() -> void:
	_return_to_lobby("Back in lobby. Ready up for another game.")

func _return_to_lobby(message: String) -> void:
	lobby_player_count = state["num_players"]
	lobby_max_cards = state["max_cards"]
	lobby_map_index = _map_index_for_id(str(state.get("map_id", _selected_map_id())))
	var names: Array = state["names"].duplicate(true)
	var profiles: Array = state["profiles"].duplicate(true)
	var bot_personality := str(state.get("bot_personality", Profile.bot_personality()))
	state = {
		"phase": "lobby",
		"map_id": _selected_map_id(),
		"names": names,
		"profiles": profiles,
		"num_players": lobby_player_count,
		"max_cards": lobby_max_cards,
		"sequence": GameRules.down_up_sequence(lobby_max_cards),
		"round_index": 0,
		"dealer": lobby_player_count - 1,
		"scores": _filled_array(lobby_player_count, 0),
		"hands": _empty_hands(lobby_player_count),
		"bids": _filled_array(lobby_player_count, null),
		"bid_submitted": _filled_array(lobby_player_count, false),
		"tricks_won": _filled_array(lobby_player_count, 0),
		"trump": "",
		"trump_card": {},
		"trick": [],
		"led_suit": null,
		"leader": 0,
		"active_player": -1,
		"connected": _connected_seats(),
		"bots": state.get("bots", _filled_array(lobby_player_count, false)).duplicate(true),
		"lobby_avatars": _default_lobby_avatars(lobby_player_count),
		"bot_personality": bot_personality,
		"ready": _filled_array(lobby_player_count, false),
		"play_again": _filled_array(lobby_player_count, false),
		"standings": [],
		"winners": [],
		"round_history": [],
		"sound_event": {},
		"emote_event": {},
		"message": message,
	}
	_publish_state()
	if multiplayer.multiplayer_peer and multiplayer.is_server():
		Net.start_advertising(_discovery_info())

func _on_peer_connected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	var seat := _first_open_seat()
	if seat == -1:
		return
	seat_peers[seat] = peer_id
	if state.has("bots"):
		state["bots"][seat] = false
	state["connected"] = _connected_seats()
	state["ready"] = _lobby_ready_seats()
	state["message"] = "Seat %d joined." % [seat + 1]
	if dedicated_server:
		print("Peer %d joined seat %d" % [peer_id, seat + 1])
	_publish_state()
	Net.update_advertisement(_discovery_info())

func _on_peer_disconnected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	var seat := seat_peers.find(peer_id)
	if seat == -1:
		return
	seat_peers[seat] = 0
	state["connected"] = _connected_seats()
	state["ready"] = _lobby_ready_seats()
	if state.has("play_again") and seat < state["play_again"].size():
		state["play_again"][seat] = false
	state["message"] = "Seat %d disconnected." % [seat + 1]
	if dedicated_server:
		print("Peer %d disconnected from seat %d" % [peer_id, seat + 1])
	_publish_state()
	Net.update_advertisement(_discovery_info())

func _first_open_seat() -> int:
	var first_seat := 0 if dedicated_server else 1
	for seat in range(first_seat, seat_peers.size()):
		if int(seat_peers[seat]) == 0:
			return seat
	return -1

func _new_seat_peers(count: int) -> Array:
	var peers: Array = []
	for seat in range(count):
		peers.append(1 if seat == 0 and not dedicated_server else 0)
	return peers

func _default_names(count: int) -> Array:
	var names: Array = []
	for i in range(count):
		if i < STARTING_NAMES.size():
			names.append(STARTING_NAMES[i])
		else:
			names.append("Player %d" % [i + 1])
	return names

func _default_profiles(count: int) -> Array:
	var profiles: Array = []
	for i in range(count):
		profiles.append({
			"id": "",
			"display_name": "Player %d" % [i + 1],
			"animal": ANIMAL_IDS[i % ANIMAL_IDS.size()],
			"games_played": 0,
			"wins": 0,
		})
	return profiles

func _clean_animal_id(value: String) -> String:
	return value if ANIMAL_IDS.has(value) else "fox"

func _make_game_id() -> String:
	return "%s-%d" % [Profile.profile_id(), Time.get_unix_time_from_system()]

func _filled_array(count: int, value) -> Array:
	var values: Array = []
	for _i in range(count):
		values.append(value)
	return values

func _default_lobby_avatars(count: int) -> Array:
	var avatars: Array = []
	var columns := 5
	for seat in range(count):
		avatars.append({
			"x": -2.8 + float(seat % columns) * 1.4,
			"z": 2.75 - float(seat / columns) * 1.05,
			"yaw": 0.0,
		})
	return avatars

func _empty_hands(count: int) -> Array:
	var hands: Array = []
	for _i in range(count):
		hands.append([])
	return hands

func _connected_seats() -> Array:
	var connected := []
	for seat in range(seat_peers.size()):
		connected.append(int(seat_peers[seat]) != 0 or _is_bot_seat(seat))
	return connected

func _lobby_ready_seats() -> Array:
	var ready: Array = []
	for seat in range(seat_peers.size()):
		var is_connected := int(seat_peers[seat]) != 0 or _is_bot_seat(seat)
		var existing_ready := false
		if _is_bot_seat(seat):
			existing_ready = true
		if state.has("ready") and seat < state["ready"].size():
			existing_ready = existing_ready or state["ready"][seat]
		ready.append(is_connected and existing_ready)
	return ready

func _lobby_can_start() -> bool:
	if state.get("phase", "") != "lobby":
		return false
	var human_count := 0
	for seat in range(state["num_players"]):
		if int(seat_peers[seat]) == 0:
			continue
		human_count += 1
		if not state["ready"][seat]:
			return false
	return human_count > 0

func _is_bot_seat(seat: int) -> bool:
	if state.has("bots") and seat >= 0 and seat < state["bots"].size():
		return bool(state["bots"][seat])
	return false

func _connected_count() -> int:
	var count := 0
	for connected in _connected_seats():
		if connected:
			count += 1
	return count

func _set_status(message: String) -> void:
	status_label.text = message
