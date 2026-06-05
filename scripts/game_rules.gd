extends Node

const SUITS := ["S", "H", "D", "C"]
const SUIT_NAMES := {"S": "Spades", "H": "Hearts", "D": "Diamonds", "C": "Clubs"}
const RANK_NAMES := {11: "J", 12: "Q", 13: "K", 14: "A"}

func max_allowed_cards(num_players: int) -> int:
	return floori(51.0 / float(num_players))

func down_up_sequence(max_cards: int) -> Array:
	var sequence: Array = []
	for card_count in range(max_cards, 0, -1):
		sequence.append(card_count)
	for card_count in range(2, max_cards + 1):
		sequence.append(card_count)
	return sequence

func build_deck() -> Array:
	var deck: Array = []
	for suit in SUITS:
		for rank in range(2, 15):
			deck.append({"suit": suit, "rank": rank})
	return deck

func shuffle_deck(deck: Array, rng: RandomNumberGenerator) -> Array:
	var shuffled := deck.duplicate(true)
	for i in range(shuffled.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = shuffled[i]
		shuffled[i] = shuffled[j]
		shuffled[j] = tmp
	return shuffled

func sort_hand(hand: Array) -> Array:
	var sorted := hand.duplicate(true)
	var suit_order := {"S": 0, "H": 1, "C": 2, "D": 3}
	sorted.sort_custom(func(a, b):
		if suit_order[a["suit"]] != suit_order[b["suit"]]:
			return suit_order[a["suit"]] < suit_order[b["suit"]]
		return int(a["rank"]) > int(b["rank"])
	)
	return sorted

func deal_round(num_players: int, round_size: int, rng: RandomNumberGenerator) -> Dictionary:
	var deck := shuffle_deck(build_deck(), rng)
	var hands: Array = []
	for _p in range(num_players):
		hands.append([])

	var cursor := 0
	for _r in range(round_size):
		for player in range(num_players):
			hands[player].append(deck[cursor])
			cursor += 1

	for player in range(num_players):
		hands[player] = sort_hand(hands[player])

	return {
		"hands": hands,
		"trump": deck[cursor]["suit"],
	}

func legal_cards(hand: Array, led_suit) -> Array:
	if led_suit == null:
		return hand.duplicate(true)

	var matching: Array = []
	for card in hand:
		if card["suit"] == led_suit:
			matching.append(card)
	return matching if matching.size() > 0 else hand.duplicate(true)

func is_legal_card(hand: Array, led_suit, card: Dictionary) -> bool:
	for legal in legal_cards(hand, led_suit):
		if same_card(legal, card):
			return true
	return false

func same_card(a: Dictionary, b: Dictionary) -> bool:
	return a["suit"] == b["suit"] and int(a["rank"]) == int(b["rank"])

func remove_card(hand: Array, card: Dictionary) -> Array:
	var next_hand := hand.duplicate(true)
	for i in range(next_hand.size()):
		if same_card(next_hand[i], card):
			next_hand.remove_at(i)
			return next_hand
	return next_hand

func trick_winner(trick: Array, led_suit: String, trump: String) -> int:
	var best: Dictionary = trick[0]
	for play in trick:
		if beats(play["card"], best["card"], led_suit, trump):
			best = play
	return int(best["player"])

func beats(a: Dictionary, b: Dictionary, led_suit: String, trump: String) -> bool:
	var a_trump: bool = a["suit"] == trump
	var b_trump: bool = b["suit"] == trump
	if a_trump and not b_trump:
		return true
	if not a_trump and b_trump:
		return false
	if a_trump and b_trump:
		return int(a["rank"]) > int(b["rank"])

	var a_led: bool = a["suit"] == led_suit
	var b_led: bool = b["suit"] == led_suit
	if a_led and not b_led:
		return true
	if not a_led and b_led:
		return false
	if a_led and b_led:
		return int(a["rank"]) > int(b["rank"])
	return false

func score_deltas(bids: Array, tricks_won: Array) -> Array:
	var deltas: Array = []
	for player in range(bids.size()):
		var hit_bid := int(tricks_won[player]) == int(bids[player])
		deltas.append(10 + int(bids[player]) if hit_bid else 0)
	return deltas

func card_label(card: Dictionary) -> String:
	var rank_text: String = RANK_NAMES.get(int(card["rank"]), str(card["rank"]))
	return "%s %s" % [rank_text, card["suit"]]
