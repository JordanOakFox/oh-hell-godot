extends Node

const SAVE_PATH := "user://profile.json"
const ANIMALS := ["bunny", "lizard", "lion", "tiger", "bear", "fox", "dog", "cat"]
const BOT_PERSONALITIES := ["casual", "smart", "ruthless"]

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
		"animal": animal(),
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

func music_volume() -> float:
	return clampf(float(data.get("music_volume", 0.7)), 0.0, 1.0)

func set_music_volume(value: float) -> void:
	data["music_volume"] = clampf(value, 0.0, 1.0)
	save_profile()

func music_muted() -> bool:
	return bool(data.get("music_muted", false))

func set_music_muted(muted: bool) -> void:
	data["music_muted"] = muted
	save_profile()

func sfx_volume() -> float:
	return clampf(float(data.get("sfx_volume", 0.75)), 0.0, 1.0)

func set_sfx_volume(value: float) -> void:
	data["sfx_volume"] = clampf(value, 0.0, 1.0)
	save_profile()

func sfx_muted() -> bool:
	return bool(data.get("sfx_muted", false))

func set_sfx_muted(muted: bool) -> void:
	data["sfx_muted"] = muted
	save_profile()

func bot_personality() -> String:
	var selected := str(data.get("bot_personality", "smart"))
	return selected if BOT_PERSONALITIES.has(selected) else "smart"

func set_bot_personality(value: String) -> void:
	data["bot_personality"] = value if BOT_PERSONALITIES.has(value) else "smart"
	save_profile()

func animal() -> String:
	var selected := str(data.get("animal", "fox"))
	return selected if ANIMALS.has(selected) else "fox"

func set_animal(value: String) -> void:
	data["animal"] = value if ANIMALS.has(value) else "fox"
	save_profile()

func _default_profile() -> Dictionary:
	return {
		"id": _make_profile_id(),
		"display_name": "Player",
		"animal": "fox",
		"music_volume": 0.7,
		"music_muted": false,
		"sfx_volume": 0.75,
		"sfx_muted": false,
		"bot_personality": "smart",
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
