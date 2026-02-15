class_name TerminalCommands
extends RefCounted

signal command_started
signal command_finished


class TerminalCommand:
	var name: String
	var description: String
	var long_help: PackedStringArray = []
	var callable: Callable
	var schema: TerminalCommandSchema = null


var _terminal: Terminal
var _command_registry: Dictionary = {}
var _environment: TerminalEnvironment
var _argv: PackedStringArray = []
var _parsed_args: TerminalArguments.ParsedArgs = null


func initialize(terminal: Terminal) -> void:
	_terminal = terminal
	_environment = _terminal.environment
	_register_commands()


func get_available_commands() -> Array:
	return Array(_command_registry.keys())


func process_command(full_command: String) -> void:
	full_command = full_command.strip_edges()
	if full_command.is_empty():
		command_finished.emit()
		return

	var parts: PackedStringArray = _split_arguments_considering_quotes(full_command)
	var command_name: String = parts[0]

	_argv.clear()
	if parts.size() > 1:
		_argv = parts.slice(1)

	if not _command_registry.has(command_name):
		_terminal.print_on_terminal("Unknown command: %s" % command_name, Color.RED)
		command_finished.emit()
		return

	var cmd_obj: TerminalCommand = _command_registry[command_name]

	if _argv.has("--help") or _argv.has("-h"):
		for help_line: String in cmd_obj.long_help:
			_terminal.print_on_terminal(help_line)
		command_finished.emit()
		return

	if cmd_obj.schema:
		_parsed_args = TerminalArguments.parse(_argv, cmd_obj.schema)
		if not _parsed_args.errors.is_empty():
			for err: String in _parsed_args.errors:
				_terminal.print_on_terminal(err, Color.RED)
			command_finished.emit()
			return
	else:
		_parsed_args = TerminalArguments.parse(_argv)

	cmd_obj.callable.call()


func _register_commands() -> void:
	var cmd_obj: TerminalCommand

	cmd_obj = TerminalCommand.new()
	cmd_obj.name = "clear"
	cmd_obj.description = "Clear the screen."
	cmd_obj.callable = _cmd_clear
	_register_command(cmd_obj)

	cmd_obj = TerminalCommand.new()
	cmd_obj.name = "echo"
	cmd_obj.description = "Print text on the screen."
	cmd_obj.callable = _cmd_echo
	_register_command(cmd_obj)

	cmd_obj = TerminalCommand.new()
	cmd_obj.name = "env"
	cmd_obj.description = "Show environment variables."
	cmd_obj.callable = _cmd_env
	_register_command(cmd_obj)

	cmd_obj = TerminalCommand.new()
	cmd_obj.name = "exit"
	cmd_obj.description = "Close the terminal."
	cmd_obj.callable = _cmd_exit
	_register_command(cmd_obj)

	cmd_obj = TerminalCommand.new()
	cmd_obj.name = "hello"
	cmd_obj.description = "Greet the user."
	cmd_obj.callable = _cmd_hello
	cmd_obj.schema = TerminalCommandSchema.new()
	cmd_obj.schema.add_positional("name", "The name of the user.")
	cmd_obj.schema.add_positional("greeting", "The greeting to use.", "Hello")
	cmd_obj.schema.add_option(
		"uppercase",
		"u",
		"Print in uppercase.",
		false,
		TerminalArguments.OptionType.FLAG
	)
	_register_command(cmd_obj)

	cmd_obj = TerminalCommand.new()
	cmd_obj.name = "help"
	cmd_obj.description = "List the available commands."
	cmd_obj.callable = _cmd_help
	_register_command(cmd_obj)

	cmd_obj = TerminalCommand.new()
	cmd_obj.name = "ping"
	cmd_obj.description = "Test the network connection."
	cmd_obj.callable = _cmd_ping
	cmd_obj.schema = TerminalCommandSchema.new()
	cmd_obj.schema.add_option("count", "c", "Number of pings.", 4, TerminalArguments.OptionType.INT)
	cmd_obj.schema.add_positional("host", "The hostname or IP address to ping.", "example.com")
	_register_command(cmd_obj)


func _register_command(cmd_obj: TerminalCommand) -> void:
	_build_long_help(cmd_obj)
	_command_registry[cmd_obj.name] = cmd_obj


func _build_long_help(cmd_obj: TerminalCommand) -> void:
	var help_lines: PackedStringArray = []
	var usage_line: String = "Usage: " + cmd_obj.name

	if cmd_obj.schema == null:
		help_lines.append(usage_line)
		help_lines.append("")
		help_lines.append(cmd_obj.description)
		cmd_obj.long_help = help_lines
		return

	if cmd_obj.schema.has_options():
		usage_line += " [options]"
	for pos: TerminalCommandSchema.Positional in cmd_obj.schema.positional_definitions:
		usage_line += " <%s>" % pos.name
	help_lines.append(usage_line)

	help_lines.append("")

	if not cmd_obj.schema.positional_definitions.is_empty():
		help_lines.append("Arguments:")
		for pos: TerminalCommandSchema.Positional in cmd_obj.schema.positional_definitions:
			var req_str: String = "" if pos.required else " (Default: %s)" % str(pos.default_value)
			help_lines.append("  %-18s %s%s" % [pos.name, pos.description, req_str])
		help_lines.append("")

	if cmd_obj.schema.has_options():
		help_lines.append("Options:")

		var processed_opts: Array = []
		for opt: TerminalCommandSchema.Option in cmd_obj.schema.allowed_options.values():
			if opt in processed_opts: continue
			processed_opts.append(opt)

			var long_opt: String = "--%s" % opt.name if opt.name != "" else ""
			var short_opt: String = "-%s" % opt.short_name if opt.short_name != "" else ""
			var comma: String = ", " if (long_opt != "" and short_opt != "") else ""
			var option_names: String = "%s%s%s" % [long_opt, comma, short_opt]

			var default_val_help: String = ""
			if opt.type != TerminalArguments.OptionType.FLAG:
				default_val_help = "(Default: %s)" % str(opt.default_value)

			var line: String = "  %-18s %s %s" % [option_names, opt.description, default_val_help]
			help_lines.append(line)

	cmd_obj.long_help = help_lines


static func _split_arguments_considering_quotes(input: String) -> PackedStringArray:
	var result: PackedStringArray = []
	var regex: RegEx = RegEx.new()
	# Matches words or text inside double quotes.
	regex.compile("\"([^\"]*)\"|(\\S+)")

	for m: RegExMatch in regex.search_all(input):
		if m.get_string(1) != "":
			# The text inside quotes.
			result.append(m.get_string(1))
		else:
			# The unquoted word.
			result.append(m.get_string(2))
	return result


func _safe_await(duration: float) -> bool:
	if not _terminal.is_alive():
		return false

	await _terminal.get_tree().create_timer(duration).timeout

	return _terminal.is_alive()


func _cmd_clear() -> void:
	_terminal.clear_screen()
	command_finished.emit()


func _cmd_echo() -> void:
	_terminal.print_on_terminal(_parsed_args.raw)
	command_finished.emit()


func _cmd_env() -> void:
	if _environment.variables.is_empty():
		_terminal.print_on_terminal("No environment variables.", Color.YELLOW)
	else:
		for key: String in _environment.variables.keys():
			var value: String = str(_environment.variables[key])
			_terminal.print_on_terminal("%s=%s" % [key, value])
	command_finished.emit()


func _cmd_exit() -> void:
	command_started.emit()
	_terminal.get_tree().quit()
	# Don't emit 'command_finished' to prevent a new line and prompt appearing before the
	# terminal actually quits.


func _cmd_help() -> void:
	_terminal.print_on_terminal("Available commands:")

	var command_names: Array = get_available_commands()
	command_names.sort()

	for command_name: String in command_names:
		var cmd_obj: TerminalCommand = _command_registry[command_name]
		# Use %-12s to pad the name to 12 characters so descriptions align.
		var line: String = "  %-12s %s" % [command_name, cmd_obj.description]
		_terminal.print_on_terminal(line)

	_terminal.print_on_terminal("Use [command] --help for more information.")
	command_finished.emit()


# Just to demonstrate options and positionals.
func _cmd_hello() -> void:
	var name_to_greet: String = _parsed_args.positionals[0]
	var greeting: String = _parsed_args.positionals[1]
	var output: String = "%s, %s!" % [greeting, name_to_greet]
	if _parsed_args.has_flag("uppercase"):
		output = output.to_upper()
	_terminal.print_on_terminal(output)
	command_finished.emit()


# This command serves as an example of a command that takes a certain time to complete.
func _cmd_ping() -> void:
	command_started.emit()

	var host: String = _parsed_args.positionals[0]
	var count: int = _parsed_args.get_option("count")

	_terminal.print_on_terminal("PING %s (???.???.???.???)." % [host])
	for seq in range(1, count + 1):
		if not await _safe_await(1.0): return
		_terminal.print_on_terminal(
			"64 bytes from %s: icmp_seq=%d time=%d ms" % [host, seq, 20 + randi() % 10])
	if not await _safe_await(1.0): return
	_terminal.print_on_terminal("--- %s ping statistics ---" % host)
	_terminal.print_on_terminal(
		"%d packets transmitted, %d received, 0%% packet loss"
		% [count, count]
	)
	command_finished.emit()
