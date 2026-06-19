extends SubViewportContainer

const AVATAR_COLORS := [
	Color("#d26a3c"),
	Color("#8f6ad6"),
	Color("#5fbf7a"),
	Color("#d8b24c"),
	Color("#6aa5d8"),
	Color("#c86a92"),
	Color("#9bb14f"),
	Color("#b58659"),
	Color("#70c6c1"),
	Color("#c95f52"),
]
const ANIMAL_COLORS := {
	"bunny": Color("#d8c4f0"),
	"lizard": Color("#66b77a"),
	"lion": Color("#d8a24a"),
	"tiger": Color("#d9783f"),
	"bear": Color("#8a6345"),
	"fox": Color("#cf6f3a"),
	"dog": Color("#a98560"),
	"cat": Color("#8f8f9a"),
}
const SUIT_COLORS := {
	"S": Color("#111111"),
	"H": Color("#c8322b"),
	"D": Color("#e86f22"),
	"C": Color("#2367c7"),
}
const SUIT_SYMBOLS := {"S": "♠", "H": "♥", "D": "♦", "C": "♣"}
const RANK_NAMES := {11: "J", 12: "Q", 13: "K", 14: "A"}

var viewport: SubViewport
var camera: Camera3D
var world_environment: WorldEnvironment
var world_root: Node3D
var ocean_root: Node3D
var ship_root: Node3D
var seat_root: Node3D
var trick_root: Node3D
var hand_root: Node3D
var flag_root: Node3D
var seats: Array = []
var seat_base_positions: Array = []
var seat_base_rotations: Array = []
var seat_moods: Array = []
var wave_strips: Array = []
var flag_strips: Array = []
var seat_count := 0
var current_active := -1
var local_seat := 0
var camera_mode := "overview"
var look_enabled := false
var skip_next_mouse_motion := false
var look_yaw := 0.0
var look_pitch := -10.0
var lobby_walk_position := Vector3(0, 1.35, 3.6)
var lobby_walk_yaw := 180.0
var lobby_walk_pitch := -8.0
var lobby_avatar_yaw := 180.0
var hand_signature := ""
var hovered_hand_index := -1
var current_map_id := "landing"
var table_felt_color := Color("#0b5a3f")
var table_rail_color := Color("#7a4a28")
var time := 0.0
var last_emote_serial := 0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	stretch = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	viewport = SubViewport.new()
	viewport.size = Vector2i(512, 288)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)

	world_root = Node3D.new()
	viewport.add_child(world_root)
	_build_world()

func _exit_tree() -> void:
	if look_enabled:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _process(delta: float) -> void:
	time += delta
	if ship_root:
		if current_map_id == "pirate":
			ship_root.position.y = sin(time * 1.35) * 0.06
			ship_root.rotation_degrees.z = sin(time * 0.9) * 1.6
			ship_root.rotation_degrees.x = cos(time * 0.7) * 1.1
		else:
			ship_root.position.y = 0.0
			ship_root.rotation_degrees.z = 0.0
			ship_root.rotation_degrees.x = 0.0
	_animate_waves()
	_animate_flag()
	_animate_seats()
	_animate_emotes()
	_update_lobby_walk(delta)
	_update_camera()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		look_enabled = event.pressed
		skip_next_mouse_motion = look_enabled
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if look_enabled else Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseMotion and look_enabled:
		if skip_next_mouse_motion:
			skip_next_mouse_motion = false
			return
		if event.relative.length() > 220.0:
			return
		if camera_mode == "lobby_walk":
			lobby_walk_yaw -= event.relative.x * 0.045
			lobby_walk_pitch = clampf(lobby_walk_pitch - event.relative.y * 0.035, -35.0, 22.0)
		else:
			look_yaw = clampf(look_yaw - event.relative.x * 0.022, -56.0, 56.0)
			look_pitch = clampf(look_pitch - event.relative.y * 0.018, -18.0, 26.0)

func set_table_state(table_state: Dictionary, my_seat: int) -> void:
	if not is_inside_tree() or table_state.is_empty():
		return
	var players := int(table_state.get("num_players", 0))
	if players <= 0:
		return
	var phase := str(table_state.get("phase", ""))
	var previous_camera_mode := camera_mode
	camera_mode = "seat" if phase in ["bidding", "playing", "trick_end", "round_end"] else ("lobby_walk" if phase in ["connecting", "lobby"] else "overview")
	var map_id := "landing" if bool(table_state.get("menu_preview", false)) or phase in ["connecting", "lobby"] else str(table_state.get("map_id", "living_room"))
	if map_id != current_map_id:
		_rebuild_map(map_id)
	if players != seat_count or previous_camera_mode != camera_mode:
		_rebuild_seats(players)
	local_seat = clampi(my_seat, 0, max(players - 1, 0))
	if not (camera_mode in ["seat", "lobby_walk"]) and look_enabled:
		look_enabled = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_update_seats(table_state, my_seat)
	_update_trick(table_state)

func set_player_hand(hand: Array) -> void:
	var signature := _hand_signature(hand)
	if signature == hand_signature:
		return
	hand_signature = signature
	_rebuild_player_hand(hand)

func set_hovered_hand_index(index: int) -> void:
	hovered_hand_index = index

func set_emote_event(event) -> void:
	if typeof(event) != TYPE_DICTIONARY:
		return
	var serial := int(event.get("serial", 0))
	if serial <= 0 or serial <= last_emote_serial:
		return
	last_emote_serial = serial
	var seat := int(event.get("seat", -1))
	if seat < 0 or seat >= seats.size():
		return
	if str(event.get("name", "")) == "middle_finger":
		_show_middle_finger_emote(seat)

func is_mouse_look_enabled() -> bool:
	return look_enabled

func release_mouse_look() -> void:
	look_enabled = false
	skip_next_mouse_motion = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func get_lobby_avatar_state() -> Dictionary:
	return {
		"x": lobby_walk_position.x,
		"z": lobby_walk_position.z,
		"yaw": lobby_avatar_yaw,
	}

func pick_hand_card(mouse_position: Vector2, display_size: Vector2) -> int:
	if not camera or not hand_root or hand_root.get_child_count() == 0 or display_size.x <= 0.0 or display_size.y <= 0.0:
		return -1
	var viewport_size := Vector2(viewport.size)
	var local_mouse := Vector2(
		mouse_position.x / display_size.x * viewport_size.x,
		mouse_position.y / display_size.y * viewport_size.y
	)
	var best_index := -1
	var best_distance := 999999.0
	for i in range(hand_root.get_child_count()):
		var card := hand_root.get_child(i) as Node3D
		if not card:
			continue
		if camera.is_position_behind(card.global_position):
			continue
		var bounds := _projected_card_bounds(card)
		if bounds.size == Vector2.ZERO:
			continue
		var padded := bounds.grow(5.0)
		if not padded.has_point(local_mouse):
			continue
		var projected := camera.unproject_position(card.global_position)
		var half_size: float = maxf(padded.size.length() * 0.5, 1.0)
		var distance: float = projected.distance_to(local_mouse) / half_size
		if distance < best_distance:
			best_distance = distance
			best_index = i
	return best_index

func _projected_card_bounds(card: Node3D) -> Rect2:
	var corners := [
		Vector3(-0.17, 0.033, -0.24),
		Vector3(0.17, 0.033, -0.24),
		Vector3(0.17, 0.033, 0.24),
		Vector3(-0.17, 0.033, 0.24),
	]
	var min_point := Vector2(999999.0, 999999.0)
	var max_point := Vector2(-999999.0, -999999.0)
	for corner in corners:
		var world_corner := card.to_global(corner)
		if camera.is_position_behind(world_corner):
			return Rect2()
		var projected := camera.unproject_position(world_corner)
		min_point.x = minf(min_point.x, projected.x)
		min_point.y = minf(min_point.y, projected.y)
		max_point.x = maxf(max_point.x, projected.x)
		max_point.y = maxf(max_point.y, projected.y)
	return Rect2(min_point, max_point - min_point)

func _build_world() -> void:
	camera = Camera3D.new()
	camera.position = Vector3(0, 5.9, 6.4)
	camera.rotation_degrees = Vector3(-50, 0, 0)
	camera.fov = 44
	world_root.add_child(camera)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-44, -32, 0)
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	world_root.add_child(sun)

	var fill := OmniLight3D.new()
	fill.position = Vector3(0, 3.4, 2.4)
	fill.light_energy = 0.85
	fill.omni_range = 7.0
	fill.shadow_enabled = true
	world_root.add_child(fill)

	var ambient := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#5aa7b9")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#c3e1df")
	env.ambient_light_energy = 0.95
	ambient.environment = env
	world_environment = ambient
	world_root.add_child(ambient)

	hand_root = Node3D.new()
	camera.add_child(hand_root)
	_rebuild_map(current_map_id)

func _rebuild_map(map_id: String) -> void:
	if not ["landing", "pirate", "space", "living_room", "jungle"].has(map_id):
		map_id = "living_room"
	current_map_id = map_id
	if ocean_root:
		ocean_root.queue_free()
	if ship_root:
		ship_root.queue_free()
	wave_strips.clear()
	flag_strips.clear()
	seats.clear()
	seat_base_positions.clear()
	seat_base_rotations.clear()
	seat_moods.clear()
	seat_count = 0

	ocean_root = Node3D.new()
	world_root.add_child(ocean_root)
	ship_root = Node3D.new()
	world_root.add_child(ship_root)

	if current_map_id == "landing":
		_build_landing_map()
	elif current_map_id == "space":
		_build_space_map()
	elif current_map_id == "living_room":
		_build_living_room_map()
	elif current_map_id == "jungle":
		_build_jungle_map()
	else:
		_build_pirate_map()
	if current_map_id == "landing":
		lobby_walk_position = Vector3(0, 1.35, 3.6)
		lobby_walk_yaw = 180.0
		lobby_walk_pitch = -8.0

func _set_world_colors(background: Color, ambient_color: Color, ambient_energy: float) -> void:
	if world_environment and world_environment.environment:
		world_environment.environment.background_color = background
		world_environment.environment.ambient_light_color = ambient_color
		world_environment.environment.ambient_light_energy = ambient_energy

func _build_ocean() -> void:
	var sea := MeshInstance3D.new()
	var sea_mesh := PlaneMesh.new()
	sea_mesh.size = Vector2(18, 13)
	sea.mesh = sea_mesh
	sea.material_override = _mat(Color("#1b6c85"))
	sea.position.y = -0.42
	ocean_root.add_child(sea)

	for i in range(14):
		var wave := _box(Vector3(2.0 + float(i % 3) * 0.45, 0.035, 0.055), Color("#d5f5f2"))
		wave.position = Vector3(-7.0 + float(i % 7) * 2.25, -0.36, -5.0 + float(i / 7) * 3.0)
		ocean_root.add_child(wave)
		wave_strips.append(wave)

func _build_pirate_map() -> void:
	table_felt_color = Color("#0b5a3f")
	table_rail_color = Color("#7a4a28")
	_set_world_colors(Color("#5aa7b9"), Color("#c3e1df"), 0.95)
	_build_ocean()

	var deck := _box(Vector3(6.5, 0.22, 4.1), Color("#8b552f"))
	deck.position = Vector3(0, -0.08, 0)
	ship_root.add_child(deck)
	for plank in range(9):
		var plank_tint := Color("#9b6239") if plank % 2 == 0 else Color("#7d4a2b")
		var plank_board := _box(Vector3(0.62, 0.035, 3.95), plank_tint)
		plank_board.position = Vector3(-2.75 + float(plank) * 0.68, 0.055, 0)
		ship_root.add_child(plank_board)

	var hull := _box(Vector3(7.0, 0.42, 4.55), Color("#5a2f1d"))
	hull.position = Vector3(0, -0.35, 0)
	ship_root.add_child(hull)

	for z in [-2.25, 2.25]:
		var rail := _box(Vector3(6.8, 0.34, 0.18), Color("#3c2117"))
		rail.position = Vector3(0, 0.28, z)
		ship_root.add_child(rail)
	for x in [-3.45, 3.45]:
		var rail_end := _box(Vector3(0.18, 0.34, 4.4), Color("#3c2117"))
		rail_end.position = Vector3(x, 0.28, 0)
		ship_root.add_child(rail_end)

	for plank in range(7):
		var seam := _box(Vector3(0.035, 0.015, 3.8), Color("#6f3f24"))
		seam.position = Vector3(-2.7 + float(plank) * 0.9, 0.05, 0)
		ship_root.add_child(seam)

	var mast := _cylinder(0.11, 2.75, Color("#4b2a1b"))
	mast.position = Vector3(2.55, 1.22, -1.35)
	ship_root.add_child(mast)

	var crossbar := _box(Vector3(1.35, 0.08, 0.08), Color("#4b2a1b"))
	crossbar.position = Vector3(2.55, 2.25, -1.35)
	ship_root.add_child(crossbar)

	flag_root = Node3D.new()
	flag_root.position = Vector3(3.12, 2.04, -1.35)
	ship_root.add_child(flag_root)
	_build_jolly_roger()

	_attach_table_area()

func _build_landing_map() -> void:
	table_felt_color = Color("#256045")
	table_rail_color = Color("#8a5c3b")
	_set_world_colors(Color("#9dd2e3"), Color("#d8f0ef"), 1.12)
	_build_ocean()

	var shore := _box(Vector3(14.5, 0.18, 4.0), Color("#5f9b55"))
	shore.position = Vector3(0, -0.22, -4.0)
	ship_root.add_child(shore)
	var road := _box(Vector3(1.45, 0.035, 4.6), Color("#9c9c8d"))
	road.position = Vector3(-4.25, -0.08, -4.18)
	ship_root.add_child(road)
	var ferry_ramp := _box(Vector3(1.85, 0.08, 1.45), Color("#777c78"))
	ferry_ramp.position = Vector3(-4.25, -0.03, -2.15)
	ship_root.add_child(ferry_ramp)

	var dock := _box(Vector3(8.2, 0.11, 0.7), Color("#7b5a3a"))
	dock.position = Vector3(1.25, 0.02, -1.62)
	ship_root.add_child(dock)
	for i in range(11):
		var post := _cylinder(0.055, 0.62, Color("#5c422b"))
		post.position = Vector3(-2.6 + float(i) * 0.72, -0.18, -1.13)
		ship_root.add_child(post)

	var ferry := _box(Vector3(2.0, 0.32, 1.05), Color("#d8dedb"))
	ferry.position = Vector3(-5.15, 0.08, -1.35)
	ship_root.add_child(ferry)
	var ferry_booth := _box(Vector3(0.5, 0.42, 0.38), Color("#c3d1d0"))
	ferry_booth.position = Vector3(-5.15, 0.45, -1.35)
	ship_root.add_child(ferry_booth)

	var restaurant := _box(Vector3(3.2, 1.1, 1.15), Color("#43b8d8"))
	restaurant.position = Vector3(2.0, 0.42, -3.15)
	ship_root.add_child(restaurant)
	var roof := _box(Vector3(3.55, 0.18, 1.35), Color("#dce8e7"))
	roof.position = Vector3(2.0, 1.08, -3.15)
	roof.rotation_degrees.z = 2
	ship_root.add_child(roof)
	var awning := _box(Vector3(2.5, 0.08, 0.58), Color("#37c7d8"))
	awning.position = Vector3(2.75, 0.72, -2.35)
	ship_root.add_child(awning)
	for i in range(4):
		var window := _box(Vector3(0.28, 0.28, 0.035), Color("#d9f7ff"))
		window.position = Vector3(0.95 + float(i) * 0.52, 0.56, -2.56)
		ship_root.add_child(window)
	var sign := _cylinder(0.24, 0.055, Color("#1f6eb8"))
	sign.position = Vector3(0.08, 0.72, -2.56)
	sign.rotation_degrees = Vector3(90, 0, 0)
	ship_root.add_child(sign)

	for i in range(13):
		var trunk := _cylinder(0.06, 0.7, Color("#6f4b2f"))
		trunk.position = Vector3(-6.2 + float(i) * 0.95, 0.15, -5.5)
		ship_root.add_child(trunk)
		var crown := _box(Vector3(0.55, 0.55, 0.55), Color("#4f8f48"))
		crown.position = trunk.position + Vector3(0, 0.55, 0)
		ship_root.add_child(crown)

	var patio := _box(Vector3(8.0, 0.1, 4.4), Color("#9b744d"))
	patio.position = Vector3(0.55, -0.04, 1.35)
	ship_root.add_child(patio)
	_attach_lobby_area()

func _attach_table_area() -> void:
	_build_table()

	seat_root = Node3D.new()
	ship_root.add_child(seat_root)
	trick_root = Node3D.new()
	ship_root.add_child(trick_root)

func _attach_lobby_area() -> void:
	seat_root = Node3D.new()
	ship_root.add_child(seat_root)
	trick_root = Node3D.new()
	ship_root.add_child(trick_root)

	var ready_sign := _box(Vector3(1.55, 0.92, 0.08), Color("#172022"))
	ready_sign.position = Vector3(-2.6, 0.65, 2.7)
	ship_root.add_child(ready_sign)
	var ready_label := Label3D.new()
	ready_label.text = "LOBBY\nWASD MOVE\nRIGHT DRAG LOOK"
	ready_label.font_size = 24
	ready_label.modulate = Color("#ffe18f")
	ready_label.outline_size = 6
	ready_label.outline_modulate = Color("#17110c")
	ready_label.position = Vector3(-2.6, 0.78, 2.64)
	ready_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	ship_root.add_child(ready_label)

func _build_space_map() -> void:
	table_felt_color = Color("#15204f")
	table_rail_color = Color("#6fd3ff")
	_set_world_colors(Color("#070a1d"), Color("#6e84c8"), 0.7)
	var platform := _cylinder(3.9, 0.22, Color("#1a2142"))
	platform.position = Vector3(0, -0.08, 0)
	ship_root.add_child(platform)
	var ring := _cylinder(4.15, 0.08, Color("#334b8f"))
	ring.position = Vector3(0, 0.08, 0)
	ship_root.add_child(ring)
	for i in range(34):
		var star := _box(Vector3(0.035, 0.035, 0.035), Color("#f5f0c7"))
		var angle := float(i) * 1.91
		var radius := 5.0 + float(i % 7) * 0.7
		star.position = Vector3(cos(angle) * radius, 0.7 + float(i % 5) * 0.42, sin(angle) * radius)
		ocean_root.add_child(star)
	for i in range(5):
		var panel := _box(Vector3(0.55, 0.08, 0.18), Color("#6fd3ff"))
		panel.position = Vector3(-1.1 + float(i) * 0.55, 0.18, -3.0)
		ship_root.add_child(panel)
	for i in range(3):
		var planet := _cylinder(0.22 + float(i) * 0.05, 0.16, [Color("#d66a45"), Color("#7bc7d9"), Color("#d6b85f")][i])
		planet.position = Vector3(-4.4 + float(i) * 4.1, 1.15 + float(i) * 0.35, 3.7)
		planet.rotation_degrees = Vector3(90, 0, 0)
		ocean_root.add_child(planet)
	_attach_table_area()

func _build_living_room_map() -> void:
	table_felt_color = Color("#256045")
	table_rail_color = Color("#7c5637")
	_set_world_colors(Color("#b98d66"), Color("#f0d4a8"), 1.05)
	var floor := _box(Vector3(8.2, 0.12, 6.2), Color("#9a6a3f"))
	floor.position = Vector3(0, -0.18, 0)
	ship_root.add_child(floor)
	var back_wall := _box(Vector3(8.2, 3.2, 0.16), Color("#8f6948"))
	back_wall.position = Vector3(0, 1.25, -3.05)
	ship_root.add_child(back_wall)
	var side_wall := _box(Vector3(0.16, 3.2, 6.2), Color("#7d5a40"))
	side_wall.position = Vector3(-4.05, 1.25, 0)
	ship_root.add_child(side_wall)
	for i in range(5):
		var plank := _box(Vector3(0.035, 0.018, 6.0), Color("#6e492d"))
		plank.position = Vector3(-2.8 + float(i) * 1.4, -0.1, 0)
		ship_root.add_child(plank)
	var couch := _box(Vector3(1.55, 0.46, 0.55), Color("#7c4055"))
	couch.position = Vector3(-2.35, 0.25, -2.35)
	ship_root.add_child(couch)
	var lamp_stand := _cylinder(0.035, 0.9, Color("#3b2b21"))
	lamp_stand.position = Vector3(2.8, 0.36, -2.35)
	ship_root.add_child(lamp_stand)
	var lamp_shade := _box(Vector3(0.42, 0.28, 0.42), Color("#e9c46a"))
	lamp_shade.position = Vector3(2.8, 0.9, -2.35)
	ship_root.add_child(lamp_shade)
	var picture_frame := _box(Vector3(1.05, 0.72, 0.06), Color("#3c2b22"))
	picture_frame.position = Vector3(-1.15, 1.55, -2.93)
	ship_root.add_child(picture_frame)
	var picture_center := _box(Vector3(0.82, 0.52, 0.065), Color("#6aa5d8"))
	picture_center.position = Vector3(-1.15, 1.55, -2.965)
	ship_root.add_child(picture_center)
	var plant_pot := _cylinder(0.22, 0.28, Color("#9b4d2b"))
	plant_pot.position = Vector3(3.1, 0.05, 2.35)
	ship_root.add_child(plant_pot)
	for i in range(4):
		var leaf := _box(Vector3(0.12, 0.5, 0.04), Color("#2e8b57"))
		leaf.position = Vector3(3.1, 0.45, 2.35)
		leaf.rotation_degrees = Vector3(20, float(i) * 90.0, 26)
		ship_root.add_child(leaf)
	_attach_table_area()

func _build_jungle_map() -> void:
	table_felt_color = Color("#1d6b34")
	table_rail_color = Color("#6a4423")
	_set_world_colors(Color("#4a8f6b"), Color("#a7d68d"), 1.0)
	var ground := _box(Vector3(8.5, 0.14, 6.4), Color("#287347"))
	ground.position = Vector3(0, -0.2, 0)
	ship_root.add_child(ground)
	for i in range(10):
		var angle := TAU * float(i) / 10.0
		var radius := 3.7 + float(i % 3) * 0.35
		var trunk := _cylinder(0.11, 1.8 + float(i % 2) * 0.35, Color("#6a4423"))
		trunk.position = Vector3(cos(angle) * radius, 0.65, sin(angle) * radius)
		ship_root.add_child(trunk)
		for leaf_index in range(3):
			var leaf := _box(Vector3(0.72, 0.18, 0.28), Color("#1f8f46"))
			leaf.position = trunk.position + Vector3(0, 1.0 + float(leaf_index) * 0.14, 0)
			leaf.rotation_degrees = Vector3(0, rad_to_deg(angle) + leaf_index * 58, 20)
			ship_root.add_child(leaf)
	for i in range(6):
		var vine := _box(Vector3(0.045, 1.2, 0.045), Color("#2c6f2f"))
		vine.position = Vector3(-3.2 + float(i) * 1.2, 1.05, -2.8)
		vine.rotation_degrees.z = sin(float(i)) * 12.0
		ship_root.add_child(vine)
	for i in range(9):
		var flower := _box(Vector3(0.12, 0.04, 0.12), [Color("#f0d28a"), Color("#d86b9b"), Color("#f7f1e3")][i % 3])
		flower.position = Vector3(-3.2 + float(i % 5) * 1.25, -0.08, 2.4 - float(i / 5) * 0.7)
		ship_root.add_child(flower)
	_attach_table_area()

func _build_table() -> void:
	var table := MeshInstance3D.new()
	var table_mesh := CylinderMesh.new()
	table_mesh.top_radius = 2.25
	table_mesh.bottom_radius = 2.35
	table_mesh.height = 0.28
	table_mesh.radial_segments = 16
	table.mesh = table_mesh
	table.material_override = _mat(table_felt_color)
	table.position.y = 0.2
	ship_root.add_child(table)

	var rail := MeshInstance3D.new()
	var rail_mesh := CylinderMesh.new()
	rail_mesh.top_radius = 2.48
	rail_mesh.bottom_radius = 2.48
	rail_mesh.height = 0.12
	rail_mesh.radial_segments = 16
	rail.mesh = rail_mesh
	rail.material_override = _mat(table_rail_color)
	rail.position.y = 0.44
	ship_root.add_child(rail)

	var table_top := MeshInstance3D.new()
	var top_mesh := CylinderMesh.new()
	top_mesh.top_radius = 2.08
	top_mesh.bottom_radius = 2.08
	top_mesh.height = 0.08
	top_mesh.radial_segments = 16
	table_top.mesh = top_mesh
	table_top.material_override = _mat(table_felt_color)
	table_top.position.y = 0.52
	ship_root.add_child(table_top)

	for i in range(12):
		var tick := _box(Vector3(0.045, 0.035, 0.28), table_rail_color.lightened(0.12))
		var angle := TAU * float(i) / 12.0
		tick.position = Vector3(cos(angle) * 2.24, 0.59, sin(angle) * 2.24)
		tick.rotation_degrees.y = -rad_to_deg(angle)
		ship_root.add_child(tick)
func _build_jolly_roger() -> void:
	for i in range(5):
		var strip := _box(Vector3(0.18, 0.5, 0.035), Color("#151515"))
		strip.position = Vector3(float(i) * 0.18, 0, 0)
		flag_root.add_child(strip)
		flag_strips.append(strip)

	var skull := _box(Vector3(0.23, 0.18, 0.045), Color("#f2ead2"))
	skull.position = Vector3(0.38, 0.08, -0.035)
	flag_root.add_child(skull)
	var jaw := _box(Vector3(0.15, 0.08, 0.045), Color("#f2ead2"))
	jaw.position = Vector3(0.38, -0.06, -0.035)
	flag_root.add_child(jaw)
	var bone_a := _box(Vector3(0.52, 0.045, 0.045), Color("#f2ead2"))
	bone_a.position = Vector3(0.38, -0.2, -0.035)
	bone_a.rotation_degrees.z = 22
	flag_root.add_child(bone_a)
	var bone_b := _box(Vector3(0.52, 0.045, 0.045), Color("#f2ead2"))
	bone_b.position = Vector3(0.38, -0.2, -0.035)
	bone_b.rotation_degrees.z = -22
	flag_root.add_child(bone_b)

func _rebuild_seats(players: int) -> void:
	if not seat_root:
		return
	for child in seat_root.get_children():
		child.queue_free()
	seats.clear()
	seat_base_positions.clear()
	seat_base_rotations.clear()
	seat_moods.clear()
	seat_count = players
	for seat in range(players):
		var avatar := _make_avatar(seat)
		var position := Vector3.ZERO
		var rotation := 0.0
		if camera_mode == "lobby_walk":
			position = _lobby_spawn_position(seat)
			rotation = deg_to_rad(180.0)
		else:
			var angle := (TAU * float(seat) / float(players)) - PI * 0.5
			position = Vector3(cos(angle) * 3.05, 0.36, sin(angle) * 3.05)
			rotation = -angle + PI * 0.5
		avatar.position = position
		avatar.rotation.y = rotation
		seat_root.add_child(avatar)
		seats.append(avatar)
		seat_base_positions.append(position)
		seat_base_rotations.append(rotation)
		seat_moods.append("neutral")

func _lobby_spawn_position(seat: int) -> Vector3:
	var columns := 5
	var x := -2.8 + float(seat % columns) * 1.4
	var z := 2.75 - float(seat / columns) * 1.05
	return Vector3(x, 0.16, z)

func _make_avatar(seat: int, animal := "fox") -> Node3D:
	var root := Node3D.new()
	root.name = "Seat%d" % seat
	root.set_meta("animal", animal)
	var color: Color = ANIMAL_COLORS.get(animal, AVATAR_COLORS[seat % AVATAR_COLORS.size()])
	var accent: Color = color.lightened(0.18)

	var body := _box(Vector3(0.54, 0.62, 0.34), color)
	body.name = "Body"
	body.position = Vector3(0, 0.24, 0)
	root.add_child(body)

	var head := _box(Vector3(0.52, 0.42, 0.42), accent)
	head.name = "Head"
	head.position = Vector3(0, 0.78, -0.03)
	root.add_child(head)

	var ear_size := _animal_ear_size(animal)
	var left_ear := _box(ear_size, accent.darkened(0.08))
	left_ear.position = Vector3(-0.19, 1.08 + ear_size.y * 0.45, -0.03)
	left_ear.rotation_degrees.z = _animal_ear_tilt(animal)
	root.add_child(left_ear)
	var right_ear := _box(ear_size, accent.darkened(0.08))
	right_ear.position = Vector3(0.19, 1.08 + ear_size.y * 0.45, -0.03)
	right_ear.rotation_degrees.z = -_animal_ear_tilt(animal)
	root.add_child(right_ear)

	var snout := _box(_animal_snout_size(animal), Color("#f1d2a4"))
	snout.position = Vector3(0, 0.76, -0.26)
	root.add_child(snout)
	if animal in ["lion", "tiger"]:
		var mane := _box(Vector3(0.65, 0.12, 0.48), color.darkened(0.18))
		mane.position = Vector3(0, 0.98, -0.02)
		root.add_child(mane)
	if animal == "lizard":
		for i in range(3):
			var crest := _box(Vector3(0.08, 0.13, 0.06), accent.lightened(0.16))
			crest.position = Vector3(0, 1.05 + float(i) * 0.08, -0.04 + float(i) * 0.08)
			root.add_child(crest)
	var eye_l := _box(Vector3(0.055, 0.055, 0.035), Color("#101010"))
	eye_l.position = Vector3(-0.11, 0.86, -0.25)
	root.add_child(eye_l)
	var eye_r := _box(Vector3(0.055, 0.055, 0.035), Color("#101010"))
	eye_r.position = Vector3(0.11, 0.86, -0.25)
	root.add_child(eye_r)

	var mouth := _box(Vector3(0.16, 0.035, 0.035), Color("#321f1b"))
	mouth.name = "Mouth"
	mouth.position = Vector3(0, 0.68, -0.34)
	root.add_child(mouth)

	for i in range(4):
		var card := _box(Vector3(0.12, 0.22, 0.025), Color("#f9f4e8"))
		card.position = Vector3(-0.18 + float(i) * 0.12, 0.48, -0.35)
		card.rotation_degrees = Vector3(-12, -14 + i * 9, 0)
		root.add_child(card)

	var name_label := Label3D.new()
	name_label.name = "Name"
	name_label.text = "P%d" % (seat + 1)
	name_label.font_size = 28
	name_label.pixel_size = 0.007
	name_label.modulate = Color("#f9f4e8")
	name_label.outline_size = 8
	name_label.outline_modulate = Color("#000000")
	name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_label.no_depth_test = true
	name_label.position = Vector3(0, 1.5, 0)
	root.add_child(name_label)

	var score_label := Label3D.new()
	score_label.name = "Score"
	score_label.text = "0p  b-  t0"
	score_label.font_size = 21
	score_label.pixel_size = 0.006
	score_label.modulate = Color("#fff6d8")
	score_label.outline_size = 7
	score_label.outline_modulate = Color("#000000")
	score_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	score_label.no_depth_test = true
	score_label.position = Vector3(0, 1.68, 0)
	root.add_child(score_label)

	var trick_pile := Node3D.new()
	trick_pile.name = "TrickPile"
	trick_pile.position = Vector3(0.62, 0.15, -0.08)
	root.add_child(trick_pile)

	var active_marker := _box(Vector3(0.82, 0.035, 0.82), Color("#f0d28a"))
	active_marker.name = "Active"
	active_marker.position = Vector3(0, 0.02, 0)
	active_marker.visible = false
	root.add_child(active_marker)

	var turn_indicator := Label3D.new()
	turn_indicator.name = "TurnIndicator"
	turn_indicator.text = "TURN"
	turn_indicator.font_size = 26
	turn_indicator.pixel_size = 0.006
	turn_indicator.modulate = Color("#ffe18f")
	turn_indicator.outline_size = 8
	turn_indicator.outline_modulate = Color("#000000")
	turn_indicator.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	turn_indicator.no_depth_test = true
	turn_indicator.position = Vector3(0, 1.95, 0)
	turn_indicator.visible = false
	root.add_child(turn_indicator)

	var emote_anchor := Node3D.new()
	emote_anchor.name = "Emote"
	emote_anchor.position = Vector3(0, 1.12, -0.58)
	root.add_child(emote_anchor)
	return root

func _animal_ear_size(animal: String) -> Vector3:
	match animal:
		"bunny":
			return Vector3(0.13, 0.48, 0.11)
		"bear":
			return Vector3(0.18, 0.16, 0.13)
		"lizard":
			return Vector3(0.1, 0.12, 0.1)
		"lion", "tiger", "fox", "cat":
			return Vector3(0.16, 0.28, 0.11)
		"dog":
			return Vector3(0.16, 0.34, 0.1)
	return Vector3(0.15, 0.22, 0.12)

func _animal_ear_tilt(animal: String) -> float:
	match animal:
		"bunny":
			return -4.0
		"dog":
			return 16.0
		"fox", "cat", "lion", "tiger":
			return -12.0
	return 0.0

func _animal_snout_size(animal: String) -> Vector3:
	match animal:
		"bear", "dog":
			return Vector3(0.3, 0.17, 0.16)
		"fox":
			return Vector3(0.28, 0.13, 0.2)
		"lizard":
			return Vector3(0.34, 0.1, 0.16)
	return Vector3(0.24, 0.14, 0.14)

func _update_seats(table_state: Dictionary, my_seat: int) -> void:
	current_active = int(table_state.get("active_player", -1))
	var names: Array = table_state.get("names", [])
	var connected: Array = table_state.get("connected", [])
	var profiles: Array = table_state.get("profiles", [])
	var phase := str(table_state.get("phase", ""))
	var bids: Array = table_state.get("bids", [])
	var tricks: Array = table_state.get("tricks_won", [])
	var scores: Array = table_state.get("scores", [])
	var submitted_bids: Array = table_state.get("bid_submitted", [])
	var lobby_avatars: Array = table_state.get("lobby_avatars", [])
	for seat in range(min(seats.size(), seat_count)):
		var avatar: Node3D = seats[seat]
		var animal := "fox"
		if seat < profiles.size() and typeof(profiles[seat]) == TYPE_DICTIONARY:
			animal = str(profiles[seat].get("animal", "fox"))
		if str(avatar.get_meta("animal", "")) != animal:
			var rebuilt := _make_avatar(seat, animal)
			rebuilt.position = avatar.position
			rebuilt.rotation = avatar.rotation
			seat_root.add_child(rebuilt)
			seat_root.move_child(rebuilt, avatar.get_index())
			seats[seat] = rebuilt
			avatar.queue_free()
			avatar = rebuilt
		var label := avatar.get_node_or_null("Name") as Label3D
		if label:
			var name := "Seat %d" % (seat + 1)
			if seat < names.size():
				name = str(names[seat])
			var display_name := "You" if seat == my_seat else name
			label.text = "%s <" % display_name if seat == current_active else display_name
			label.modulate = Color("#ffe18f") if seat == current_active else Color("#f9f4e8")
		if camera_mode == "lobby_walk":
			var lobby_info: Dictionary = {}
			if seat < lobby_avatars.size() and typeof(lobby_avatars[seat]) == TYPE_DICTIONARY:
				lobby_info = lobby_avatars[seat]
			if seat == my_seat:
				avatar.position = Vector3(lobby_walk_position.x, 0.16, lobby_walk_position.z)
				avatar.rotation.y = deg_to_rad(lobby_avatar_yaw)
			elif not lobby_info.is_empty():
				var target := Vector3(float(lobby_info.get("x", avatar.position.x)), 0.16, float(lobby_info.get("z", avatar.position.z)))
				avatar.position = avatar.position.lerp(target, 0.25)
				avatar.rotation.y = lerp_angle(avatar.rotation.y, deg_to_rad(float(lobby_info.get("yaw", rad_to_deg(avatar.rotation.y)))), 0.25)
			else:
				avatar.position = avatar.position.lerp(_lobby_spawn_position(seat), 0.08)
			var lobby_status := avatar.get_node_or_null("Score") as Label3D
			if lobby_status:
				var ready: Array = table_state.get("ready", [])
				lobby_status.text = "Ready" if seat < ready.size() and bool(ready[seat]) else "Waiting"
				lobby_status.modulate = Color("#93df9d") if seat < ready.size() and bool(ready[seat]) else Color("#fff6d8")
			avatar.visible = seat != my_seat and (seat >= connected.size() or bool(connected[seat]))
			seat_moods[seat] = "neutral"
			continue
		var score_label := avatar.get_node_or_null("Score") as Label3D
		if score_label:
			score_label.text = _seat_score_text(seat, phase, scores, bids, submitted_bids, tricks)
			score_label.modulate = Color("#ffe18f") if seat == current_active else Color("#fff6d8")
		var trick_pile := avatar.get_node_or_null("TrickPile") as Node3D
		if trick_pile:
			var pile_count := 0
			if seat < tricks.size():
				pile_count = int(tricks[seat])
			_update_trick_pile(trick_pile, pile_count)
		var active := avatar.get_node_or_null("Active") as Node3D
		if active:
			active.visible = seat == current_active
		var turn_indicator := avatar.get_node_or_null("TurnIndicator") as Label3D
		if turn_indicator:
			turn_indicator.visible = seat == current_active
		avatar.visible = seat >= connected.size() or bool(connected[seat])
		var mood := "neutral"
		if phase in ["round_end", "game_end"] and seat < bids.size() and seat < tricks.size() and bids[seat] != null:
			mood = "happy" if int(bids[seat]) == int(tricks[seat]) else "sad"
		seat_moods[seat] = mood
		var mouth := avatar.get_node_or_null("Mouth") as Node3D
		if mouth:
			mouth.rotation_degrees.z = 0 if mood != "sad" else 12

func _seat_score_text(seat: int, phase: String, scores: Array, bids: Array, submitted_bids: Array, tricks: Array) -> String:
	var points := 0
	if seat < scores.size():
		points = int(scores[seat])
	var trick_count := 0
	if seat < tricks.size():
		trick_count = int(tricks[seat])
	var bid_text := "?"
	if phase == "bidding":
		bid_text = "in" if seat < submitted_bids.size() and bool(submitted_bids[seat]) else "..."
	elif seat < bids.size() and bids[seat] != null:
		bid_text = str(bids[seat])
	return "%dp  b%s  t%d" % [points, bid_text, trick_count]

func _update_trick_pile(pile: Node3D, trick_count: int) -> void:
	for child in pile.get_children():
		child.queue_free()
	if trick_count <= 0:
		return
	var visible_cards: int = mini(trick_count, 8)
	for i in range(visible_cards):
		var card := _box(Vector3(0.2, 0.018, 0.28), Color("#f9f4e8"))
		card.position = Vector3(float(i) * 0.018, float(i) * 0.012, float(i) * -0.01)
		card.rotation_degrees = Vector3(0, 10 + float(i) * 3.0, 0)
		pile.add_child(card)
	if trick_count > 1:
		var count_label := Label3D.new()
		count_label.text = "x%d" % trick_count
		count_label.font_size = 18
		count_label.modulate = Color("#f0d28a")
		count_label.outline_size = 4
		count_label.outline_modulate = Color("#17110c")
		count_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		count_label.no_depth_test = true
		count_label.position = Vector3(0.18, 0.2, 0)
		pile.add_child(count_label)

func _show_middle_finger_emote(seat: int) -> void:
	var avatar := seats[seat] as Node3D
	if not avatar:
		return
	var anchor := avatar.get_node_or_null("Emote") as Node3D
	if not anchor:
		return
	for child in anchor.get_children():
		child.queue_free()
	var hand := Node3D.new()
	hand.name = "HiddenHand"
	hand.set_meta("expires_at", time + 2.6)
	hand.scale = Vector3(0.1, 0.1, 0.1)
	anchor.add_child(hand)

	var skin := Color("#f0c494")
	var palm := _box(Vector3(0.24, 0.26, 0.09), skin)
	palm.position = Vector3(0, 0.0, 0)
	hand.add_child(palm)

	var middle := _box(Vector3(0.075, 0.46, 0.07), skin.lightened(0.05))
	middle.position = Vector3(0, 0.34, 0)
	hand.add_child(middle)

	for x in [-0.16, -0.08, 0.08, 0.16]:
		var folded := _box(Vector3(0.065, 0.16, 0.065), skin.darkened(0.03))
		folded.position = Vector3(x, 0.08, -0.02)
		folded.rotation_degrees.z = 12.0 if x < 0 else -12.0
		hand.add_child(folded)

	var thumb := _box(Vector3(0.08, 0.2, 0.07), skin.darkened(0.02))
	thumb.position = Vector3(-0.2, -0.01, 0)
	thumb.rotation_degrees.z = 52.0
	hand.add_child(thumb)

	var label := Label3D.new()
	label.text = "!"
	label.font_size = 30
	label.modulate = Color("#f0d28a")
	label.outline_size = 4
	label.outline_modulate = Color("#17110c")
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = Vector3(0.22, 0.58, 0)
	hand.add_child(label)

func _animate_emotes() -> void:
	for avatar in seats:
		if not avatar:
			continue
		var anchor := avatar.get_node_or_null("Emote") as Node3D
		if not anchor:
			continue
		for child in anchor.get_children():
			var expires := float(child.get_meta("expires_at", 0.0))
			if expires > 0.0 and time > expires:
				child.queue_free()
				continue
			var remaining := maxf(0.0, expires - time)
			var appear := clampf(1.0 - remaining / 2.6, 0.0, 1.0)
			var pop := minf(1.0, appear * 8.0)
			child.scale = Vector3.ONE * (0.78 + pop * 0.42)
			child.position.y = 0.05 + absf(sin(time * 6.0)) * 0.04
			child.rotation_degrees = Vector3(-10.0, sin(time * 13.0) * 4.0, sin(time * 10.0) * 6.0)

func _update_trick(table_state: Dictionary) -> void:
	for child in trick_root.get_children():
		child.queue_free()
	var trick: Array = table_state.get("trick", [])
	for i in range(trick.size()):
		var play: Dictionary = trick[i]
		var card: Dictionary = play.get("card", {})
		var card_node := _make_readable_card(card, 1.0)
		var card_box := card_node
		card_box.position = Vector3(-0.5 + float(i) * 0.22, 0.62 + float(i) * 0.01, 0.02 + float(i) * 0.05)
		card_box.rotation_degrees = Vector3(0, -18 + i * 9, 0)
		trick_root.add_child(card_node)

func _rebuild_player_hand(hand: Array) -> void:
	if not hand_root:
		return
	for child in hand_root.get_children():
		child.queue_free()
	if hand.is_empty():
		return
	var count := hand.size()
	for i in range(count):
		var card: Dictionary = hand[i]
		var card_node := _make_readable_card(card, 0.84)
		card_node.name = "HandCard%d" % i
		card_node.set_meta("base_scale", 0.84)
		_apply_hand_card_transform(card_node, i, count, false)
		hand_root.add_child(card_node)

func _animate_waves() -> void:
	for i in range(wave_strips.size()):
		var wave: Node3D = wave_strips[i]
		wave.position.x += 0.012 + float(i % 3) * 0.004
		wave.position.y = -0.35 + sin(time * 2.2 + float(i)) * 0.025
		if wave.position.x > 8.0:
			wave.position.x = -8.0

func _animate_flag() -> void:
	for i in range(flag_strips.size()):
		var strip: Node3D = flag_strips[i]
		strip.position.z = sin(time * 5.0 + float(i) * 0.75) * 0.055
		strip.rotation_degrees.y = sin(time * 4.2 + float(i)) * 8.0

func _animate_seats() -> void:
	for seat in range(seats.size()):
		var avatar: Node3D = seats[seat]
		if seat >= seat_base_positions.size():
			continue
		var base: Vector3 = seat_base_positions[seat]
		var mood := str(seat_moods[seat]) if seat < seat_moods.size() else "neutral"
		var bounce := 0.0
		var lean := 0.0
		if mood == "happy":
			bounce = absf(sin(time * 5.2 + float(seat))) * 0.18
			lean = sin(time * 7.0 + float(seat)) * 6.0
		elif mood == "sad":
			bounce = -0.08
			lean = -9.0
		elif seat == current_active:
			bounce = absf(sin(time * 3.2)) * 0.06
		else:
			bounce = sin(time * 1.4 + float(seat) * 0.7) * 0.018
		avatar.position = base + Vector3(0, bounce, 0)
		avatar.rotation.y = seat_base_rotations[seat]
		avatar.rotation_degrees.x = lean
		avatar.rotation_degrees.z = sin(time * 1.7 + float(seat)) * (1.8 if seat == current_active else 0.8)
		var active := avatar.get_node_or_null("Active") as Node3D
		if active and active.visible:
			var pulse := 1.0 + absf(sin(time * 5.8)) * 0.28
			active.scale = Vector3(pulse, 1.0, pulse)
		var turn_indicator := avatar.get_node_or_null("TurnIndicator") as Label3D
		if turn_indicator and turn_indicator.visible:
			var flash := 0.58 + absf(sin(time * 6.4)) * 0.42
			turn_indicator.modulate = Color(1.0, 0.86, 0.28, flash)
			turn_indicator.scale = Vector3.ONE * (1.0 + absf(sin(time * 6.4)) * 0.12)
	_animate_player_hand()

func _animate_player_hand() -> void:
	if not hand_root or hand_root.get_child_count() == 0:
		return
	var count := hand_root.get_child_count()
	for i in range(count):
		var card := hand_root.get_child(i) as Node3D
		if not card:
			continue
		var is_hovered := i == hovered_hand_index
		_apply_hand_card_transform(card, i, count, is_hovered)
		_set_card_hover_visual(card, is_hovered)

func _apply_hand_card_transform(card: Node3D, index: int, count: int, hovered: bool) -> void:
	var offset := float(index) - float(count - 1) * 0.5
	var spread := 0.43
	if count >= 7:
		spread = 0.36
	if count >= 10:
		spread = 3.25 / float(max(count - 1, 1))
	var lift := 0.095 if hovered else 0.0
	var fan_turn := offset * 2.4
	var base_scale := float(card.get_meta("base_scale", card.scale.x))
	card.scale = Vector3.ONE * base_scale * (1.08 if hovered else 1.0)
	card.position = Vector3(
		offset * spread,
		-0.5 + lift - absf(offset) * 0.006 + sin(time * 2.0 + float(index)) * 0.002,
		-1.08 - absf(offset) * 0.008 - (0.04 if hovered else 0.0)
	)
	card.rotation_degrees = Vector3(
		62.0 + absf(offset) * 0.45 + sin(time * 1.5 + float(index)) * 0.25,
		-offset * 0.25,
		-fan_turn
	)

func _update_lobby_walk(delta: float) -> void:
	if camera_mode != "lobby_walk":
		return
	var input := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		input.z -= 1.0
	if Input.is_key_pressed(KEY_S):
		input.z += 1.0
	if Input.is_key_pressed(KEY_A):
		input.x -= 1.0
	if Input.is_key_pressed(KEY_D):
		input.x += 1.0
	if input == Vector3.ZERO:
		return
	input = input.normalized()
	var yaw_radians := deg_to_rad(lobby_walk_yaw)
	var forward := Vector3(-sin(yaw_radians), 0, -cos(yaw_radians)).normalized()
	var right := Vector3(-forward.z, 0, forward.x).normalized()
	var movement := (forward * -input.z + right * input.x).normalized()
	lobby_walk_position += movement * delta * 2.15
	lobby_avatar_yaw = rad_to_deg(atan2(-movement.x, -movement.z))
	lobby_walk_position.x = clampf(lobby_walk_position.x, -5.75, 5.75)
	lobby_walk_position.z = clampf(lobby_walk_position.z, -5.65, 4.6)
	lobby_walk_position.y = 1.35

func _update_camera() -> void:
	if not camera:
		return
	if camera_mode == "lobby_walk":
		camera.global_position = camera.global_position.lerp(lobby_walk_position, 0.2)
		var yaw_radians := deg_to_rad(lobby_walk_yaw)
		var pitch_radians := deg_to_rad(lobby_walk_pitch)
		var forward := Vector3(-sin(yaw_radians) * cos(pitch_radians), sin(pitch_radians), -cos(yaw_radians) * cos(pitch_radians)).normalized()
		camera.look_at(camera.global_position + forward, Vector3.UP)
		camera.fov = lerpf(camera.fov, 58.0, 0.08)
		return
	if camera_mode != "seat" or local_seat >= seat_base_positions.size():
		camera.position = camera.position.lerp(Vector3(0, 5.9, 6.4), 0.08)
		camera.rotation_degrees = camera.rotation_degrees.lerp(Vector3(-50, 0, 0), 0.08)
		camera.fov = lerpf(camera.fov, 44.0, 0.08)
		return

	var seat_pos: Vector3 = seat_base_positions[local_seat]
	var seat_angle: float = atan2(seat_pos.z, seat_pos.x)
	var inward := Vector3(-cos(seat_angle), 0, -sin(seat_angle)).normalized()
	var side := Vector3(-inward.z, 0, inward.x)
	var base_pos := ship_root.to_global(seat_pos + inward * 0.35 + Vector3(0, 1.24, 0))
	var natural_yaw := rad_to_deg(atan2(-inward.x, -inward.z))
	var yaw := natural_yaw + look_yaw
	var pitch := look_pitch
	if not look_enabled:
		look_yaw = lerpf(look_yaw, 0.0, 0.08)
		look_pitch = lerpf(look_pitch, -10.0, 0.08)
		yaw = natural_yaw + look_yaw
		pitch = look_pitch
	var sway := side * sin(time * 1.8) * 0.025
	camera.global_position = camera.global_position.lerp(base_pos + sway, 0.18)
	var yaw_radians := deg_to_rad(yaw)
	var pitch_radians := deg_to_rad(pitch)
	var forward := Vector3(-sin(yaw_radians) * cos(pitch_radians), sin(pitch_radians), -cos(yaw_radians) * cos(pitch_radians)).normalized()
	camera.look_at(camera.global_position + forward, Vector3.UP)
	camera.fov = lerpf(camera.fov, 64.0, 0.08)

func _make_readable_card(card: Dictionary, scale_factor: float) -> Node3D:
	var root := Node3D.new()
	root.scale = Vector3.ONE * scale_factor
	var shadow := _box(Vector3(0.37, 0.012, 0.51), Color(0, 0, 0, 0.42))
	shadow.name = "Shadow"
	shadow.position = Vector3(0.018, -0.012, 0.018)
	root.add_child(shadow)
	var edge := _box(Vector3(0.37, 0.028, 0.51), Color("#05070d"))
	edge.name = "Edge"
	root.add_child(edge)
	var base := _box(Vector3(0.34, 0.025, 0.48), Color("#fffaf0"))
	base.name = "Face"
	base.material_override = _card_face_mat(Color("#fffaf0"))
	base.position = Vector3(0, 0.006, 0)
	root.add_child(base)
	var border := Node3D.new()
	border.name = "HoverBorder"
	border.visible = false
	var border_color := Color("#ffe066")
	var top := _box(Vector3(0.37, 0.014, 0.014), border_color)
	top.position = Vector3(0.0, 0.036, -0.248)
	border.add_child(top)
	var bottom := _box(Vector3(0.37, 0.014, 0.014), border_color)
	bottom.position = Vector3(0.0, 0.036, 0.248)
	border.add_child(bottom)
	var left := _box(Vector3(0.014, 0.014, 0.51), border_color)
	left.position = Vector3(-0.178, 0.036, 0.0)
	border.add_child(left)
	var right := _box(Vector3(0.014, 0.014, 0.51), border_color)
	right.position = Vector3(0.178, 0.036, 0.0)
	border.add_child(right)
	root.add_child(border)

	var suit := str(card.get("suit", ""))
	var rank := int(card.get("rank", 0))
	var color: Color = SUIT_COLORS.get(suit, Color("#111111"))
	var rank_text: String = str(RANK_NAMES.get(rank, str(rank)))
	var suit_text: String = str(SUIT_SYMBOLS.get(suit, suit))
	_add_card_label(root, "%s%s" % [rank_text, suit_text], Vector3(-0.095, 0.029, -0.17), 24, 0.0027, color, 0.0)
	_add_card_label(root, suit_text, Vector3(0.0, 0.03, 0.012), 46, 0.0044, color, 0.0)
	_add_card_label(root, "%s%s" % [rank_text, suit_text], Vector3(0.095, 0.029, 0.17), 24, 0.0027, color, 180.0)
	return root

func _add_card_label(root: Node3D, text: String, position: Vector3, font_size: int, pixel_size: float, color: Color, spin_degrees: float) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = font_size
	label.pixel_size = pixel_size
	label.modulate = color
	label.outline_size = 2
	label.outline_modulate = Color("#fffaf0")
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	label.no_depth_test = true
	label.position = position
	label.rotation_degrees = Vector3(-90, 0, spin_degrees)
	root.add_child(label)

func _set_card_hover_visual(card: Node3D, hovered: bool) -> void:
	var face := card.get_node_or_null("Face") as MeshInstance3D
	if not face:
		return
	face.material_override = _card_face_mat(Color("#fff1a6") if hovered else Color("#fffaf0"))
	var shadow := card.get_node_or_null("Shadow") as MeshInstance3D
	if shadow:
		shadow.visible = not hovered
	var border := card.get_node_or_null("HoverBorder") as Node3D
	if border:
		border.visible = hovered

func _hand_signature(hand: Array) -> String:
	var parts: Array = []
	for card in hand:
		parts.append("%s%s" % [str(card.get("suit", "")), str(card.get("rank", ""))])
	return "|".join(parts)

func _box(size: Vector3, color: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = _mat(color)
	return node

func _cylinder(radius: float, height: float, color: Color) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 8
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = _mat(color)
	return node

func _mat(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.88
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	return material

func _card_face_mat(color: Color) -> StandardMaterial3D:
	var material := _mat(color)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material
