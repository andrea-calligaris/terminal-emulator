class_name TerminalEnvironment
extends Object

# Key-value pairs for environment variables (PATH, HOME, etc.).
var variables: Dictionary = {}


func get_var(name: String) -> String:
	return variables.get(name)


func set_var(name: String, value: String) -> void:
	variables[name] = value


func unset_var(name: String) -> void:
	variables.erase(name)


func has_var(name: String) -> bool:
	return variables.has(name)
