extends Node

signal connection_changed(message: String)

const DEFAULT_PORT := 24567

func host(port: int = DEFAULT_PORT, max_clients: int = 9) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, max_clients)
	if err == OK:
		multiplayer.multiplayer_peer = peer
		connection_changed.emit("Hosting on port %d" % port)
	return err

func join(address: String, port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err == OK:
		multiplayer.multiplayer_peer = peer
		connection_changed.emit("Joining %s:%d" % [address, port])
	return err

func stop() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
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
