class_name Terminal
extends Control

enum RIGHTCLICK_MENU_ITEMS {
	ITEM_COPY,
	ITEM_PASTE,
}

const GODOT_DEFAULT_FONT_SIZE: int = 16

@export var font_file: FontFile = preload("res://fonts/monospaced/DejaVu_Sans/DejaVuSansMono.ttf")
@export var font_size: int = 22
@export var default_text_color: Color = Color.WHITE
@export var prompt_color: Color = Color.GREEN
@export var primary_prompt_text: String = "[wd]> "
# The prompt for when using Shift + Enter (multi-line input).
@export var continuation_prompt_text: String = "> "
@export var selection_color: Color = Color(0.2, 0.4, 0.6, 0.5)
@export var caret_blink_interval: float = 0.5

var environment: TerminalEnvironment

var caret: TerminalCaret
var caret_logical_index_x: int = 0

var max_columns: int = 20

var _commands: TerminalCommands
var _input_handler: TerminalInput

var _font: Font
var _font_width: float = 0.0
var _font_height: float = 0.0

var _primary_prompt_length: int = 0
var _continuation_prompt_length: int = 0

var _logical_lines: Array[TerminalLogicalLine] = []
var _display_lines: Array[TerminalDisplayLine] = []
var _active_logical_line_idx: int = 0
var _input_first_logical_line_idx: int = 0
var _first_active_display_line_idx: int = 0

var _is_input_locked: bool = false

var _is_selecting: bool = false
var _selection_anchor_index: Vector2i = Vector2i.ZERO
var _selection_cursor_index: Vector2i = Vector2i.ZERO
var _selection_from_index: Vector2i = Vector2i.ZERO
var _selection_to_index: Vector2i = Vector2i.ZERO

var _paste_queue: Array[String] = []
var _is_pasting_multiline: bool = false

var _command_history: Array[String] = []
var _history_index: int = -1
var _history_temp_input: String = ""

@onready var _scroll_container: ScrollContainer = find_child("ScrollContainer")
@onready var _display_control: PanelContainer = find_child("Display")
@onready var _rightclick_menu: PopupMenu = find_child("PopupMenu")


func _ready() -> void:
	_rightclick_menu.add_item("Copy", RIGHTCLICK_MENU_ITEMS.ITEM_COPY)
	_rightclick_menu.add_item("Paste", RIGHTCLICK_MENU_ITEMS.ITEM_PASTE)
	_rightclick_menu.id_pressed.connect(_on_popup_item_pressed)

	environment = TerminalEnvironment.new()

	caret = TerminalCaret.new()
	caret.name = "Caret"
	caret.initialize(self)
	_display_control.add_child(caret)

	_commands = TerminalCommands.new()
	_commands.initialize(self)
	_commands.command_started.connect(_on_command_started)
	_commands.command_finished.connect(_on_command_finished)

	_input_handler = TerminalInput.new()
	_input_handler.initialize(self)

	_setup_terminal(false)
	_create_new_line_with_prompt()

	_display_control.focus_mode = Control.FOCUS_ALL
	_display_control.focus_neighbor_left = NodePath("")
	_display_control.focus_neighbor_right = NodePath("")
	_display_control.focus_neighbor_top = NodePath("")
	_display_control.focus_neighbor_bottom = NodePath("")
	_display_control.grab_focus()


func is_alive() -> bool:
	return is_inside_tree() and not is_queued_for_deletion()


func get_active_logical_line() -> TerminalLogicalLine:
	return _logical_lines[_active_logical_line_idx]


func get_prompt_length() -> int:
	if _active_logical_line_idx == _input_first_logical_line_idx:
		return _primary_prompt_length
	else:
		return _continuation_prompt_length


func recreate_display_lines_since_last_input_only() -> void:
	_recreate_display_lines(_active_logical_line_idx)


func update_caret_position() -> void:
	if _first_active_display_line_idx < 0:
		push_error("Terminal: No active display line. This shouldn't happen.")
		return

	var caret_display_index_x: int = caret_logical_index_x % max_columns
	@warning_ignore("integer_division")
	var caret_relative_display_row: int = floori(caret_logical_index_x / max_columns)
	var caret_display_index_y: int = _first_active_display_line_idx + caret_relative_display_row
	var caret_pos_x: float = caret_display_index_x * _font_width
	var caret_pos_y: float = caret_display_index_y * _font_height
	caret.position = Vector2(caret_pos_x, caret_pos_y)

	# Pass the selected character to the caret for it to draw it with inverted colors.
	var active_logical_line_chars: Array[Dictionary] = get_active_logical_line().chars
	if caret_logical_index_x < active_logical_line_chars.size():
		caret.char_under_caret = active_logical_line_chars[caret_logical_index_x]
	else:
		caret.char_under_caret = { "char": "", "color": default_text_color }
	caret.queue_redraw()


func input_newline() -> void:
	_create_new_line_with_prompt(false)


func run_command() -> void:
	var command: String = _build_input_text().strip_edges()
	_save_to_history(command)
	_commands.process_command(command)


func clear_screen() -> void:
	_clear_all_lines()
	_create_new_logical_line()


func print_on_terminal(text: String, color: Color = default_text_color) -> void:
	_create_new_logical_line()
	_insert_text_at_caret(text, color)


func insert_char_at_caret(
	character: String,
	color: Color = default_text_color,
	should_update: bool = true
) -> void:
	get_active_logical_line().insert_char(caret_logical_index_x, character, color)
	caret_logical_index_x += 1
	if should_update:
		recreate_display_lines_since_last_input_only()


func navigate_history_up() -> void:
	if _command_history.size() > 0:
		clear_selection()

		# If the user is not already browsing history, store the current input for later.
		if _history_index == -1:
			_history_temp_input = _build_input_text()

		_history_index = clamp(_history_index + 1, 0, _command_history.size() - 1)

		var retrieved_command: String = _command_history[
			_command_history.size() - 1 - _history_index
		]

		_clear_input()
		_insert_text_at_caret(retrieved_command)
		caret_logical_index_x = get_active_logical_line().length()


func navigate_history_down() -> void:
	if _command_history.size() > 0:
		clear_selection()

		_history_index = clamp(_history_index - 1, -1, _command_history.size() - 1)

		var retrieved_command: String = ""
		if _history_index == -1:
			retrieved_command = _history_temp_input
		else:
			retrieved_command = _command_history[_command_history.size() - 1 - _history_index]

		_clear_input()
		_insert_text_at_caret(retrieved_command)
		caret_logical_index_x = get_active_logical_line().length()


func invoke_autocompletion() -> void:
	var line: TerminalLogicalLine = get_active_logical_line()
	var prompt_len: int = get_prompt_length()
	var original_input_text: String = line.get_text(prompt_len)
	var original_caret_pos_x: int = caret_logical_index_x

	if caret_logical_index_x <= prompt_len:
		return

	# Extract text from end of prompt to caret (ignore right side).
	var left_text: String = original_input_text.substr(0, caret_logical_index_x - prompt_len)
	left_text = left_text.strip_edges(true, false)

	# Find the start of the current word.
	var is_preceded_by_other_words: bool = false
	var word_start_idx: int = 0
	for i in range(left_text.length() - 1, -1, -1):
		var ch: String = left_text[i]
		if ch == " " or ch == "\t":
			word_start_idx = i + 1
			is_preceded_by_other_words = true
			break

	var current_word: String = left_text.substr(word_start_idx)

	# Only autocomplete the first word (the command name); more advanced autocompletion can be added
	# by calling custom command-specific methods from the 'TerminalCommands' class.
	if is_preceded_by_other_words:
		return

	var commands: Array = _commands.get_available_commands()
	var matches: Array = []

	for command: String in commands:
		if command.begins_with(current_word):
			matches.append(command)

	if matches.is_empty():
		# No matches: can't autocomplete.
		pass
	elif matches.size() == 1:
		# Single match: autocomplete inline.
		_autocomplete(current_word, matches[0])
	else:
		# Multiple matches: print a list.
		print_on_terminal(", ".join(matches), default_text_color)
		_create_new_line_with_prompt()
		_insert_text_at_caret(original_input_text)
		caret_logical_index_x = original_caret_pos_x
		update_caret_position()


func clear_selection() -> void:
	_is_selecting = false
	_selection_anchor_index = Vector2i.ZERO
	_selection_cursor_index = Vector2i.ZERO
	_selection_from_index = Vector2i.ZERO
	_selection_to_index = Vector2i.ZERO
	_display_control.queue_redraw()


func copy_text() -> void:
	var selected_text: String = _get_selected_text()
	if not selected_text.is_empty():
		DisplayServer.clipboard_set(selected_text)


func paste_text() -> void:
	if _is_input_locked:
		return

	var clipboard_text: String = DisplayServer.clipboard_get()
	if clipboard_text == "":
		return

	var lines: PackedStringArray = clipboard_text \
		.replace("\r\n", "\n") \
		.replace("\r", "\n") \
		.split("\n")

	# Populate '_paste_queue' while removing empty lines.
	_paste_queue.clear()
	for line: String in lines:
		var trimmed: String = line.strip_edges()
		if trimmed != "":
			_paste_queue.append(line)

	if _paste_queue.is_empty():
		# Nothing to paste.
		pass
	elif _paste_queue.size() == 1:
		# Single-line paste: insert at the caret.
		_insert_text_at_caret(_paste_queue[0])
	else:
		# Multi-line paste.
		# The approach below is to treat each line as a command and execute them sequentially.
		# One of the other approaches could be to insert all the lines in the current input and
		# don't execute anything until the user presses Enter. Etc.
		clear_selection()
		# Clear the current input, keeping the current prompt as it is. This is especially important
		# if the prompt contains dynamic information like the current time.
		_clear_input()

		_is_pasting_multiline = true
		_lock_input()
		_run_next_pasted_command(true)


func display_has_focus() -> bool:
	return _display_control.has_focus()


func get_font() -> Font:
	return _font


func get_font_size() -> int:
	return font_size


func _setup_environment() -> void:
	# Just as an example.
	environment.set_var("PATH", "/usr/bin:/bin")
	environment.set_var("HOME", "/home/user")


func _setup_terminal(should_recreate_display_lines: bool = true) -> void:
	_setup_environment()

	if font_file == null:
		push_error("Font file is not assigned.")
		return
	_font = font_file
	_font_width = _font.get_char_size(ord('A'), font_size).x
	_font_height = _font.get_height() * font_size / GODOT_DEFAULT_FONT_SIZE

	if caret != null:
		caret.font_width = _font_width
		caret.font_height = _font_height
		caret.color = default_text_color
		caret.blink_interval = caret_blink_interval

	if should_recreate_display_lines:
		_recreate_display_lines()


func _build_input_text() -> String:
	# Here we cannot use 'get_prompt_length()' because we're iterating over multiple logical lines,
	# not just the active one.
	var text: String = ""
	for i: int in range(_input_first_logical_line_idx, _logical_lines.size()):
		# Store newlines (input with Shift + Enter).
		if i > _input_first_logical_line_idx:
			text += "\n"

		var from_index: int = 0
		if i == _input_first_logical_line_idx:
			from_index = _primary_prompt_length
		else:
			from_index = _continuation_prompt_length

		text += _logical_lines[i].get_text(from_index)

	return text


func _create_new_logical_line() -> void:
	var new_logical: TerminalLogicalLine = TerminalLogicalLine.new()
	_logical_lines.append(new_logical)
	_active_logical_line_idx = _logical_lines.size() - 1
	caret_logical_index_x = 0


func _create_new_line_with_prompt(is_primary_prompt: bool = true) -> void:
	_create_new_logical_line()
	_write_prompt(is_primary_prompt)
	_history_index = -1
	recreate_display_lines_since_last_input_only()


func _write_prompt(is_primary_prompt: bool) -> void:
	var prompt_text: String
	if is_primary_prompt:
		prompt_text = primary_prompt_text
	else:
		prompt_text = continuation_prompt_text
	for ch: String in prompt_text:
		get_active_logical_line().insert_char(
			caret_logical_index_x,
			ch,
			prompt_color
		)
		caret_logical_index_x += 1
	if is_primary_prompt:
		_primary_prompt_length = caret_logical_index_x
		_input_first_logical_line_idx = _active_logical_line_idx
	else:
		_continuation_prompt_length = caret_logical_index_x


func _insert_text_at_caret(text: String, color: Color = default_text_color) -> void:
	for ch: String in text:
		insert_char_at_caret(ch, color, false)
	recreate_display_lines_since_last_input_only()


func _clear_all_lines() -> void:
	for display_line: TerminalDisplayLine in _display_lines:
		display_line.free()
	_display_lines.clear()
	for logical_line: TerminalLogicalLine in _logical_lines:
		logical_line.free()
	_logical_lines.clear()


func _clear_input() -> void:
	var active_line: TerminalLogicalLine = get_active_logical_line()
	var prompt_length: int = get_prompt_length()
	active_line.chars.resize(prompt_length)
	caret_logical_index_x = prompt_length


func _save_to_history(command: String) -> void:
	if command == "":
		return

	if _command_history.is_empty() or _command_history[_command_history.size() - 1] != command:
		_command_history.append(command)


func _autocomplete(incomplete_input: String, complete_input: String) -> void:
	if not complete_input.begins_with(incomplete_input):
		push_error(
			"Terminal: Autocomplete mismatch: complete_input does not start with incomplete_input."
		)
		return

	var suffix: String = complete_input.substr(incomplete_input.length())

	# Insert only the missing part at the caret, preserving everything else.
	for ch: String in suffix:
		insert_char_at_caret(ch, default_text_color)


func _run_next_pasted_command(first_line: bool = false) -> void:
	if _paste_queue.is_empty():
		_is_pasting_multiline = false
		_unlock_input()
		return

	var command: String = _paste_queue.pop_front()
	if first_line:
		_clear_input()
	else:
		_create_new_line_with_prompt()
	_insert_text_at_caret(command)
	run_command()


func _create_display_lines_from_logical_line(logical_line: TerminalLogicalLine) -> void:
	var display_line_start: int = 0
	var n_chars_remaining: int = logical_line.length()
	var is_first_processed_display_line: bool = true

	# Create at least one display line to ensure newlines occupy vertical space too.
	# Then wrap any remaining text across multiple display lines.
	while true:
		var display_line_len: int = min(max_columns, n_chars_remaining)
		var display_line: TerminalDisplayLine = TerminalDisplayLine.new()
		display_line.setup_from_logical_line(logical_line, display_line_start, display_line_len)
		_display_lines.append(display_line)

		# Store the index of the first active display line:
		if is_first_processed_display_line:
			if logical_line == get_active_logical_line():
				_first_active_display_line_idx = _display_lines.size() - 1
			is_first_processed_display_line = false

		display_line_start += display_line_len
		n_chars_remaining -= display_line_len

		if n_chars_remaining <= 0:
			break


func _recreate_display_lines(from_which_logical_line: int = 0) -> void:
	if _display_lines.size() > 0:
		if from_which_logical_line > 0:
			# Clean display lines (only the required ones), going backwards.
			for dl_idx in range(_display_lines.size() - 1, -1, -1):
				if _display_lines[dl_idx].logical_line \
						!= _logical_lines[from_which_logical_line]:
					break
				_display_lines[dl_idx].free()
				_display_lines.pop_back()
		else:
			# Clean all the display lines.
			for dl: TerminalDisplayLine in _display_lines:
				dl.free()
			_display_lines.clear()

	# Recreate the display lines (only the required ones).
	for ll_idx in range(from_which_logical_line, _logical_lines.size()):
		_create_display_lines_from_logical_line(_logical_lines[ll_idx])

	_update_display_height()
	_display_control.queue_redraw()
	_scroll()
	update_caret_position()


func _update_display_height() -> void:
	var required_height: float = _display_lines.size() * _font_height
	var scroll_container_height: float = _scroll_container.get_rect().size.y
	if required_height < scroll_container_height:
		required_height = scroll_container_height
	_display_control.set_custom_minimum_size(Vector2(0, required_height))


func _get_display_index_from_mouse_position(pos: Vector2) -> Vector2i:
	# Map mouse position to display line index.
	var display_line_y: int = floori(pos.y / _font_height)
	display_line_y = clamp(display_line_y, 0, _display_lines.size() - 1)

	# Map mouse position to character index within the display line.
	var display_line: TerminalDisplayLine = _display_lines[display_line_y]
	var char_x: int = floori(pos.x / _font_width)
	char_x = clamp(char_x, 0, display_line.display_length)

	return Vector2i(char_x, display_line_y)


func _get_selected_text() -> String:
	if _selection_from_index == _selection_to_index:
		return ""

	var text_buffer: String = ""
	var prev_logical_line: TerminalLogicalLine = null

	for d_idx in range(_selection_from_index.y, _selection_to_index.y + 1):
		var display_line: TerminalDisplayLine = _display_lines[d_idx]
		var logical_line: TerminalLogicalLine = display_line.logical_line

		var start_char: int = 0
		var end_char: int = display_line.display_length

		if d_idx == _selection_from_index.y:
			start_char = _selection_from_index.x
		if d_idx == _selection_to_index.y:
			end_char = _selection_to_index.x

		# Insert EOL character only when logical lines end.
		if prev_logical_line != null and logical_line != prev_logical_line:
			text_buffer += "\n"

		# Copy the required "slice" by reading directly from the logical line using offsets.
		text_buffer += logical_line.get_text(
			display_line.logical_start_index + start_char,
			display_line.logical_start_index + end_char
		)

		prev_logical_line = logical_line

	return text_buffer


func _lock_input() -> void:
	_is_input_locked = true
	caret.is_blinking_allowed = false


func _unlock_input() -> void:
	_is_input_locked = false
	caret.is_blinking_allowed = true
	# Restore the caret by calling 'terminal_focus_changed', in case in the meanwhile the terminal
	# lost focus.
	caret.terminal_focus_changed()


func _rightclick_menu_popup(rect: Rect2i) -> void:
	# Setup items.
	var has_selection: bool = _get_selected_text() != ""
	_rightclick_menu.set_item_disabled(RIGHTCLICK_MENU_ITEMS.ITEM_COPY, !has_selection)
	var clipboard_text: String = DisplayServer.clipboard_get()
	_rightclick_menu.set_item_disabled(RIGHTCLICK_MENU_ITEMS.ITEM_PASTE, clipboard_text == "")

	_rightclick_menu.popup(rect)


func _scroll() -> void:
	# ScrollContainer updates its scrollbar max_value after the layout pass, so 'call_deferred()'
	# and 'await get_tree().process_frame' both fire too early.
	# The timer is the only workaround for this known Godot issue.
	await get_tree().create_timer(0.005).timeout
	var v_scroll_max: int = int(_scroll_container.get_v_scroll_bar().max_value)
	_scroll_container.set_v_scroll(v_scroll_max)


func _on_command_started() -> void:
	_lock_input()


func _on_command_finished() -> void:
	if _is_pasting_multiline:
		if _paste_queue.is_empty():
			_is_pasting_multiline = false
			_create_new_line_with_prompt()
			_unlock_input()
		else:
			_run_next_pasted_command()
	else:
		_create_new_line_with_prompt()
		_unlock_input()


func _on_scroll_container_resized() -> void:
	clear_selection()
	max_columns = int(floor(get_rect().size.x / _font_width))
	_recreate_display_lines()
	_scroll()


func _on_display_draw() -> void:
	assert(not _display_lines.is_empty(), "Terminal: '_display_lines' unexpectedly empty.")

	var d_line_idx: int = 0
	for display_line: TerminalDisplayLine in _display_lines:
		var start_idx: int = display_line.logical_start_index

		# Selection.
		var is_line_selected: bool = false
		var selection_start_char: int = 0
		var selection_end_char: int = 0
		if _selection_from_index.y <= d_line_idx and d_line_idx <= _selection_to_index.y:
			is_line_selected = true
			selection_start_char = 0
			selection_end_char = display_line.display_length
			if d_line_idx == _selection_from_index.y:
				selection_start_char = _selection_from_index.x
			if d_line_idx == _selection_to_index.y:
				selection_end_char = _selection_to_index.x
		if is_line_selected:
			var pos_x: float = selection_start_char * _font_width
			var pos_y: float = d_line_idx * _font_height
			var width: float = (selection_end_char - selection_start_char) * _font_width
			var height: float = _font_height
			_display_control.draw_rect(Rect2(pos_x, pos_y, width, height), selection_color)

		# Draw characters.
		for c_idx in range(display_line.display_length):
			var c: Dictionary = display_line.logical_line.chars[start_idx + c_idx]
			var pos: Vector2 = Vector2(
				c_idx * _font_width,
				(d_line_idx * _font_height) + _font.get_ascent(font_size)
			)

			_display_control.draw_char(_font, pos, c["char"], font_size, c["color"])

		d_line_idx += 1


func _update_selection_bounds() -> void:
	if (_selection_anchor_index.y < _selection_cursor_index.y
			or (_selection_anchor_index.y == _selection_cursor_index.y
			and _selection_anchor_index.x < _selection_cursor_index.x)):
		_selection_from_index = _selection_anchor_index
		_selection_to_index = _selection_cursor_index
	else:
		_selection_from_index = _selection_cursor_index
		_selection_to_index = _selection_anchor_index


func _on_display_gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.is_pressed() and not _is_input_locked:
		accept_event()
		_input_handler.handle_key_event(event)
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.is_pressed():
			_rightclick_menu_popup(Rect2i(event.global_position.x, event.global_position.y, 1, 1))
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.is_pressed():
				clear_selection()
				_is_selecting = true
				_selection_anchor_index = _get_display_index_from_mouse_position(event.position)
				_selection_cursor_index = _selection_anchor_index
			elif event.is_released() and _is_selecting:
				_is_selecting = false
				_update_selection_bounds()
				_display_control.queue_redraw()

	if event is InputEventMouseMotion:
		if _is_selecting:
			_selection_cursor_index = _get_display_index_from_mouse_position(event.position)
			_update_selection_bounds()
			_display_control.queue_redraw()


func _on_display_focus_entered() -> void:
	caret.terminal_focus_changed()


func _on_display_focus_exited() -> void:
	caret.terminal_focus_changed()


func _on_popup_item_pressed(id: int) -> void:
	match id:
		RIGHTCLICK_MENU_ITEMS.ITEM_COPY:
			copy_text()
		RIGHTCLICK_MENU_ITEMS.ITEM_PASTE:
			paste_text()
		_:
			push_error("Terminal: Popup menu: Unknown menu item: ", id)


func _on_tree_exiting() -> void:
	_clear_all_lines()
	if environment != null:
		environment.free()
