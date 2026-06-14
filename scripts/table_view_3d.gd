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
var seat_root: Node3D
var trick_root: Node3D
var seats: Array = []
var seat_count := 0
var current_active := -1

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	stretch = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	viewport = SubViewport.new()
	viewport.size = Vector2i(426, 240)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)

	world_root = Node3D.new()
	viewport.add_child(world_root)
	_build_world()

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
	camera.position = Vector3(0, 5.8, 5.4)
	camera.rotation_degrees = Vector3(-52, 0, 0)
	camera.fov = 45
	world_root.add_child(camera)
	viewport.get_camera_3d()

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, -35, 0)
	light.light_energy = 1.4
	world_root.add_child(light)

	var ambient := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#06251d")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#5e6f68")
	env.ambient_light_energy = 0.9
	ambient.environment = env
	world_root.add_child(ambient)

	var floor := MeshInstance3D.new()
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(12, 8)
	floor.mesh = floor_mesh
	floor.material_override = _mat(Color("#073927"))
	floor.position.y = -0.16
	world_root.add_child(floor)

	var table := MeshInstance3D.new()
	var table_mesh := CylinderMesh.new()
	table_mesh.top_radius = 2.35
	table_mesh.bottom_radius = 2.45
	table_mesh.height = 0.28
	table_mesh.radial_segments = 16
	table.mesh = table_mesh
	table.material_override = _mat(Color("#0b5a3f"))
	world_root.add_child(table)

	var rail := MeshInstance3D.new()
	var rail_mesh := CylinderMesh.new()
	rail_mesh.top_radius = 2.55
	rail_mesh.bottom_radius = 2.55
	rail_mesh.height = 0.12
	rail_mesh.radial_segments = 16
	rail.mesh = rail_mesh
	rail.material_override = _mat(Color("#7a4a28"))
	rail.position.y = 0.16
	world_root.add_child(rail)

	var table_top := MeshInstance3D.new()
	var top_mesh := CylinderMesh.new()
	top_mesh.top_radius = 2.2
	top_mesh.bottom_radius = 2.2
	top_mesh.height = 0.08
	top_mesh.radial_segments = 16
	table_top.mesh = top_mesh
	table_top.material_override = _mat(Color("#0b5a3f"))
	table_top.position.y = 0.24
	world_root.add_child(table_top)

	seat_root = Node3D.new()
	world_root.add_child(seat_root)
	trick_root = Node3D.new()
	world_root.add_child(trick_root)

func _rebuild_seats(players: int) -> void:
	for child in seat_root.get_children():
		child.queue_free()
	seats.clear()
	seat_count = players
	for seat in range(players):
		var angle := (TAU * float(seat) / float(players)) - PI * 0.5
		var avatar := _make_avatar(seat)
		avatar.position = Vector3(cos(angle) * 3.0, 0.0, sin(angle) * 3.0)
		avatar.rotation.y = -angle + PI * 0.5
		seat_root.add_child(avatar)
		seats.append(avatar)

func _make_avatar(seat: int) -> Node3D:
	var root := Node3D.new()
	root.name = "Seat%d" % seat
	var color: Color = AVATAR_COLORS[seat % AVATAR_COLORS.size()]
	var accent: Color = color.lightened(0.18)

	var body := _box(Vector3(0.52, 0.62, 0.34), color)
	body.name = "Body"
	body.position = Vector3(0, 0.24, 0)
	root.add_child(body)

	var head := _box(Vector3(0.48, 0.42, 0.42), accent)
	head.name = "Head"
	head.position = Vector3(0, 0.78, -0.03)
	root.add_child(head)

	var left_ear := _box(Vector3(0.15, 0.22, 0.12), accent.darkened(0.08))
	left_ear.position = Vector3(-0.18, 1.09, -0.03)
	root.add_child(left_ear)
	var right_ear := _box(Vector3(0.15, 0.22, 0.12), accent.darkened(0.08))
	right_ear.position = Vector3(0.18, 1.09, -0.03)
	root.add_child(right_ear)

	var snout := _box(Vector3(0.24, 0.14, 0.14), Color("#f1d2a4"))
	snout.position = Vector3(0, 0.76, -0.26)
	root.add_child(snout)

	for i in range(3):
		var card := _box(Vector3(0.13, 0.22, 0.025), Color("#f9f4e8"))
		card.position = Vector3(-0.14 + float(i) * 0.14, 0.48, -0.34)
		card.rotation_degrees = Vector3(-12, -10 + i * 10, 0)
		root.add_child(card)

	var name_label := Label3D.new()
	name_label.name = "Name"
	name_label.text = "P%d" % (seat + 1)
	name_label.font_size = 24
	name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_label.position = Vector3(0, 1.34, 0)
	root.add_child(name_label)

	var active_marker := _box(Vector3(0.78, 0.035, 0.78), Color("#f0d28a"))
	active_marker.name = "Active"
	active_marker.position = Vector3(0, 0.02, 0)
	active_marker.visible = false
	root.add_child(active_marker)
	return root

func _update_seats(table_state: Dictionary, my_seat: int) -> void:
	current_active = int(table_state.get("active_player", -1))
	var names: Array = table_state.get("names", [])
	var connected: Array = table_state.get("connected", [])
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

func _update_trick(table_state: Dictionary) -> void:
	for child in trick_root.get_children():
		child.queue_free()
	var trick: Array = table_state.get("trick", [])
	for i in range(trick.size()):
		var play: Dictionary = trick[i]
		var card: Dictionary = play.get("card", {})
		var suit := str(card.get("suit", ""))
		var card_box := _box(Vector3(0.34, 0.025, 0.48), Color("#f9f4e8"))
		card_box.position = Vector3(-0.5 + float(i) * 0.22, 0.24 + float(i) * 0.01, 0.02 + float(i) * 0.05)
		card_box.rotation_degrees = Vector3(0, -18 + i * 9, 0)
		trick_root.add_child(card_box)
		var mark := _box(Vector3(0.16, 0.03, 0.16), SUIT_COLORS.get(suit, Color("#111111")))
		mark.position = card_box.position + Vector3(0, 0.04, 0)
		mark.rotation = card_box.rotation
		trick_root.add_child(mark)

func _box(size: Vector3, color: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = _mat(color)
	return node

func _mat(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	return material
