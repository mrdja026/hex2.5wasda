## Manages the network connection to the game backend.
# class_name GameNetworkClient
extends Node

signal snapshot_received(snapshot: Dictionary)
signal update_received(update: Dictionary)
signal error_received(message: String)
signal status_received(message: String)

const DEFAULT_BASE_URL: String = "http://localhost:8002"
const FALLBACK_BASE_URL: String = "http://127.0.0.1:8002"
const ENV_BASE_URL: StringName = &"GAME_BACKEND_URL"

var base_url: String = DEFAULT_BASE_URL
var user_id: int = 0
var auth_cookie: String = ""
var channel_id: int = -1
var username: String = ""

@onready var _http: HTTPRequest = HTTPRequest.new()
@onready var _command_http: HTTPRequest = HTTPRequest.new()
@onready var _poll_http: HTTPRequest = HTTPRequest.new()

var _command_queue: Array = []
var _command_inflight: bool = false
var _poll_inflight: bool = false
var _poll_elapsed: float = 0.0
var _poll_interval: float = 4.0
var _ws: WebSocketPeer
var _channel_id: int = -1
var _is_connecting: bool = false

func _ready() -> void:
	add_child(_http)
	add_child(_command_http)
	add_child(_poll_http)
	base_url = _read_env_string(ENV_BASE_URL, DEFAULT_BASE_URL)
	_http.timeout = 8.0
	_command_http.timeout = 8.0
	_poll_http.timeout = 8.0

func _process(_delta: float) -> void:
	if _ws == null:
		_poll_tick(_delta)
		return
	_ws.poll()
	if _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		_poll_tick(_delta)
		return
	while _ws.get_available_packet_count() > 0:
		var packet: PackedByteArray = _ws.get_packet()
		var text: String = packet.get_string_from_utf8()
		var data: Variant = JSON.parse_string(text)
		if typeof(data) != TYPE_DICTIONARY:
			continue
		_handle_socket_message(data as Dictionary)
	_poll_tick(_delta)

func connect_to_game() -> void:
	if _is_connecting:
		return
	_is_connecting = true
	_call_connect_flow()

func send_command(command: String, target_username: String = "", force: bool = false) -> void:
	if _channel_id <= 0:
		error_received.emit("Game channel not joined")
		return
	_command_queue.append({
		"command": command,
		"target_username": target_username,
		"force": force,
	})
	_call_send_command()

func _call_connect_flow() -> void:
	await _connect_flow()

func _call_send_command() -> void:
	await _process_command_queue()

func _connect_flow() -> void:
	var health_ok: bool = await _probe_backend()
	if not health_ok:
		_is_connecting = false
		error_received.emit("Backend not reachable")
		return
	var response: Dictionary = await _auth_game_with_fallback()
	if not response.get("ok", false):
		_is_connecting = false
		error_received.emit("Failed to authenticate for #game")
		return
	var data: Variant = response.get("data")
	if typeof(data) != TYPE_DICTIONARY:
		_is_connecting = false
		error_received.emit("Invalid auth response")
		return
	var data_dict := data as Dictionary
	var access_token: String = str(data_dict.get("access_token", ""))
	var token_type: String = str(data_dict.get("token_type", "bearer")).to_lower()
	if access_token.is_empty():
		_is_connecting = false
		error_received.emit("Missing access token")
		return
	if token_type == "bearer":
		auth_cookie = "Bearer %s" % access_token
	else:
		auth_cookie = access_token
	user_id = int(data_dict.get("user_id", 0))
	_channel_id = int(data_dict.get("channel_id", -1))
	channel_id = _channel_id
	username = str(data_dict.get("username", ""))
	if not username.is_empty():
		status_received.emit("Auth OK: %s" % username)
	var snapshot: Variant = data_dict.get("snapshot", {})
	if typeof(snapshot) == TYPE_DICTIONARY:
		snapshot_received.emit(snapshot as Dictionary)
	if user_id <= 0 or _channel_id <= 0:
		_is_connecting = false
		error_received.emit("Invalid auth payload")
		return
	await _request_json(HTTPClient.METHOD_POST, "/channels/%s/join" % _channel_id)
	_connect_websocket()
	_is_connecting = false

func _auth_game_with_fallback() -> Dictionary:
	var response: Dictionary = await _request_json(HTTPClient.METHOD_POST, "/auth/auth_game")
	if response.get("ok", false):
		return response
	if _should_try_fallback() and base_url != FALLBACK_BASE_URL:
		status_received.emit("Auth failed, retrying %s" % FALLBACK_BASE_URL)
		base_url = FALLBACK_BASE_URL
		if not await _health_check(base_url):
			return response
		return await _request_json(HTTPClient.METHOD_POST, "/auth/auth_game")
	return response

func _probe_backend() -> bool:
	if await _health_check(base_url):
		status_received.emit("Health OK: %s" % base_url)
		return true
	if _should_try_fallback():
		status_received.emit("Health failed, retrying %s" % FALLBACK_BASE_URL)
		base_url = FALLBACK_BASE_URL
		if await _health_check(base_url):
			status_received.emit("Health OK: %s" % base_url)
			return true
	return false

func _health_check(url_root: String) -> bool:
	var previous_url: String = base_url
	base_url = url_root
	var response: Dictionary = await _request_json(HTTPClient.METHOD_GET, "/health")
	var ok: bool = response.get("ok", false)
	base_url = previous_url
	if not ok:
		var error_code: String = str(response.get("error_code", ""))
		if not error_code.is_empty():
			status_received.emit("Health error: %s" % error_code)
	return ok

func _should_try_fallback() -> bool:
	return base_url.find("localhost") != -1

func _process_command_queue() -> void:
	if _command_inflight:
		return
	if _command_queue.is_empty():
		return
	_command_inflight = true
	var item: Dictionary = _command_queue.pop_front() as Dictionary
	await _send_command(item)
	_command_inflight = false
	await _process_command_queue()

func _send_command(item: Dictionary) -> void:
	var payload: Dictionary = {
		"command": item.get("command", ""),
		"channel_id": _channel_id,
		"force": item.get("force", false),
	}
	var target_username: String = str(item.get("target_username", ""))
	if not target_username.is_empty():
		payload["target_username"] = target_username
	var response: Dictionary = await _request_json(HTTPClient.METHOD_POST, "/game/command", payload, _command_http)
	var status: int = int(response.get("status", 0))
	if response.get("ok", false):
		status_received.emit("Command OK status=%s" % status)
		return
	var error_text: String = "Command failed"
	var response_data: Variant = response.get("data")
	if typeof(response_data) == TYPE_DICTIONARY:
		var response_dict: Dictionary = response_data as Dictionary
		if response_dict.has("error"):
			error_text = str(response_dict.get("error"))
	status_received.emit("%s status=%s" % [error_text, status])

func _connect_websocket() -> void:
	var ws_url: String = _build_ws_url()
	_ws = WebSocketPeer.new()
	_ws.connect_to_url(ws_url)

func _poll_tick(delta: float) -> void:
	_poll_elapsed += delta
	if _poll_elapsed < _poll_interval:
		return
	_poll_elapsed = 0.0
	if _channel_id <= 0:
		return
	if _poll_inflight:
		return
	_call_poll_snapshot()

func _call_poll_snapshot() -> void:
	await _poll_snapshot()

func _poll_snapshot() -> void:
	_poll_inflight = true
	var response: Dictionary = await _request_json(
		HTTPClient.METHOD_GET,
		"/game/channel/%s/snapshot" % _channel_id,
		{},
		_poll_http,
	)
	_poll_inflight = false
	if not response.get("ok", false):
		return
	var data: Variant = response.get("data")
	if typeof(data) == TYPE_DICTIONARY:
		snapshot_received.emit(data as Dictionary)

func _handle_socket_message(data: Dictionary) -> void:
	var message_type: String = data.get("type", "")
	if message_type == "game_action_error":
		var error_message: String = str(data.get("error", "Unknown error"))
		error_received.emit(error_message)
		return
	if message_type == "game_state_update":
		var snapshot: Variant = data.get("snapshot", {})
		if typeof(snapshot) == TYPE_DICTIONARY:
			snapshot_received.emit(snapshot as Dictionary)
		return
	if message_type == "game_action":
		var snapshot_action: Variant = data.get("snapshot", {})
		if typeof(snapshot_action) == TYPE_DICTIONARY:
			snapshot_received.emit(snapshot_action as Dictionary)
		update_received.emit(data)

func _request_json(method: int, path: String, body: Dictionary = {}, http_request: HTTPRequest = null) -> Dictionary:
	var request_node: HTTPRequest = http_request if http_request != null else _http
	var url: String = _build_url(path)
	var method_name: String = _method_name(method)
	status_received.emit("%s %s" % [method_name, url])
	var headers: PackedStringArray = PackedStringArray()
	headers.append("Content-Type: application/json")
	if not auth_cookie.is_empty():
		headers.append("Cookie: access_token=%s" % auth_cookie)
	var payload: String = ""
	if method != HTTPClient.METHOD_GET and not body.is_empty():
		payload = JSON.stringify(body)
	var error: int = request_node.request(url, headers, method, payload)
	if error != OK:
		status_received.emit("%s %s error=%s" % [method_name, url, error])
		return {"ok": false, "error": "request_failed", "error_code": error}
	var result: Array = await request_node.request_completed
	var request_result: int = int(result[0])
	var status_code: int = int(result[1])
	var response_body: PackedByteArray = result[3]
	var body_text: String = response_body.get_string_from_utf8()
	var parsed: Variant = {}
	if not body_text.is_empty():
		parsed = JSON.parse_string(body_text)
	if request_result != HTTPRequest.RESULT_SUCCESS:
		status_received.emit("%s %s result=%s status=%s" % [method_name, url, request_result, status_code])
		return {
			"ok": false,
			"status": status_code,
			"data": parsed,
			"error": "request_failed",
			"error_code": request_result,
		}
	status_received.emit("%s %s status=%s" % [method_name, url, status_code])
	return {
		"ok": status_code >= 200 and status_code < 300,
		"status": status_code,
		"data": parsed,
	}

func _build_url(path: String) -> String:
	var root: String = base_url.rstrip("/")
	return root + path

func _build_ws_url() -> String:
	var root: String = base_url.rstrip("/")
	if root.begins_with("https://"):
		root = root.replace("https://", "wss://")
	elif root.begins_with("http://"):
		root = root.replace("http://", "ws://")
	return "%s/ws/%s" % [root, user_id]

func _read_env_string(env_name: StringName, fallback: String) -> String:
	var value: String = OS.get_environment(env_name)
	return value if not value.is_empty() else fallback

func _method_name(method: int) -> String:
	match method:
		HTTPClient.METHOD_GET:
			return "GET"
		HTTPClient.METHOD_POST:
			return "POST"
		HTTPClient.METHOD_PUT:
			return "PUT"
		HTTPClient.METHOD_PATCH:
			return "PATCH"
		HTTPClient.METHOD_DELETE:
			return "DELETE"
		_:
			return "HTTP"
