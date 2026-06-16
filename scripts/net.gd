extends Node

signal connection_changed(message: String)
signal discovered_games_changed(games: Array)

const DEFAULT_PORT := 24567
const DISCOVERY_PORT := 24568
const DISCOVERY_MAGIC := "oh-hell-godot-lobby-v1"

var discovery_listener: PacketPeerUDP
var discovery_sender: PacketPeerUDP
var discovered_games := {}
var advertise_info := {}
var advertise_elapsed := 0.0
var discovery_enabled := false
var advertising_enabled := false
var current_port := DEFAULT_PORT

func _process(delta: float) -> void:
	if advertising_enabled:
		advertise_elapsed += delta
		if advertise_elapsed >= 1.0:
			advertise_elapsed = 0.0
			_send_discovery_advertisement()
	if discovery_enabled:
		_poll_discovery()
		_prune_discovery()

func host(port: int = DEFAULT_PORT, max_clients: int = 9) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, max_clients)
	if err == OK:
		current_port = port
		multiplayer.multiplayer_peer = peer
		connection_changed.emit("Hosting on port %d" % port)
	return err

func join(address: String, port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err == OK:
		current_port = port
		multiplayer.multiplayer_peer = peer
		connection_changed.emit("Joining %s:%d" % [address, port])
	return err

func stop() -> void:
	stop_discovery()
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	current_port = DEFAULT_PORT
	connection_changed.emit("Offline")

func is_host() -> bool:
	return multiplayer.is_server()

func local_join_addresses(port: int = DEFAULT_PORT) -> Array:
	var addresses: Array = []
	for address in IP.get_local_addresses():
		var text := str(address)
		if text == "127.0.0.1" or text == "::1":
			continue
		if text.find(":") != -1:
			continue
		if text.begins_with("169.254."):
			continue
		addresses.append("%s:%d" % [text, port])
	return addresses

func start_advertising(info: Dictionary) -> void:
	advertise_info = info.duplicate(true)
	advertising_enabled = true
	if discovery_sender == null:
		discovery_sender = PacketPeerUDP.new()
		discovery_sender.set_broadcast_enabled(true)
		discovery_sender.set_dest_address("255.255.255.255", DISCOVERY_PORT)
	advertise_elapsed = 1.0

func update_advertisement(info: Dictionary) -> void:
	advertise_info = info.duplicate(true)

func start_discovery() -> void:
	if discovery_listener == null:
		discovery_listener = PacketPeerUDP.new()
		var err := discovery_listener.bind(DISCOVERY_PORT, "0.0.0.0")
		if err != OK:
			connection_changed.emit("LAN scan unavailable on this device.")
			discovery_listener = null
			return
	discovery_enabled = true

func stop_discovery() -> void:
	discovery_enabled = false
	advertising_enabled = false
	discovered_games.clear()
	if discovery_listener:
		discovery_listener.close()
	discovery_listener = null
	if discovery_sender:
		discovery_sender.close()
	discovery_sender = null
	discovered_games_changed.emit([])

func discovery_games() -> Array:
	var games: Array = []
	for key in discovered_games.keys():
		games.append(discovered_games[key])
	return games

func _send_discovery_advertisement() -> void:
	if discovery_sender == null:
		return
	var payload := advertise_info.duplicate(true)
	payload["magic"] = DISCOVERY_MAGIC
	payload["port"] = current_port
	payload["time"] = Time.get_unix_time_from_system()
	discovery_sender.put_packet(JSON.stringify(payload).to_utf8_buffer())

func _poll_discovery() -> void:
	if discovery_listener == null:
		return
	var changed := false
	while discovery_listener.get_available_packet_count() > 0:
		var packet := discovery_listener.get_packet()
		var text := packet.get_string_from_utf8()
		var parsed = JSON.parse_string(text)
		if typeof(parsed) != TYPE_DICTIONARY:
			continue
		if parsed.get("magic", "") != DISCOVERY_MAGIC:
			continue
		var address := discovery_listener.get_packet_ip()
		var key := "%s:%d" % [address, int(parsed.get("port", DEFAULT_PORT))]
		parsed["address"] = address
		parsed["last_seen"] = Time.get_unix_time_from_system()
		discovered_games[key] = parsed
		changed = true
	if changed:
		discovered_games_changed.emit(discovery_games())

func _prune_discovery() -> void:
	var now := Time.get_unix_time_from_system()
	var changed := false
	for key in discovered_games.keys():
		if now - float(discovered_games[key].get("last_seen", 0.0)) > 4.0:
			discovered_games.erase(key)
			changed = true
	if changed:
		discovered_games_changed.emit(discovery_games())
