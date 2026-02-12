## Lightweight file logger for game network diagnostics.
extends Node

const LOG_DIR_RES: String = "res://logs"

var _log_file: FileAccess
var _log_path: String = ""

func _ready() -> void:
	_open_log_file()

func _exit_tree() -> void:
	flush()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		flush()

func log_line(source: String, message: String) -> void:
	if message.is_empty():
		return
	if _log_file == null:
		return
	var ts: String = Time.get_datetime_string_from_system(true, true)
	_log_file.store_line("[%s] [%s] %s" % [ts, source, message])

func flush() -> void:
	if _log_file != null:
		_log_file.flush()

func get_log_path() -> String:
	return _log_path

func _open_log_file() -> void:
	var abs_dir: String = ProjectSettings.globalize_path(LOG_DIR_RES)
	var dir_err: int = DirAccess.make_dir_recursive_absolute(abs_dir)
	if dir_err != OK and dir_err != ERR_ALREADY_EXISTS:
		return

	var now: Dictionary = Time.get_datetime_dict_from_system()
	var filename: String = "session_%04d%02d%02d_%02d%02d%02d.log" % [
		int(now.get("year", 0)),
		int(now.get("month", 0)),
		int(now.get("day", 0)),
		int(now.get("hour", 0)),
		int(now.get("minute", 0)),
		int(now.get("second", 0)),
	]
	_log_path = "%s/%s" % [abs_dir, filename]
	_log_file = FileAccess.open(_log_path, FileAccess.WRITE)
	if _log_file != null:
		log_line("logger", "session started")
