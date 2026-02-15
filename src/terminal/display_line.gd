class_name TerminalDisplayLine
extends Object

var logical_line: TerminalLogicalLine
var logical_start_index: int = 0
var display_length: int = 0


func setup_from_logical_line(
	logical_line_ref: TerminalLogicalLine,
	logical_start_idx: int,
	max_columns: int
) -> void:
	logical_line = logical_line_ref
	logical_start_index = logical_start_idx
	display_length = min(max_columns, logical_line.length() - logical_start_index)
