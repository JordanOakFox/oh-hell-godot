extends Button
class_name CardButton

const SUIT_COLORS := {
	"S": Color("#171717"),
	"H": Color("#c8322b"),
	"D": Color("#d6a51f"),
	"C": Color("#2367c7"),
}
const SUIT_SYMBOLS := {"S": "♠", "H": "♥", "D": "♦", "C": "♣"}
const RANK_NAMES := {11: "J", 12: "Q", 13: "K", 14: "A"}

var card: Dictionary = {}
var face_down := false

func setup(new_card: Dictionary, is_face_down := false) -> void:
	card = new_card.duplicate(true)
	face_down = is_face_down
	text = ""
	flat = true
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(74, 106)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	queue_redraw()

func _draw() -> void:
	var card_rect := Rect2(Vector2(1, 1), size - Vector2(2, 2))
	draw_rect(card_rect.grow(2), Color(0, 0, 0, 0.22))

	if face_down:
		draw_rect(card_rect, Color("#f9f4e8"))
		draw_rect(card_rect.grow(-7), Color("#d9b44a"), false, 2.0)
		for x in range(16, int(size.x) - 10, 14):
			for y in range(18, int(size.y) - 10, 14):
				draw_circle(Vector2(x, y), 2.2, Color("#2367c7", 0.18))
		return

	var ink: Color = SUIT_COLORS.get(str(card["suit"]), Color("#181818"))
	var fill: Color = Color("#f9f4e8") if not disabled else Color("#bdb6aa")
	draw_rect(card_rect, fill)
	draw_rect(card_rect, Color("#252019"), false, 2.0)
	draw_rect(card_rect.grow(-5), Color("#d9b44a"), false, 1.0)

	var font: Font = get_theme_default_font()
	var rank: String = RANK_NAMES.get(int(card["rank"]), str(card["rank"]))
	var suit: String = SUIT_SYMBOLS.get(str(card["suit"]), str(card["suit"]))

	draw_string(font, Vector2(9, 24), rank, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, ink)
	draw_string(font, Vector2(10, 46), suit, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, ink)
	draw_string(font, Vector2(size.x * 0.5 - 15, size.y * 0.58), suit, HORIZONTAL_ALIGNMENT_CENTER, 30, 36, ink)

	var bottom_text: String = "%s%s" % [rank, suit]
	draw_string(font, Vector2(size.x - 45, size.y - 10), bottom_text, HORIZONTAL_ALIGNMENT_RIGHT, 38, 18, ink)
