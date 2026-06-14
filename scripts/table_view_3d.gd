extends SubViewportContainer
class_name TableView3D

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
const SUIT_COLORS := {
	"S": Color("#111111"),
	"H": Color("#c8322b"),
	"D": Color("#e86f22"),
	"C": Color("#2367c7"),
}

var viewport: SubViewport
var world_root: Node3D
var ocean_root: Node3D
var ship_root: Node3D
var seat_root: Node3D
var trick_root: Node3D
var flag_root: Node3D
var seats: Array = []
var seat_base_positions: Array = []
var seat_base_rotations: Array = []
var seat_moods: Array = []
var wave_strips: Array = []
var flag_strips: Array = []
var seat_count := 0
var current_active := -1
var time := 0.0

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

func _process(delta: float) -> void:
	time += delta
	if ship_root:
		ship_root.position.y = sin(time * 1.35) * 0.06
		ship_root.rotation_degrees.z = sin(time * 0.9) * 1.6
		ship_root.rotation_degrees.x = cos(time * 0.7) * 1.1
	_animate_waves()
	_animate_flag()
	_animate_seats()

func set_table_state(table_state: Dictionary, my_seat: int) -> void:
	if not is_inside_tree() or table_state.is_empty():
		return
	var players := int(table_state.get("num_players", 0))
	if players <= 0:
		return
	if players != seat_count:
		_rebuild_seats(players)
	_update_seats(table_state, my_seat)
	_update_trick(table_state)

func _build_world() -> void:
	var camera := Camera3D.new()
	camera.position = Vector3(0, 5.9, 6.4)
	camera.rotation_degrees = Vector3(-50, 0, 0)
	camera.fov = 44
	world_root.add_child(camera)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-44, -32, 0)
	sun.light_energy = 1.6
	world_root.add_child(sun)

	var ambient := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#5aa7b9")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#c3e1df")
	env.ambient_light_energy = 0.95
	ambient.environment = env
	world_root.add_child(ambient)

	ocean_root = Node3D.new()
	world_root.add_child(ocean_root)
	_build_ocean()

	ship_root = Node3D.new()
	world_root.add_child(ship_root)
	_build_ship()

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

func _build_ship() -> void:
	var deck := _box(Vector3(6.5, 0.22, 4.1), Color("#8b552f"))
	deck.position = Vector3(0, -0.08, 0)
	ship_root.add_child(deck)

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

	_build_table()

	seat_root = Node3D.new()
	ship_root.add_child(seat_root)
	trick_root = Node3D.new()
	ship_root.add_child(trick_root)

func _build_table() -> void:
	var table := MeshInstance3D.new()
	var table_mesh := CylinderMesh.new()
	table_mesh.top_radius = 2.25
	table_mesh.bottom_radius = 2.35
	table_mesh.height = 0.28
	table_mesh.radial_segments = 16
	table.mesh = table_mesh
	table.material_override = _mat(Color("#0b5a3f"))
	table.position.y = 0.2
	ship_root.add_child(table)

	var rail := MeshInstance3D.new()
	var rail_mesh := CylinderMesh.new()
	rail_mesh.top_radius = 2.48
	rail_mesh.bottom_radius = 2.48
	rail_mesh.height = 0.12
	rail_mesh.radial_segments = 16
	rail.mesh = rail_mesh
	rail.material_override = _mat(Color("#7a4a28"))
	rail.position.y = 0.44
	ship_root.add_child(rail)

	var table_top := MeshInstance3D.new()
	var top_mesh := CylinderMesh.new()
	top_mesh.top_radius = 2.08
	top_mesh.bottom_radius = 2.08
	top_mesh.height = 0.08
	top_mesh.radial_segments = 16
	table_top.mesh = top_mesh
	table_top.material_override = _mat(Color("#0b5a3f"))
	table_top.position.y = 0.52
	ship_root.add_child(table_top)

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
	for child in seat_root.get_children():
		child.queue_free()
	seats.clear()
	seat_base_positions.clear()
	seat_base_rotations.clear()
	seat_moods.clear()
	seat_count = players
	for seat in range(players):
		var angle := (TAU * float(seat) / float(players)) - PI * 0.5
		var avatar := _make_avatar(seat)
		var position := Vector3(cos(angle) * 3.05, 0.36, sin(angle) * 3.05)
		var rotation := -angle + PI * 0.5
		avatar.position = position
		avatar.rotation.y = rotation
		seat_root.add_child(avatar)
		seats.append(avatar)
		seat_base_positions.append(position)
		seat_base_rotations.append(rotation)
		seat_moods.append("neutral")

func _make_avatar(seat: int) -> Node3D:
	var root := Node3D.new()
	root.name = "Seat%d" % seat
	var color: Color = AVATAR_COLORS[seat % AVATAR_COLORS.size()]
	var accent: Color = color.lightened(0.18)

	var body := _box(Vector3(0.54, 0.62, 0.34), color)
	body.name = "Body"
	body.position = Vector3(0, 0.24, 0)
	root.add_child(body)

	var head := _box(Vector3(0.52, 0.42, 0.42), accent)
	head.name = "Head"
	head.position = Vector3(0, 0.78, -0.03)
	root.add_child(head)

	var left_ear := _box(Vector3(0.15, 0.22, 0.12), accent.darkened(0.08))
	left_ear.position = Vector3(-0.19, 1.09, -0.03)
	root.add_child(left_ear)
	var right_ear := _box(Vector3(0.15, 0.22, 0.12), accent.darkened(0.08))
	right_ear.position = Vector3(0.19, 1.09, -0.03)
	root.add_child(right_ear)

	var snout := _box(Vector3(0.24, 0.14, 0.14), Color("#f1d2a4"))
	snout.position = Vector3(0, 0.76, -0.26)
	root.add_child(snout)
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
	name_label.font_size = 22
	name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_label.position = Vector3(0, 1.34, 0)
	root.add_child(name_label)

	var active_marker := _box(Vector3(0.82, 0.035, 0.82), Color("#f0d28a"))
	active_marker.name = "Active"
	active_marker.position = Vector3(0, 0.02, 0)
	active_marker.visible = false
	root.add_child(active_marker)
	return root

func _update_seats(table_state: Dictionary, my_seat: int) -> void:
	current_active = int(table_state.get("active_player", -1))
	var names: Array = table_state.get("names", [])
	var connected: Array = table_state.get("connected", [])
	var phase := str(table_state.get("phase", ""))
	var bids: Array = table_state.get("bids", [])
	var tricks: Array = table_state.get("tricks_won", [])
	for seat in range(min(seats.size(), seat_count)):
		var avatar: Node3D = seats[seat]
		var label := avatar.get_node_or_null("Name") as Label3D
		if label:
			var name := "Seat %d" % (seat + 1)
			if seat < names.size():
				name = str(names[seat])
			label.text = "You" if seat == my_seat else name
		var active := avatar.get_node_or_null("Active") as Node3D
		if active:
			active.visible = seat == current_active
		avatar.visible = seat >= connected.size() or bool(connected[seat])
		var mood := "neutral"
		if phase in ["round_end", "game_end"] and seat < bids.size() and seat < tricks.size() and bids[seat] != null:
			mood = "happy" if int(bids[seat]) == int(tricks[seat]) else "sad"
		seat_moods[seat] = mood
		var mouth := avatar.get_node_or_null("Mouth") as Node3D
		if mouth:
			mouth.rotation_degrees.z = 0 if mood != "sad" else 12

func _update_trick(table_state: Dictionary) -> void:
	for child in trick_root.get_children():
		child.queue_free()
	var trick: Array = table_state.get("trick", [])
	for i in range(trick.size()):
		var play: Dictionary = trick[i]
		var card: Dictionary = play.get("card", {})
		var suit := str(card.get("suit", ""))
		var card_box := _box(Vector3(0.34, 0.025, 0.48), Color("#f9f4e8"))
		card_box.position = Vector3(-0.5 + float(i) * 0.22, 0.62 + float(i) * 0.01, 0.02 + float(i) * 0.05)
		card_box.rotation_degrees = Vector3(0, -18 + i * 9, 0)
		trick_root.add_child(card_box)
		var mark := _box(Vector3(0.16, 0.03, 0.16), SUIT_COLORS.get(suit, Color("#111111")))
		mark.position = card_box.position + Vector3(0, 0.04, 0)
		mark.rotation = card_box.rotation
		trick_root.add_child(mark)

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
		avatar.position = base + Vector3(0, bounce, 0)
		avatar.rotation.y = seat_base_rotations[seat]
		avatar.rotation_degrees.x = lean

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
