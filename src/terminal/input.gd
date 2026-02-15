class_name TerminalInput
extends Object

var _terminal: Terminal


func initialize(terminal: Terminal) -> void:
	_terminal = terminal


func handle_key_event(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		# Input is happening, thus the caret must be visible.
		_terminal.caret.reset_timer()

		if (event.is_ctrl_pressed() or event.is_shift_pressed() or event.is_alt_pressed()
				or event.is_meta_pressed()):
			match event.keycode:
				Key.KEY_ENTER, Key.KEY_KP_ENTER:
					if event.is_shift_pressed():
						# Handle "Shift + Enter": insert a newline without submitting.
						_terminal.input_newline()
						return
				Key.KEY_LEFT:
					if event.is_ctrl_pressed() or event.is_alt_pressed():
						_move_caret_word_left()
						return
				Key.KEY_RIGHT:
					if event.is_ctrl_pressed() or event.is_alt_pressed():
						_move_caret_word_right()
						return
				Key.KEY_C:
					if event.is_ctrl_pressed() and event.is_shift_pressed():
						_terminal.copy_text()
						return
				Key.KEY_INSERT:
					if event.is_shift_pressed():
						_terminal.copy_text()
						return
				Key.KEY_V:
					if event.is_ctrl_pressed() and event.is_shift_pressed():
						_terminal.paste_text()
						return

		# No shortcuts.
		match event.keycode:
			Key.KEY_ENTER, Key.KEY_KP_ENTER:
				_terminal.run_command()
			Key.KEY_LEFT:
				_key_left()
			Key.KEY_RIGHT:
				_key_right()
			Key.KEY_BACKSPACE:
				_key_backspace()
			Key.KEY_DELETE:
				_key_delete()
			Key.KEY_HOME:
				_jump_to_start()
			Key.KEY_END:
				_jump_to_end()
			Key.KEY_UP:
				_terminal.navigate_history_up()
			Key.KEY_DOWN:
				_terminal.navigate_history_down()
			Key.KEY_TAB:
				_terminal.invoke_autocompletion()
			_:
				_insert_printable_character(event)


func _insert_printable_character(event: InputEvent) -> void:
	if event.unicode != 0:
		_terminal.clear_selection()
		_terminal.insert_char_at_caret(char(event.unicode))


func _key_backspace() -> void:
	if _terminal.caret_logical_index_x > _terminal.get_prompt_length():
		_terminal.clear_selection()
		_terminal.get_active_logical_line().delete_char(_terminal.caret_logical_index_x - 1)
		_terminal.caret_logical_index_x -= 1
		_terminal.recreate_display_lines_since_last_input_only()


func _key_delete() -> void:
	if _terminal.caret_logical_index_x < _terminal.get_active_logical_line().length():
		_terminal.clear_selection()
		_terminal.get_active_logical_line().delete_char(_terminal.caret_logical_index_x)
		_terminal.recreate_display_lines_since_last_input_only()


func _key_left() -> void:
	if _terminal.caret_logical_index_x > _terminal.get_prompt_length():
		_terminal.caret_logical_index_x -= 1
		_terminal.update_caret_position()


func _key_right() -> void:
	if _terminal.caret_logical_index_x < _terminal.get_active_logical_line().length():
		_terminal.caret_logical_index_x += 1
		_terminal.update_caret_position()


func _jump_to_start() -> void:
	_terminal.caret_logical_index_x = _terminal.get_prompt_length()
	_terminal.update_caret_position()


func _jump_to_end() -> void:
	_terminal.caret_logical_index_x = _terminal.get_active_logical_line().length()
	_terminal.update_caret_position()


# This uses 'is_valid_unicode_identifier()' as a Unicode-aware approximation of "word characters",
# saving us from implementing full Unicode word rules.
func _is_char_a_word_boundary(ch: String) -> bool:
	assert(ch.length() == 1, "Expected single-character string")

	var is_word_char: bool = false

	# Letters (it's required to manually exclude the underscore).
	if ch.is_valid_unicode_identifier() and ch != "_":
		is_word_char = true
	# Digits.
	elif ch >= "0" and ch <= "9":
		is_word_char = true

	return not is_word_char


func _move_caret_word_left() -> void:
	var line: TerminalLogicalLine = _terminal.get_active_logical_line()
	var idx: int = _terminal.caret_logical_index_x
	var prompt_len: int = _terminal.get_prompt_length()

	if idx <= prompt_len:
		_terminal.caret_logical_index_x = prompt_len
		_terminal.update_caret_position()
		return

	# If the cursor is sitting on any word boundary characters, skip them.
	while idx > prompt_len and _is_char_a_word_boundary(line.chars[idx - 1]['char']):
		idx -= 1

	# Skip the word itself.
	while idx > prompt_len and not _is_char_a_word_boundary(line.chars[idx - 1]['char']):
		idx -= 1

	_terminal.caret_logical_index_x = idx
	_terminal.update_caret_position()


func _move_caret_word_right() -> void:
	var line: TerminalLogicalLine = _terminal.get_active_logical_line()
	var idx: int = _terminal.caret_logical_index_x
	var length: int = line.length()

	# If already at end, nothing to do.
	if idx >= length:
		_terminal.caret_logical_index_x = length
		_terminal.update_caret_position()
		return

	# If the cursor is sitting on any word boundary characters, skip them.
	while idx < length and _is_char_a_word_boundary(line.chars[idx]['char']):
		idx += 1

	# Skip the word itself.
	while idx < length and not _is_char_a_word_boundary(line.chars[idx]['char']):
		idx += 1

	_terminal.caret_logical_index_x = idx
	_terminal.update_caret_position()
