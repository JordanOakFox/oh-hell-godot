extends Control

const STARTING_NAMES := ["Player 1", "Player 2", "Player 3", "Player 4"]
const DEFAULT_MAX_CARDS := 7
const TARGET_PLAYERS := 4

const CardButtonScript := preload("res://scripts/card_button.gd")
const FeltBackgroundScript := preload("res://scripts/felt_background.gd")

var state: Dictionary = {}
var view_state: Dictionary = {}
var local_hand: Array = []
var my_seat := 0
var seat_peers: Array = [1, 0, 0, 0]
var rng := RandomNumberGenerator.new()

var status_label: Label
var table_label: Label
var trick_box: HBoxContainer
var hand_box: HBoxContainer
var action_box: HBoxContainer
var address_input: LineEdit

func _ready() -> void:
	rng.randomize()
	_build_ui()
	Net.connection_changed.connect(_set_status)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
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
	var err := Net.host()
	if err != OK:
		_set_status("Host failed: %s" % error_string(err))
		return
	my_seat = 0
	seat_peers = [1, 0, 0, 0]
	_create_lobby("Hosting. Waiting for players...")

func _on_join_pressed() -> void:
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
	seat_peers = [1, 0, 0, 0]
	_create_lobby("Offline preview. Host a game or join a host.")

func _create_client_waiting_view() -> void:
	view_state = {
		"phase": "connecting",
		"names": STARTING_NAMES,
		"num_players": TARGET_PLAYERS,
		"sequence": [DEFAULT_MAX_CARDS],
		"round_index": 0,
		"dealer": TARGET_PLAYERS - 1,
		"scores": [0, 0, 0, 0],
		"bids": [null, null, null, null],
		"bid_submitted": [false, false, false, false],
		"tricks_won": [0, 0, 0, 0],
		"trump": "",
		"trick": [],
		"led_suit": null,
		"leader": 0,
		"active_player": -1,
		"connected": [false, false, false, false],
		"message": "Connecting to host...",
	}
	local_hand = []
	_render()

func _create_lobby(message: String) -> void:
	state = {
		"phase": "lobby",
		"names": STARTING_NAMES,
		"num_players": TARGET_PLAYERS,
		"sequence": GameRules.down_up_sequence(DEFAULT_MAX_CARDS),
		"round_index": 0,
		"dealer": TARGET_PLAYERS - 1,
		"scores": [0, 0, 0, 0],
		"hands": [[], [], [], []],
		"bids": [null, null, null, null],
		"bid_submitted": [false, false, false, false],
		"tricks_won": [0, 0, 0, 0],
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
	text += "You are seat %d: %s\n\n" % [my_seat + 1, view_state["names"][my_seat]]
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
			_start_match(STARTING_NAMES, DEFAULT_MAX_CARDS)

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
