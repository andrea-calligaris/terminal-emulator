class_name TerminalCaret
extends Node2D

var font_width: float = 0.0
var font_height: float = 0.0
var color: Color = Color.WHITE
var char_under_caret: Dictionary = { "char": "", "color": null }
var is_blinking_allowed: bool = true
var blink_interval: float = 0.5
var _blink_timer: float = 0.0
var _terminal: Terminal


func _process(delta: float) -> void:
	if not _terminal.display_has_focus() or not is_blinking_allowed:
		return

	_blink_timer += delta
	if _blink_timer >= blink_interval:
		visible = !visible
		_blink_timer = 0.0
		queue_redraw()


func _draw() -> void:
	if _terminal.display_has_focus():
		if visible or is_blinking_allowed == false:
			draw_rect(Rect2(Vector2.ZERO, Vector2(font_width, font_height)), color)
			# Draw the selected character on top, with inverted colors.
			if char_under_caret["char"] != "":
				var terminal_font: Font = _terminal.get_font()
				var terminal_font_size: int = _terminal.get_font_size()
				var pos: Vector2 = Vector2(0, terminal_font.get_ascent(terminal_font_size))
				var original_color: Color = char_under_caret["color"]
				var inverted_color: Color = Color(
					1.0 - original_color.r,
					1.0 - original_color.g,
					1.0 - original_color.b)
				draw_char(
					terminal_font,
					pos,
					char_under_caret["char"],
					terminal_font_size,
					inverted_color
				)
	else:
		# Solid outline, and non-blinking.
		draw_rect(
			Rect2(Vector2.ZERO, Vector2(font_width, font_height)),
			color,
			false,
			1.0
		)


func initialize(terminal: Terminal) -> void:
	_terminal = terminal


func reset_timer() -> void:
	visible = true
	_blink_timer = 0.0


func terminal_focus_changed() -> void:
	reset_timer()
	queue_redraw()
