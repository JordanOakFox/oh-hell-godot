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

