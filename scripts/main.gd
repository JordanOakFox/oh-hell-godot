extends Control

const STARTING_NAMES := ["Player 1", "Player 2", "Player 3", "Player 4"]
const DEFAULT_MAX_CARDS := 7
const DEFAULT_PLAYERS := 4

const CardButtonScript := preload("res://scripts/card_button.gd")
const FeltBackgroundScript := preload("res://scripts/felt_background.gd")

var state: Dictionary = {}
var view_state: Dictionary = {}
var local_hand: Array = []
var my_seat := 0
var seat_peers: Array = []
var lobby_player_count := DEFAULT_PLAYERS
var lobby_max_cards := DEFAULT_MAX_CARDS
var local_player_name := "Player 1"
var rng := RandomNumberGenerator.new()

var status_label: Label
var table_label: Label
var trick_box: HBoxContainer
var hand_box: HBoxContainer
var action_box: HBoxContainer
var address_input: LineEdit
var name_input: LineEdit
var player_count_spin: SpinBox
var max_cards_spin: SpinBox

func _ready() -> void:
	rng.randomize()
	_build_ui()
	Net.connection_changed.connect(_set_status)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	_create_offline_lobby()
	_apply_command_line_mode()

func _build_ui() -> void:
	var background = FeltBackgroundScript.new()
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 12)
	root.offset_left = 24
	root.offset_top = 18
	root.offset_right = -24
	root.offset_bottom = -18
	add_child(root)

	var title := Label.new()
	title.text = "Oh Hell"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 42)
	title.add_theme_color_override("font_color", Color("#f0d28a"))
	root.add_child(title)

	var net_row := HBoxContainer.new()
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

	var settings_row := HBoxContainer.new()
	settings_row.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(settings_row)

	var players_label := Label.new()
	players_label.text = "Players"
	players_label.add_theme_color_override("font_color", Color("#f7f1e3"))
	settings_row.add_child(players_label)

	player_count_spin = SpinBox.new()
	player_count_spin.min_value = 3
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

	status_label = Label.new()
	status_label.text = "Offline local preview"
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_color_override("font_color", Color("#f7f1e3"))
	root.add_child(status_label)

	table_label = Label.new()
	table_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	table_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	table_label.add_theme_font_size_override("font_size", 18)
	table_label.add_theme_color_override("font_color", Color("#f7f1e3"))
	table_label.custom_minimum_size = Vector2(0, 148)
	root.add_child(table_label)

	trick_box = HBoxContainer.new()
	trick_box.alignment = BoxContainer.ALIGNMENT_CENTER
	trick_box.add_theme_constant_override("separation", 18)
	trick_box.custom_minimum_size = Vector2(0, 124)
	root.add_child(trick_box)

	action_box = HBoxContainer.new()
	action_box.alignment = BoxContainer.ALIGNMENT_CENTER
	action_box.add_theme_constant_override("separation", 8)
	root.add_child(action_box)

	hand_box = HBoxContainer.new()
	hand_box.alignment = BoxContainer.ALIGNMENT_CENTER
	hand_box.add_theme_constant_override("separation", 10)
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

func _on_join_pressed() -> void:
	_read_lobby_inputs()
	var address := address_input.text.strip_edges()
	if address.is_empty():
		address = "127.0.0.1"
	var err := Net.join(address)
	if err != OK:
		_set_status("Join failed: %s" % error_string(err))
	else:
		_create_client_waiting_view()

func _apply_command_line_mode() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--host"):
		_on_host_pressed()
	elif args.has("--join"):
		_on_join_pressed()

func _create_offline_lobby() -> void:
	my_seat = 0
	seat_peers = _new_seat_peers(lobby_player_count)
	_create_lobby("Offline preview. Host a game or join a host.")

func _create_client_waiting_view() -> void:
	view_state = {
		"phase": "connecting",
		"names": _default_names(lobby_player_count),
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
		"message": "Connecting to host...",
	}
	local_hand = []
	_render()

func _create_lobby(message: String) -> void:
	var names := _default_names(lobby_player_count)
	names[0] = local_player_name
	state = {
		"phase": "lobby",
		"names": names,
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
		"message": message,
	}
	_publish_state()

func _start_match(names: Array, max_cards: int) -> void:
	if multiplayer.multiplayer_peer and not multiplayer.is_server():
		return

	state = {
		"phase": "bidding",
		"names": names,
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

func _publish_state() -> void:
	if multiplayer.multiplayer_peer and multiplayer.is_server():
		for seat in range(state["num_players"]):
			if not state["connected"][seat]:
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
	if view_state["phase"] == "connecting":
		table_label.text = view_state["message"]
		_render_trick()
		_render_actions()
		_render_hand()
		return
	if view_state["phase"] == "lobby":
		_render_lobby()
		return

	var round_size: int = view_state["sequence"][view_state["round_index"]]
	var text := "Round %d / %d | Cards: %d | Trump: %s\n" % [
		view_state["round_index"] + 1,
		view_state["sequence"].size(),
		round_size,
		GameRules.SUIT_NAMES.get(view_state["trump"], view_state["trump"]),
	]
	text += "You are seat %d: %s\n\n" % [my_seat + 1, view_state["names"][my_seat]]
	for i in range(view_state["num_players"]):
		var bid_text := "?"
		if view_state["phase"] == "bidding":
			bid_text = "in" if view_state["bid_submitted"][i] else "..."
		elif view_state["bids"][i] != null:
			bid_text = str(view_state["bids"][i])
		text += "%s: %d points, bid %s, tricks %d\n" % [
			view_state["names"][i],
			view_state["scores"][i],
			bid_text,
			view_state["tricks_won"][i],
		]
	text += "\n%s" % view_state["message"]
	table_label.text = text

	_render_trick()
	_render_actions()
	_render_hand()

func _render_lobby() -> void:
	var text := "Multiplayer Lobby\n\n"
	text += "Table: %d players, %d max cards\n" % [view_state["num_players"], view_state["max_cards"]]
	text += "You are seat %d: %s\n\n" % [my_seat + 1, view_state["names"][my_seat]]
	if multiplayer.multiplayer_peer and multiplayer.is_server():
		var addresses := Net.local_join_addresses()
		if addresses.is_empty():
			text += "Join address: local network IP not found\n"
		else:
			text += "Join address: %s\n" % ", ".join(addresses)
		text += "\n"
	for i in range(view_state["num_players"]):
		var status := "connected" if view_state["connected"][i] else "waiting"
		text += "Seat %d: %s - %s\n" % [i + 1, view_state["names"][i], status]
	text += "\n%s" % view_state["message"]
	table_label.text = text
	_render_trick()
	_render_actions()
	_render_hand()

func _render_trick() -> void:
	for child in trick_box.get_children():
		child.queue_free()

	if view_state["trick"].is_empty():
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
		var waiting := Label.new()
		waiting.text = "Waiting for players: %d / %d" % [connected_count, view_state["num_players"]]
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

func _render_hand() -> void:
	for child in hand_box.get_children():
		child.queue_free()

	for card in local_hand:
		var button = CardButtonScript.new()
		button.setup(card)
		button.disabled = view_state["phase"] != "playing" or view_state["active_player"] != my_seat or not GameRules.is_legal_card(local_hand, view_state["led_suit"], card)
		button.set_meta("card", card)
		button.pressed.connect(_on_card_button_pressed.bind(button))
		hand_box.add_child(button)

func _view_connected_count() -> int:
	if not view_state.has("connected"):
		return 0
	var count := 0
	for connected in view_state["connected"]:
		if connected:
			count += 1
	return count

func _read_lobby_inputs() -> void:
	local_player_name = name_input.text.strip_edges()
	if local_player_name.is_empty():
		local_player_name = "Player 1"
	lobby_player_count = int(player_count_spin.value)
	lobby_max_cards = int(max_cards_spin.value)
	lobby_max_cards = clampi(lobby_max_cards, 1, GameRules.max_allowed_cards(lobby_player_count))

func _on_name_changed(new_text: String) -> void:
	local_player_name = new_text.strip_edges()
	if local_player_name.is_empty():
		local_player_name = "Player 1"
	if multiplayer.multiplayer_peer and multiplayer.is_server() and state.get("phase", "") == "lobby":
		state["names"][0] = local_player_name
		_publish_state()

func _on_player_count_changed(value: float) -> void:
	lobby_player_count = int(value)
	var allowed := GameRules.max_allowed_cards(lobby_player_count)
	max_cards_spin.max_value = allowed
	if max_cards_spin.value > allowed:
		max_cards_spin.value = allowed
	lobby_max_cards = int(max_cards_spin.value)
	if not multiplayer.multiplayer_peer:
		_create_offline_lobby()

func _on_max_cards_changed(value: float) -> void:
	lobby_max_cards = int(value)
	if not multiplayer.multiplayer_peer:
		_create_offline_lobby()

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
		state["phase"] = "game_end"
		state["message"] = "Game over."
		_publish_state()
	else:
		_begin_round()

func _peer_for_seat(seat: int) -> int:
	if seat == 0:
		return 1
	return int(seat_peers[seat])

func _seat_for_peer(peer_id: int) -> int:
	if peer_id == 1:
		return 0
	return seat_peers.find(peer_id)

func _on_connected_to_server() -> void:
	_server_register_name.rpc_id(1, local_player_name)

func _on_connection_failed() -> void:
	_create_client_waiting_view()
	view_state["message"] = "Connection failed."
	_render()

@rpc("any_peer", "reliable")
func _server_register_name(player_name: String) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	var seat := _seat_for_peer(peer_id)
	if seat < 0 or seat >= state["num_players"]:
		return
	var clean_name := player_name.strip_edges()
	if clean_name.is_empty():
		clean_name = "Player %d" % [seat + 1]
	state["names"][seat] = clean_name.substr(0, 18)
	state["message"] = "%s joined seat %d." % [state["names"][seat], seat + 1]
	_publish_state()

func _on_peer_connected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	var seat := _first_open_seat()
	if seat == -1:
		return
	seat_peers[seat] = peer_id
	state["connected"] = _connected_seats()
	state["message"] = "Seat %d joined." % [seat + 1]
	_publish_state()
	if _connected_count() == state["num_players"] and state["phase"] == "lobby":
		await get_tree().create_timer(0.5).timeout
		if state["phase"] == "lobby" and _connected_count() == state["num_players"]:
			_start_match(state["names"].duplicate(true), state["max_cards"])

func _on_peer_disconnected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	var seat := seat_peers.find(peer_id)
	if seat == -1:
		return
	seat_peers[seat] = 0
	state["connected"] = _connected_seats()
	state["message"] = "Seat %d disconnected." % [seat + 1]
	_publish_state()

func _first_open_seat() -> int:
	for seat in range(1, seat_peers.size()):
		if int(seat_peers[seat]) == 0:
			return seat
	return -1

func _new_seat_peers(count: int) -> Array:
	var peers: Array = []
	for seat in range(count):
		peers.append(1 if seat == 0 else 0)
	return peers

func _default_names(count: int) -> Array:
	var names: Array = []
	for i in range(count):
		if i < STARTING_NAMES.size():
			names.append(STARTING_NAMES[i])
		else:
			names.append("Player %d" % [i + 1])
	return names

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
	for peer_id in seat_peers:
		connected.append(int(peer_id) != 0)
	return connected

func _connected_count() -> int:
	var count := 0
	for connected in _connected_seats():
		if connected:
			count += 1
	return count

func _set_status(message: String) -> void:
	status_label.text = message
