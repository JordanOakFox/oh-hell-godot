extends Control

const STARTING_NAMES := ["Player 1", "Player 2", "Player 3", "Player 4"]
const DEFAULT_MAX_CARDS := 7
const DEFAULT_PLAYERS := 4
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
var lobby_map_index := 0
var local_player_name := "Player"
var local_profile_id := ""
var recorded_game_ids := {}
var rng := RandomNumberGenerator.new()
var last_hand_signature := ""
var last_shuffle_round_key := ""
var bot_action_key := ""
var hovered_3d_card_index := -1
var dedicated_server := false

var title_label: Label
var status_label: Label
var table_label: Label
var left_stats_label: Label
var net_row: HBoxContainer
var settings_row: HBoxContainer
var map_row: HBoxContainer
var map_name_label: Label
var right_info_panel: VBoxContainer
var right_info_label: Label
var trump_symbol_label: Label
var trump_name_label: Label
var seat_info_label: Label
var trick_box: HBoxContainer
var hand_box: Control
var action_box: HBoxContainer
var address_input: LineEdit
var name_input: LineEdit
var player_count_spin: SpinBox
var max_cards_spin: SpinBox
var discovered_game_picker: OptionButton
var discovered_games: Array = []
var fireworks_overlay: Control
var table_view_3d: Control

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

func _input(event: InputEvent) -> void:
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

	if event is InputEventMouseMotion:
		_set_3d_card_hover(_legal_3d_card_index_at(event.position))
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var index := _legal_3d_card_index_at(event.position)
		if index >= 0 and index < local_hand.size():
			_set_3d_card_hover(-1)
			_submit_card(local_hand[index])

func _build_ui() -> void:
	table_view_3d = TableView3DScript.new()
	table_view_3d.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(table_view_3d)

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

	net_row = HBoxContainer.new()
	net_row.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(net_row)

	name_input = LineEdit.new()
	name_input.text = local_player_name
	name_input.placeholder_text = "Your name"
	name_input.custom_minimum_size = Vector2(160, 0)
	name_input.text_changed.connect(_on_name_changed)
	net_row.add_child(name_input)

	var host_button := Button.new()
	host_button.text = "Host"
	host_button.pressed.connect(_on_host_pressed)
	net_row.add_child(host_button)

	address_input = LineEdit.new()
	address_input.text = "127.0.0.1"
	address_input.placeholder_text = "Host IP"
	address_input.custom_minimum_size = Vector2(160, 0)
	net_row.add_child(address_input)

	var join_button := Button.new()
	join_button.text = "Join"
	join_button.pressed.connect(_on_join_pressed)
	net_row.add_child(join_button)

	discovered_game_picker = OptionButton.new()
	discovered_game_picker.custom_minimum_size = Vector2(220, 0)
	discovered_game_picker.add_item("Scanning for games...")
	net_row.add_child(discovered_game_picker)

	var join_found_button := Button.new()
	join_found_button.text = "Join Found"
	join_found_button.pressed.connect(_on_join_found_pressed)
	net_row.add_child(join_found_button)

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

	left_stats_label = Label.new()
	left_stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left_stats_label.add_theme_font_size_override("font_size", 15)
	left_stats_label.add_theme_color_override("font_color", Color("#f7f1e3"))
	left_stats_label.add_theme_color_override("font_shadow_color", Color("#17110c"))
	left_stats_label.add_theme_constant_override("shadow_offset_x", 2)
	left_stats_label.add_theme_constant_override("shadow_offset_y", 2)
	left_stats_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	left_stats_label.offset_left = 18
	left_stats_label.offset_top = -82
	left_stats_label.offset_right = 258
	left_stats_label.offset_bottom = -18
	left_stats_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left_stats_label.visible = false
	add_child(left_stats_label)

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

	right_info_panel = VBoxContainer.new()
	right_info_panel.custom_minimum_size = Vector2(240, 0)
	right_info_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_info_panel.add_theme_constant_override("separation", 12)
	play_row.add_child(right_info_panel)

	right_info_label = Label.new()
	right_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right_info_label.add_theme_font_size_override("font_size", 16)
	right_info_label.add_theme_color_override("font_color", Color("#f7f1e3"))
	right_info_panel.add_child(right_info_label)

	trump_symbol_label = Label.new()
	trump_symbol_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	trump_symbol_label.add_theme_font_size_override("font_size", 76)
	trump_symbol_label.custom_minimum_size = Vector2(0, 84)
	right_info_panel.add_child(trump_symbol_label)

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

func _on_host_pressed() -> void:
	_read_lobby_inputs()
	var err := Net.host()
	if err != OK:
		_set_status("Host failed: %s" % error_string(err))
		return
	my_seat = 0
	seat_peers = _new_seat_peers(lobby_player_count)
	_create_lobby("Hosting. Waiting for players...")
	Net.start_advertising(_discovery_info())

func _start_dedicated_server() -> void:
	dedicated_server = true
	lobby_player_count = _command_line_int("--players", DEFAULT_PLAYERS, 2, 10)
	lobby_max_cards = _command_line_int("--cards", DEFAULT_MAX_CARDS, 1, GameRules.max_allowed_cards(lobby_player_count))
	var map_arg := _command_line_value("--map")
	if not map_arg.is_empty():
		lobby_map_index = _map_index_for_id(map_arg)
	local_player_name = "Dedicated Server"
	var err := Net.host()
	if err != OK:
		push_error("Dedicated server failed: %s" % error_string(err))
		get_tree().quit(1)
		return
	my_seat = -1
	seat_peers = _new_seat_peers(lobby_player_count)
	_create_lobby("Dedicated server online. Players can join.")
	Net.start_advertising(_discovery_info())
	print("Oh Hell dedicated server listening on port %d" % Net.DEFAULT_PORT)

func _on_join_pressed() -> void:
	_read_lobby_inputs()
	var address := address_input.text.strip_edges()
	if address.is_empty():
		address = "127.0.0.1"
	var err := Net.join(address)
	if err != OK:
		_set_status("Join failed: %s" % error_string(err))
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

func _create_offline_lobby() -> void:
	my_seat = 0
	seat_peers = _new_seat_peers(lobby_player_count)
	_create_lobby("Offline preview. Host a game or join a host.")
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
		"trick": [],
		"led_suit": null,
		"leader": 0,
		"active_player": -1,
		"connected": _filled_array(lobby_player_count, false),
		"bots": _filled_array(lobby_player_count, false),
		"ready": _filled_array(lobby_player_count, false),
		"play_again": _filled_array(lobby_player_count, false),
		"standings": [],
		"winners": [],
		"round_history": [],
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
		"trick": [],
		"led_suit": null,
		"leader": 0,
		"active_player": -1,
		"connected": _connected_seats(),
		"bots": _filled_array(lobby_player_count, false),
		"ready": _lobby_ready_seats(),
		"play_again": _filled_array(lobby_player_count, false),
		"standings": [],
		"winners": [],
		"round_history": [],
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
		"trick": [],
		"led_suit": null,
		"leader": 0,
		"active_player": -1,
		"connected": _connected_seats(),
		"bots": state.get("bots", _filled_array(names.size(), false)).duplicate(true),
		"ready": _lobby_ready_seats(),
		"play_again": _filled_array(names.size(), false),
		"standings": [],
		"winners": [],
		"round_history": [],
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
	state["led_suit"] = null
	state["leader"] = (state["dealer"] + 1) % state["num_players"]
	state["active_player"] = -1
	state["phase"] = "bidding"
	state["message"] = "Choose your secret bid."
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
	if not multiplayer.multiplayer_peer or not multiplayer.is_server():
		state = public_state
	local_hand = hand
	my_seat = seat
	_render()

func _public_state() -> Dictionary:
	var public := state.duplicate(true)
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
	if map_name_label:
		map_name_label.text = _selected_map_name()
	var active_game: bool = view_state.get("phase", "") in ["bidding", "playing", "trick_end", "round_end"]
	if title_label:
		title_label.visible = view_state.get("phase", "") in ["connecting", "lobby", "game_end"]
	if net_row:
		net_row.visible = not active_game
	if settings_row:
		settings_row.visible = not active_game
	if map_row:
		map_row.visible = not active_game
	if status_label:
		status_label.visible = not active_game
	if table_view_3d:
		table_view_3d.set_table_state(view_state, my_seat)
		table_view_3d.set_player_hand(local_hand)
	if fireworks_overlay:
		fireworks_overlay.set_celebrating(view_state.get("phase", "") == "game_end")
	if view_state["phase"] == "connecting":
		table_label.add_theme_font_size_override("font_size", 18)
		trick_box.visible = true
		hand_box.visible = true
		left_stats_label.visible = false
		right_info_panel.visible = false
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
		left_stats_label.visible = false
		right_info_panel.visible = false
		left_stats_label.text = ""
		right_info_label.text = ""
		_render_lobby()
		return
	if view_state["phase"] == "game_end":
		table_label.add_theme_font_size_override("font_size", 18)
		trick_box.visible = true
		hand_box.visible = true
		left_stats_label.visible = false
		right_info_panel.visible = false
		_render_game_end()
		return

	trick_box.visible = true
	hand_box.visible = true
	left_stats_label.visible = true
	right_info_panel.visible = true
	table_label.add_theme_font_size_override("font_size", 18)
	var round_size: int = view_state["sequence"][view_state["round_index"]]
	right_info_label.text = "Round %d / %d\nCards: %d\n\nTrump" % [
		view_state["round_index"] + 1,
		view_state["sequence"].size(),
		round_size,
	]
	seat_info_label.text = "\nYou are seat %d\n%s" % [
		my_seat + 1,
		view_state["names"][my_seat],
	]
	_render_trump_symbol()
	var my_bid_text := "?"
	if view_state["phase"] == "bidding":
		my_bid_text = "in" if view_state["bid_submitted"][my_seat] else "..."
	elif view_state["bids"][my_seat] != null:
		my_bid_text = str(view_state["bids"][my_seat])
	left_stats_label.text = "You: %d pts\nBid %s | Tricks %d" % [
		view_state["scores"][my_seat],
		my_bid_text,
		view_state["tricks_won"][my_seat],
	]
	table_label.text = view_state["message"]

	_render_trick()
	_render_actions()
	_render_hand()

func _render_game_end() -> void:
	var winner_text := "Game Over"
	if view_state["winners"].size() == 1:
		winner_text = "%s Wins!" % view_state["winners"][0]
	elif view_state["winners"].size() > 1:
		winner_text = "%s Tie!" % ", ".join(view_state["winners"])

	var text := "%s\n\nFinal Standings\n" % winner_text
	for row in view_state["standings"]:
		text += "%d. %s - %d\n" % [int(row["place"]), row["name"], int(row["score"])]
	text += "\n%s" % view_state["message"]
	left_stats_label.text = ""
	right_info_label.text = ""
	table_label.text = text
	_render_trick()
	_render_actions()
	_render_hand()

func _render_trump_symbol() -> void:
	var trump := str(view_state.get("trump", ""))
	trump_symbol_label.text = SUIT_SYMBOLS.get(trump, trump)
	trump_symbol_label.add_theme_color_override("font_color", SUIT_COLORS.get(trump, Color("#f7f1e3")))
	var trump_name: String = GameRules.SUIT_NAMES.get(trump, trump)
	trump_name_label.text = trump_name
	trump_name_label.add_theme_color_override("font_color", SUIT_COLORS.get(trump, Color("#f7f1e3")))
	trump_symbol_label.tooltip_text = trump_name

func _discovery_info() -> Dictionary:
	var connected_count := _connected_count()
	if state.is_empty() or state.get("phase", "") != "lobby":
		connected_count = 0
	return {
		"name": "%s's table" % local_player_name,
		"players": connected_count,
		"max_players": lobby_player_count,
		"max_cards": lobby_max_cards,
		"map_id": _selected_map_id(),
		"map_name": _selected_map_name(),
		"phase": state.get("phase", "lobby"),
	}

func _render_lobby() -> void:
	left_stats_label.text = ""
	right_info_label.text = ""
	table_label.add_theme_font_size_override("font_size", 16)
	var text := "Multiplayer Lobby\n"
	text += "%d players | %d max cards | %s\n" % [
		view_state["num_players"],
		view_state["max_cards"],
		MAP_NAMES.get(str(view_state.get("map_id", _selected_map_id())), _selected_map_name()),
	]
	text += "You are seat %d: %s\n" % [my_seat + 1, view_state["names"][my_seat]]
	if multiplayer.multiplayer_peer and multiplayer.is_server():
		var addresses := Net.local_join_addresses()
		if addresses.is_empty():
			text += "Join: local network IP not found\n"
		else:
			text += "Join: %s\n" % ", ".join(addresses)
	var seat_parts: Array = []
	for i in range(view_state["num_players"]):
		var status := "waiting"
		if view_state.has("bots") and view_state["bots"][i]:
			status = "bot"
		elif view_state["connected"][i]:
			status = "ready" if view_state["ready"][i] else "not ready"
		seat_parts.append("%d %s: %s" % [i + 1, view_state["names"][i], status])
	text += "Seats: %s\n" % " | ".join(seat_parts)
	text += view_state["message"]
	table_label.text = text
	_render_trick()
	_render_actions()
	_render_hand()

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
			ready_button.pressed.connect(_request_toggle_ready)
			action_box.add_child(ready_button)

		if multiplayer.multiplayer_peer and (multiplayer.is_server() or _view_can_request_start()):
			var start_button := Button.new()
			start_button.text = "Start Game"
			start_button.disabled = not _view_lobby_can_start()
			start_button.pressed.connect(_request_start_game)
			action_box.add_child(start_button)

		var waiting := Label.new()
		waiting.text = "Players: %d / %d" % [connected_count, view_state["num_players"]]
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
		next_round.pressed.connect(_request_next_round)
		action_box.add_child(next_round)
	elif view_state["phase"] == "game_end":
		var play_again := Button.new()
		play_again.text = "Waiting..." if view_state["play_again"][my_seat] else "Play Again"
		play_again.disabled = view_state["play_again"][my_seat]
		play_again.pressed.connect(_request_play_again)
		action_box.add_child(play_again)

		var waiting := Label.new()
		waiting.text = "Play again: %d / %d" % [_play_again_count(), view_state["num_players"]]
		waiting.add_theme_color_override("font_color", Color("#f7f1e3"))
		action_box.add_child(waiting)

	if _can_host_stop_game():
		var stop_button := Button.new()
		stop_button.text = "Stop Game"
		stop_button.pressed.connect(_host_stop_game)
		action_box.add_child(stop_button)

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
	for control in [action_box, name_input, address_input, player_count_spin, max_cards_spin, discovered_game_picker]:
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

func _play_again_count() -> int:
	if not view_state.has("play_again"):
		return 0
	var count := 0
	for voted in view_state["play_again"]:
		if voted:
			count += 1
	return count

func _selected_map_id() -> String:
	return MAP_IDS[lobby_map_index % MAP_IDS.size()]

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
	if multiplayer.multiplayer_peer and not multiplayer.is_server():
		_set_status("Host chooses the map.")
		return
	lobby_map_index = posmod(lobby_map_index + direction, MAP_IDS.size())
	if map_name_label:
		map_name_label.text = _selected_map_name()
	if state.has("map_id") and state.get("phase", "") == "lobby":
		state["map_id"] = _selected_map_id()
		_publish_state()
		if multiplayer.multiplayer_peer and multiplayer.is_server():
			Net.update_advertisement(_discovery_info())
	elif not multiplayer.multiplayer_peer:
		_create_offline_lobby()

func _read_lobby_inputs() -> void:
	local_player_name = name_input.text.strip_edges()
	if local_player_name.is_empty():
		local_player_name = "Player"
	Profile.set_display_name(local_player_name)
	local_player_name = Profile.display_name()
	lobby_player_count = int(player_count_spin.value)
	lobby_max_cards = int(max_cards_spin.value)
	lobby_max_cards = clampi(lobby_max_cards, 1, GameRules.max_allowed_cards(lobby_player_count))

func _on_name_changed(new_text: String) -> void:
	local_player_name = new_text.strip_edges()
	if local_player_name.is_empty():
		local_player_name = "Player"
	Profile.set_display_name(local_player_name)
	local_player_name = Profile.display_name()
	if multiplayer.multiplayer_peer and multiplayer.is_server() and state.get("phase", "") == "lobby":
		state["names"][0] = local_player_name
		state["profiles"][0] = Profile.public_profile()
		_publish_state()

func _on_player_count_changed(value: float) -> void:
	lobby_player_count = int(value)
	var allowed := GameRules.max_allowed_cards(lobby_player_count)
	max_cards_spin.max_value = allowed
	if max_cards_spin.value > allowed:
		max_cards_spin.value = allowed
	lobby_max_cards = int(max_cards_spin.value)
	if multiplayer.multiplayer_peer and multiplayer.is_server() and state.get("phase", "") == "lobby":
		_resize_host_lobby(lobby_player_count, lobby_max_cards)
	elif not multiplayer.multiplayer_peer:
		_create_offline_lobby()

func _on_max_cards_changed(value: float) -> void:
	lobby_max_cards = int(value)
	if multiplayer.multiplayer_peer and multiplayer.is_server() and state.get("phase", "") == "lobby":
		_resize_host_lobby(lobby_player_count, lobby_max_cards)
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
	var old_peers: Array = seat_peers.duplicate(true)
	seat_peers = _new_seat_peers(player_count)

	for seat in range(1, player_count):
		if seat < old_peers.size():
			seat_peers[seat] = old_peers[seat]

	state["num_players"] = player_count
	state["max_cards"] = max_cards
	state["sequence"] = GameRules.down_up_sequence(max_cards)
	state["names"] = _default_names(player_count)
	state["profiles"] = _default_profiles(player_count)
	state["bots"] = _filled_array(player_count, false)
	state["ready"] = _filled_array(player_count, false)
	for seat in range(player_count):
		if seat < old_names.size():
			state["names"][seat] = old_names[seat]
		if seat < old_profiles.size():
			state["profiles"][seat] = old_profiles[seat]
		if seat < old_bots.size() and int(seat_peers[seat]) == 0:
			state["bots"][seat] = old_bots[seat]
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
	address_input.text = str(game.get("address", ""))
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
	else:
		state["message"] = _bidding_message()
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

	if state["trick"].size() == state["num_players"]:
		var winner := GameRules.trick_winner(state["trick"], state["led_suit"], state["trump"])
		state["leader"] = winner
		state["active_player"] = winner
		state["phase"] = "trick_end"
		state["message"] = "%s wins the trick and leads next." % state["names"][winner]
		_publish_state()
		_schedule_auto_continue_after_trick(state["round_index"], winner)
		return
	else:
		state["active_player"] = (seat + 1) % state["num_players"]
		state["message"] = "%s, play a card." % state["names"][state["active_player"]]
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
	else:
		state["phase"] = "playing"
		state["active_player"] = state["leader"]
		state["message"] = "%s leads." % state["names"][state["leader"]]
	_publish_state()
	_schedule_bot_action()

func _request_next_round() -> void:
	if multiplayer.multiplayer_peer and not multiplayer.is_server():
		_server_next_round.rpc_id(1)
	else:
		_next_round()

@rpc("any_peer", "reliable")
func _server_next_round() -> void:
	_next_round()

func _next_round() -> void:
	state["round_index"] += 1
	state["dealer"] = (state["dealer"] + 1) % state["num_players"]
	if state["round_index"] >= state["sequence"].size():
		_end_game()
		return
	_begin_round()

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
	var key := "bid:%d:%d" % [int(state["round_index"]), seat]
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
	var key := "card:%d:%d:%d" % [int(state["round_index"]), state["trick"].size(), seat]
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
	var likely_tricks := 0
	for card in hand:
		var rank := int(card["rank"])
		if card["suit"] == state["trump"] and rank >= 10:
			likely_tricks += 1
		elif rank >= 13:
			likely_tricks += 1
		elif rank >= 11 and rng.randf() < 0.35:
			likely_tricks += 1
	if round_size > 1 and rng.randf() < 0.22:
		likely_tricks += rng.randi_range(-1, 1)
	return clampi(likely_tricks, 0, round_size)

func _bot_choose_card(seat: int) -> Dictionary:
	var legal: Array = GameRules.legal_cards(state["hands"][seat], state["led_suit"])
	if legal.is_empty():
		return state["hands"][seat][0]
	var wants_tricks := int(state["tricks_won"][seat]) < int(state["bids"][seat])
	legal.sort_custom(func(a, b):
		var a_power := _bot_card_power(a)
		var b_power := _bot_card_power(b)
		return a_power > b_power if wants_tricks else a_power < b_power
	)
	var limit = mini(legal.size() - 1, 1)
	return legal[rng.randi_range(0, limit)]

func _bot_card_power(card: Dictionary) -> int:
	var power := int(card["rank"])
	if card["suit"] == state["trump"]:
		power += 20
	elif state["led_suit"] != null and card["suit"] == state["led_suit"]:
		power += 8
	return power

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
	_publish_state()
	_publish_game_results(game_id, winners)

func _build_standings() -> Array:
	var rows: Array = []
	for i in range(state["num_players"]):
		rows.append({"name": state["names"][i], "score": state["scores"][i]})
	rows.sort_custom(func(a, b): return int(a["score"]) > int(b["score"]))
	var place := 1
	for row in rows:
		row["place"] = place
		place += 1
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
	view_state["message"] = "Connection failed."
	_render()

@rpc("any_peer", "reliable")
func _server_register_profile(profile: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	var seat := _seat_for_peer(peer_id)
	if seat < 0 or seat >= state["num_players"]:
		return
	var clean_name := str(profile.get("display_name", "")).strip_edges()
	if clean_name.is_empty():
		clean_name = "Player %d" % [seat + 1]
	state["names"][seat] = clean_name.substr(0, 18)
	state["profiles"][seat] = {
		"id": str(profile.get("id", "")),
		"display_name": state["names"][seat],
		"games_played": int(profile.get("games_played", 0)),
		"wins": int(profile.get("wins", 0)),
	}
	state["message"] = "%s joined seat %d." % [state["names"][seat], seat + 1]
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
				"games_played": 0,
				"wins": 0,
			}
		else:
			bots[seat] = false
	state["bots"] = bots
	state["connected"] = _connected_seats()
	state["ready"] = _lobby_ready_seats()

func _can_host_stop_game() -> bool:
	if not multiplayer.multiplayer_peer or not multiplayer.is_server():
		return false
	return view_state.get("phase", "") in ["bidding", "playing", "trick_end", "round_end"]

func _host_stop_game() -> void:
	if not multiplayer.is_server():
		return
	if not (state.get("phase", "") in ["bidding", "playing", "trick_end", "round_end"]):
		return
	_return_to_lobby("Game stopped by host. Ready up to start again.")

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
		"trick": [],
		"led_suit": null,
		"leader": 0,
		"active_player": -1,
		"connected": _connected_seats(),
		"bots": state.get("bots", _filled_array(lobby_player_count, false)).duplicate(true),
		"ready": _filled_array(lobby_player_count, false),
		"play_again": _filled_array(lobby_player_count, false),
		"standings": [],
		"winners": [],
		"round_history": [],
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
			"games_played": 0,
			"wins": 0,
		})
	return profiles

func _make_game_id() -> String:
	return "%s-%d" % [Profile.profile_id(), Time.get_unix_time_from_system()]

func _filled_array(count: int, value) -> Array:
	var values: Array = []
	for _i in range(count):
		values.append(value)
	return values

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
