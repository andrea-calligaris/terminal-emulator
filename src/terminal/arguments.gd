class_name TerminalArguments
extends RefCounted

enum OptionType { VALUE, INT, FLAG }

class ParsedArgs:
	var positionals: Array[String] = []
	var flags: Dictionary = {}
	var options: Dictionary = {}
	var raw: String = ""
	var errors: Array[String] = []

	func has_flag(name: String) -> bool:
		return flags.has(name)

	func get_option(name: String) -> Variant:
		assert(
			options.has(name),
			"TerminalArguments: Option '%s' was not defined in the schema." % name
		)
		return options[name]


static func parse(argv: PackedStringArray, schema: TerminalCommandSchema = null) -> ParsedArgs:
	var parsed: ParsedArgs = ParsedArgs.new()
	parsed.raw = " ".join(argv)

	if schema == null:
		parsed.positionals.assign(Array(argv))
		return parsed

	# Initialize option defaults.
	for opt: TerminalCommandSchema.Option in schema.allowed_options.values():
		parsed.options[opt.name] = opt.default_value

	var collected_positionals: Array[String] = []
	var i: int = 0
	var parsing_options: bool = true

	while i < argv.size():
		var token: String = argv[i]

		if parsing_options and token == "--":
			parsing_options = false
			i += 1
			continue

		if not parsing_options or not token.begins_with("-"):
			collected_positionals.append(token)
			i += 1
			continue

		if token.begins_with("--"):
			i += _handle_long_option(token, argv, i, parsed, schema)
		else:
			i += _handle_short_options(token, argv, i, parsed, schema)

		i += 1

	_validate_positionals(collected_positionals, parsed, schema)
	return parsed


static func _handle_long_option(
	token: String,
	argv: PackedStringArray,
	i: int,
	parsed: ParsedArgs,
	schema: TerminalCommandSchema
) -> int:
	var eq_idx: int = token.find("=")
	var key: String
	var inline_value: String = ""

	if eq_idx != -1:
		key = token.substr(2, eq_idx - 2)
		inline_value = token.substr(eq_idx + 1)
	else:
		key = token.substr(2)

	var opt: TerminalCommandSchema.Option = schema.get_option_data(key)
	if opt == null:
		parsed.errors.append("Unknown option: --%s" % key)
		return 0

	if opt.type == OptionType.FLAG:
		parsed.flags[opt.name] = true
		return 0

	return _consume_value(opt, inline_value, argv, i, parsed)


static func _handle_short_options(
	token: String,
	argv: PackedStringArray,
	i: int,
	parsed: ParsedArgs,
	schema: TerminalCommandSchema
) -> int:
	var bundle: String = token.substr(1)

	# Single short option like "-c 4": allowed to consume the next token.
	if bundle.length() == 1:
		var opt: TerminalCommandSchema.Option = schema.get_option_data(bundle)
		if opt == null:
			parsed.errors.append("Unknown option: -%s" % bundle)
			return 0
		if opt.type == OptionType.FLAG:
			parsed.flags[opt.name] = true
			return 0
		return _consume_value(opt, "", argv, i, parsed)

	# Bundled short options like "-abc": only flags are allowed.
	for j in range(bundle.length()):
		var ch: String = bundle[j]
		var opt: TerminalCommandSchema.Option = schema.get_option_data(ch)
		if opt == null:
			parsed.errors.append("Unknown option: -%s" % ch)
			continue
		if opt.type != OptionType.FLAG:
			parsed.errors.append("Option '-%s' requires a value and cannot be bundled." % ch)
			continue
		parsed.flags[opt.name] = true

	return 0


# Try to get a value for the option, either from 'inline_value' (already provided via
# `--option=val`) or by consuming the next token from 'argv' ('-o val'). Return the number of
# extra tokens consumed (0 or 1).
static func _consume_value(
	opt: TerminalCommandSchema.Option,
	inline_value: String,
	argv: PackedStringArray,
	i: int,
	parsed: ParsedArgs
) -> int:
	var value_str: String
	var extra_consumed: int = 0

	if inline_value != "":
		# Value was provided inline: '--option=val'.
		value_str = inline_value
	elif i + 1 < argv.size() and not argv[i + 1].begins_with("-"):
		# Consume the next token as the value: '--option val' or '-o val'.
		value_str = argv[i + 1]
		extra_consumed = 1
	else:
		parsed.errors.append("Option '--%s' requires a value." % opt.name)
		return 0

	if opt.type == OptionType.INT:
		if not value_str.is_valid_int():
			parsed.errors.append(
				"Option '--%s' requires an integer, got: '%s'" % [opt.name, value_str]
			)
			return extra_consumed
		parsed.options[opt.name] = value_str.to_int()
	else:
		parsed.options[opt.name] = value_str

	return extra_consumed


static func _validate_positionals(
	collected: Array[String],
	parsed: ParsedArgs,
	schema: TerminalCommandSchema
) -> void:
	for j in range(schema.positional_definitions.size()):
		var positional_definition: TerminalCommandSchema.Positional \
			= schema.positional_definitions[j]
		if j < collected.size():
			parsed.positionals.append(collected[j])
		elif positional_definition.required:
			parsed.errors.append("Missing required argument: <%s>" % positional_definition.name)
		else:
			parsed.positionals.append(str(positional_definition.default_value))

	for k in range(schema.positional_definitions.size(), collected.size()):
		parsed.errors.append("Unexpected extra argument: '%s'" % collected[k])
