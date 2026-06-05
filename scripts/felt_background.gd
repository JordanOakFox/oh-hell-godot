extends Control
class_name FeltBackground

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#063b2a"))
	var center: Vector2 = size * 0.5
	var radius: float = max(size.x, size.y) * 0.7
	for ring in range(8):
		var alpha: float = 0.05 - float(ring) * 0.004
		draw_circle(center, radius - float(ring) * 70.0, Color(0.08, 0.34, 0.24, max(alpha, 0.01)))

	for x in range(0, int(size.x) + 28, 28):
		for y in range(0, int(size.y) + 28, 28):
			var offset: int = 14 if int(y / 28) % 2 == 0 else 0
			draw_circle(Vector2(x + offset, y), 1.2, Color(1, 1, 1, 0.045))

	var rail_rect: Rect2 = Rect2(Vector2(18, 18), size - Vector2(36, 36))
	draw_rect(rail_rect, Color(0.88, 0.68, 0.32, 0.18), false, 3.0)
