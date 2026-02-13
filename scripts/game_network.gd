## Manages the network connection to the game backend.
class_name GameNetworkClient
extends Node

signal snapshot_received(snapshot: Dictionary)
signal update_received(update: Dictionary)
signal action_result_received(payload: Dictionary)
signal error_received(message: String)
signal status_received(message: String)
signal connection_state_changed(is_connected: bool)
signal heartbeat_status_changed(ok: bool, latency_ms: int, missed_count: int)

const DEFAULT_BASE_URL: String = "http://localhost:8002"
const FALLBACK_BASE_URL: String = "http://127.0.0.1:8002"
const ENV_BASE_URL: StringName = &"GAME_BACKEND_URL"
const HEARTBEAT_INTERVAL_SEC: float = 10.0
const WS_POLL_INTERVAL_SEC: float = 0.05  # 20Hz polling instead of 60Hz

var base_url: String = DEFAULT_BASE_URL
var user_id: int = 0
var auth_cookie: String = ""
var channel_id: int = -1
var username: String = ""

@onready var _http: HTTPRequest = HTTPRequest.new()
var _ws_poll_timer: Timer
var _heartbeat_timer: Timer

var _ws: WebSocketPeer
var _channel_id: int = -1
var _is_connecting: bool = false
var _last_ws_state: int = WebSocketPeer.STATE_CLOSED
var _debug_heartbeat_enabled: bool = false
var _awaiting_pong: bool = false
var _last_ping_sent_ms: int = 0
var _missed_pongs: int = 0

func _ready() -> void:
	add_child(_http)
	base_url = _read_env_string(ENV_BASE_URL, DEFAULT_BASE_URL)
	_http.timeout = 8.0
	
	# P1: Use Timer for WebSocket polling instead of _process
	_ws_poll_timer = Timer.new()
	_ws_poll_timer.wait_time = WS_POLL_INTERVAL_SEC
	_ws_poll_timer.one_shot = false
	_ws_poll_timer.timeout.connect(_on_ws_poll_timeout)
	add_child(_ws_poll_timer)
	
	# P1: Use Timer for heartbeat instead of accumulator in _process
	_heartbeat_timer = Timer.new()
	_heartbeat_timer.wait_time = HEARTBEAT_INTERVAL_SEC
	_heartbeat_timer.one_shot = false
	_heartbeat_timer.timeout.connect(_on_heartbeat_timeout)
	add_child(_heartbeat_timer)

# P1: Replaced _process polling with Timer-based polling
func _on_ws_poll_timeout() -> void:
	if _ws == null:
		return
	_ws.poll()
	var state = _ws.get_ready_state()
	if state != _last_ws_state:
		_last_ws_state = state
		match state:
			WebSocketPeer.STATE_CONNECTING:
				status_received.emit("WebSocket connecting")
			WebSocketPeer.STATE_OPEN:
				status_received.emit("WebSocket connected")
				connection_state_changed.emit(true)
				if _debug_heartbeat_enabled and _heartbeat_timer.is_stopped():
					_heartbeat_timer.start()
			WebSocketPeer.STATE_CLOSING:
				status_received.emit("WebSocket closing")
			WebSocketPeer.STATE_CLOSED:
				status_received.emit("WebSocket closed")
				connection_state_changed.emit(false)
				_heartbeat_timer.stop()
				_reset_heartbeat_state()
	if state == WebSocketPeer.STATE_OPEN:
		while _ws.get_available_packet_count() > 0:
			var packet: PackedByteArray = _ws.get_packet()
			var text: String = packet.get_string_from_utf8()
			var data: Variant = JSON.parse_string(text)
			if typeof(data) != TYPE_DICTIONARY:
				continue
			_handle_socket_message(data as Dictionary)

# P1: Timer-based heartbeat instead of accumulator
func _on_heartbeat_timeout() -> void:
	if not _debug_heartbeat_enabled:
		return
	_send_heartbeat_ping()

func set_debug_heartbeat_enabled(enabled: bool) -> void:
	_debug_heartbeat_enabled = enabled
	if not enabled:
		_heartbeat_timer.stop()
		_reset_heartbeat_state()
		status_received.emit("Heartbeat disabled")
		return
	status_received.emit("Heartbeat enabled (%ss interval)" % int(HEARTBEAT_INTERVAL_SEC))
	if _ws != null and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_heartbeat_timer.start()

func connect_to_game() -> void:
	if _is_connecting:
		return
	_is_connecting = true
	status_received.emit("Starting connection flow")
	_call_connect_flow()

func send_command(command: String, target_username: String = "", force: bool = false) -> void:
	if _ws == null or _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		error_received.emit("Not connected to game server")
		return
	if _channel_id <= 0:
		error_received.emit("Game channel not joined")
		return
	
	var payload: Dictionary = {
		"type": "game_command",
		"channel_id": _channel_id,
		"payload": {
			"command": command,
			"target_username": target_username if not target_username.is_empty() else null,
			"timestamp": Time.get_unix_time_from_system()
		}
	}
	_ws.send_text(JSON.stringify(payload))

func _call_connect_flow() -> void:
	await _connect_flow()

func _connect_flow() -> void:
	status_received.emit("Checking backend health")
	var health_ok: bool = await _probe_backend()
	if not health_ok:
		_is_connecting = false
		error_received.emit("Backend not reachable")
		return
	status_received.emit("Authenticating")
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
	
	# Initial snapshot might come in auth response, but backend will send full snapshot on WS connect
	if user_id <= 0 or _channel_id <= 0:
		_is_connecting = false
		error_received.emit("Invalid auth payload")
		return
	
	# Join channel via HTTP to establish session (still needed for session creation)
	status_received.emit("Joining #game")
	await _request_json(HTTPClient.METHOD_POST, "/channels/%s/join" % _channel_id)
	
	status_received.emit("Opening WebSocket")
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

func _connect_websocket() -> void:
	var ws_url: String = _build_ws_url()
	_ws = WebSocketPeer.new()
	var err: int = _ws.connect_to_url(ws_url)
	if err != OK:
		error_received.emit("WebSocket connect failed (%s)" % err)
		connection_state_changed.emit(false)
		return
	_last_ws_state = WebSocketPeer.STATE_CONNECTING
	_ws_poll_timer.start()  # P1: Start polling timer when WS connects
	status_received.emit("Waiting for server snapshot")

func _handle_socket_message(data: Dictionary) -> void:
	var message_type: String = str(data.get("type", ""))
	var payload: Dictionary = {}
	if data.has("payload"):
		var p = data.get("payload")
		if typeof(p) == TYPE_DICTIONARY:
			payload = p as Dictionary

	if message_type == "game_snapshot":
		snapshot_received.emit(payload)
		status_received.emit("Snapshot received")
	elif message_type == "game_state_update":
		# Merge logic could happen here or in game_world.gd
		# For now, pass it through as update
		update_received.emit(payload)
	elif message_type == "action_result":
		action_result_received.emit(payload)
		var success: bool = bool(payload.get("success", false))
		var msg: String = str(payload.get("message", ""))
		if not success:
			var error_obj = payload.get("error")
			var error_text = "Unknown error"
			if typeof(error_obj) == TYPE_DICTIONARY:
				error_text = str((error_obj as Dictionary).get("message", "Unknown error"))
			error_received.emit(error_text)
		else:
			if not msg.is_empty():
				status_received.emit(msg)
	elif message_type == "error":
		var msg = str(payload.get("message", "Unknown system error"))
		error_received.emit(msg)
	elif message_type == "pong":
		_handle_heartbeat_pong(payload)

# P1: _tick_heartbeat removed - replaced by _on_heartbeat_timeout Timer callback

func _send_heartbeat_ping() -> void:
	if _ws == null or _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	if _awaiting_pong:
		_missed_pongs += 1
		if _missed_pongs >= 2:
			heartbeat_status_changed.emit(false, -1, _missed_pongs)
			status_received.emit("Heartbeat stale (missed %s)" % _missed_pongs)
	_last_ping_sent_ms = Time.get_ticks_msec()
	_awaiting_pong = true
	_ws.send_text(
		JSON.stringify(
			{
				"type": "ping",
				"payload": {
					"sent_at_ms": _last_ping_sent_ms,
				}
			}
		)
	)

func _handle_heartbeat_pong(payload: Dictionary) -> void:
	var now_ms: int = Time.get_ticks_msec()
	var sent_at_ms: int = int(payload.get("sent_at_ms", 0))
	var latency_ms: int = -1
	if sent_at_ms > 0 and sent_at_ms <= now_ms:
		latency_ms = now_ms - sent_at_ms
	_awaiting_pong = false
	_missed_pongs = 0
	heartbeat_status_changed.emit(true, latency_ms, 0)
	if latency_ms >= 0:
		status_received.emit("Heartbeat OK (%sms)" % latency_ms)
	else:
		status_received.emit("Heartbeat OK")

func _reset_heartbeat_state() -> void:
	_awaiting_pong = false
	_last_ping_sent_ms = 0
	_missed_pongs = 0

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
