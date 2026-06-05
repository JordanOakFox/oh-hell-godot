extends Node

const SAVE_PATH := "user://profile.json"

var data: Dictionary = {}

func _ready() -> void:
	load_profile()

func load_profile() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
		if file:
			var parsed = JSON.parse_string(file.get_as_text())
			if typeof(parsed) == TYPE_DICTIONARY:
				data = parsed
	if data.is_empty():
		data = _default_profile()
		save_profile()

func save_profile() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))

func display_name() -> String:
	return str(data.get("display_name", "Player"))

func profile_id() -> String:
	return str(data.get("id", ""))

func set_display_name(name: String) -> void:
	var clean := name.strip_edges()
	if clean.is_empty():
		clean = "Player"
	data["display_name"] = clean.substr(0, 18)
	save_profile()

func public_profile() -> Dictionary:
	return {
		"id": profile_id(),
		"display_name": display_name(),
		"games_played": int(data.get("games_played", 0)),
		"wins": int(data.get("wins", 0)),
	}

func record_game_result(score: int, won: bool, bid_hits: int, bid_misses: int) -> void:
	data["games_played"] = int(data.get("games_played", 0)) + 1
	data["wins"] = int(data.get("wins", 0)) + (1 if won else 0)
	data["total_score"] = int(data.get("total_score", 0)) + score
	data["best_score"] = max(int(data.get("best_score", 0)), score)
	data["bid_hits"] = int(data.get("bid_hits", 0)) + bid_hits
	data["bid_misses"] = int(data.get("bid_misses", 0)) + bid_misses
	data["last_score"] = score
	data["last_result"] = "Win" if won else "Loss"
	data["updated_at"] = Time.get_datetime_string_from_system(false, true)
	save_profile()

func stats_line() -> String:
	var games := int(data.get("games_played", 0))
	var wins := int(data.get("wins", 0))
	var best := int(data.get("best_score", 0))
	if games == 0:
		return "New profile"
	return "%d games, %d wins, best %d" % [games, wins, best]

func _default_profile() -> Dictionary:
	return {
		"id": _make_profile_id(),
		"display_name": "Player",
		"games_played": 0,
		"wins": 0,
		"total_score": 0,
		"best_score": 0,
		"bid_hits": 0,
		"bid_misses": 0,
		"last_score": 0,
		"last_result": "",
		"created_at": Time.get_datetime_string_from_system(false, true),
		"updated_at": Time.get_datetime_string_from_system(false, true),
	}

func _make_profile_id() -> String:
	var crypto := Crypto.new()
	var bytes := crypto.generate_random_bytes(16)
	var id := ""
	for byte in bytes:
		id += "%02x" % int(byte)
	return id
