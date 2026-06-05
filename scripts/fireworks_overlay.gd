extends Control
class_name FireworksOverlay

var bursts: Array = []
var rng := RandomNumberGenerator.new()
var spawn_timer := 0.0
var enabled := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	rng.randomize()
	set_process(false)
	visible = false

func set_celebrating(value: bool) -> void:
	enabled = value
	visible = value
	set_process(value)
	if not value:
		bursts.clear()
		queue_redraw()

func _process(delta: float) -> void:
	if not enabled:
		return
	spawn_timer -= delta
	if spawn_timer <= 0.0:
		spawn_timer = rng.randf_range(0.45, 0.9)
		_add_burst()

	for burst in bursts:
		burst["age"] += delta
	bursts = bursts.filter(func(burst): return float(burst["age"]) < float(burst["life"]))
	queue_redraw()

func _add_burst() -> void:
	var palette := [Color("#f0d28a"), Color("#76c893"), Color("#f7f1e3"), Color("#e06c6c")]
	bursts.append({
		"position": Vector2(rng.randf_range(size.x * 0.18, size.x * 0.82), rng.randf_range(size.y * 0.12, size.y * 0.5)),
		"color": palette[rng.randi_range(0, palette.size() - 1)],
		"age": 0.0,
		"life": rng.randf_range(1.0, 1.4),
		"rays": rng.randi_range(8, 14),
		"radius": rng.randf_range(34.0, 68.0),
	})

func _draw() -> void:
	for burst in bursts:
		var age: float = burst["age"]
		var life: float = burst["life"]
		var t := clampf(age / life, 0.0, 1.0)
		var alpha := 1.0 - t
		var center: Vector2 = burst["position"]
		var color: Color = burst["color"]
		color.a = alpha * 0.72
		var rays: int = burst["rays"]
		var radius: float = burst["radius"] * t
		for i in range(rays):
			var angle := TAU * float(i) / float(rays)
			var direction := Vector2(cos(angle), sin(angle))
			var inner := center + direction * radius * 0.45
			var outer := center + direction * radius
			draw_line(inner, outer, color, 2.0)
		draw_circle(center, 2.5, color)
