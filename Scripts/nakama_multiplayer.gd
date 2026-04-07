extends Node

signal status_changed(message: String)
signal match_joined(match_id: String)
signal match_join_failed(message: String)
signal remote_player_joined(session_id: String)
signal remote_player_left(session_id: String)

const DEFAULT_HOST := "127.0.0.1"
const DEFAULT_PORT := 7350
const DEFAULT_SCHEME := "ws"
const DEFAULT_SERVER_KEY := "defaultkey"
const DEFAULT_MATCH_QUERY := "*"
const DEFAULT_MATCH_MIN_COUNT := 2
const DEFAULT_MATCH_MAX_COUNT := 2
const STATE_SEND_INTERVAL := 1.0 / 15.0
const STATE_OP_CODE := 1
const PLAYER_SCENE_PATH := "res://Scenes/player.tscn"

@export var host: String = DEFAULT_HOST
@export var port: int = DEFAULT_PORT
@export var scheme: String = DEFAULT_SCHEME
@export var server_key: String = DEFAULT_SERVER_KEY
@export var auto_connect: bool = true
@export var auto_join_matchmaker: bool = true

var session_token: String = ""
var user_id: String = ""
var username: String = ""
var match_id: String = ""

var _http_request: HTTPRequest
var _socket: WebSocketPeer = WebSocketPeer.new()
var _connected := false
var _connecting := false
var _matchmaker_started := false
var _socket_started := false
var _request_cid := 1
var _state_send_timer := 0.0
var _queued_local_state: Dictionary = {}
var _remote_players: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_bootstrap")

func _bootstrap() -> void:
	_http_request = HTTPRequest.new()
	add_child(_http_request)
	if auto_connect:
		connect_to_server()

func connect_to_server() -> void:
	if _connecting or _connected:
		return
	_connecting = true
	_matchmaker_started = false
	_socket_started = false
	match_id = ""
	_emit_status("Authenticating with Nakama")
	await _authenticate_and_connect()

func disconnect_from_server() -> void:
	if _socket and _socket.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		_socket.close()
	_handle_socket_closed()

func publish_local_player_state(state: Dictionary) -> void:
	_queued_local_state = state.duplicate(true)

func has_remote_player(session_id: String) -> bool:
	return _remote_players.has(session_id)

func get_remote_player(session_id: String) -> Node:
	return _remote_players.get(session_id, null)

func _process(_delta: float) -> void:
	_poll_socket()

func _physics_process(delta: float) -> void:
	if _state_send_timer > 0.0:
		_state_send_timer -= delta

	if _connected and match_id != "" and not _queued_local_state.is_empty() and _state_send_timer <= 0.0:
		_send_match_state(_queued_local_state)
		_state_send_timer = STATE_SEND_INTERVAL

func _authenticate_and_connect() -> void:
	var device_id := _build_device_id()
	var auth_payload := {"id": device_id}
	var response := await _request_json(
		"/v2/account/authenticate/device?create=true",
		auth_payload,
		true
	)

	if response.is_empty():
		_connecting = false
		_emit_status("Nakama authentication failed")
		return

	session_token = str(response.get("token", ""))
	
	if session_token.is_empty():
		_connecting = false
		_emit_status("Nakama authentication returned no token")
		return
	
	# Extract user_id from JWT payload
	var jwt_parts := session_token.split(".")
	if jwt_parts.size() < 2:
		_connecting = false
		_emit_status("Invalid JWT token format")
		return
	
	var payload_encoded := jwt_parts[1]
	var payload_json := _decode_base64_url(payload_encoded)
	var jwt_payload := _parse_json_object(payload_json)
	
	user_id = str(jwt_payload.get("uid", ""))
	username = str(jwt_payload.get("usn", ""))
	
	if user_id.is_empty():
		_connecting = false
		_emit_status("Could not extract user_id from JWT token")
		return

	var ws_scheme := "wss" if scheme == "wss" else "ws"
	var ws_url := "%s://%s:%d/ws?lang=en&status=false&token=%s" % [
		ws_scheme,
		host,
		port,
		session_token.uri_encode()
	]

	_socket = WebSocketPeer.new()
	var connect_error := _socket.connect_to_url(ws_url)
	if connect_error != OK:
		_connecting = false
		_emit_status("WebSocket connect failed: %s" % error_string(connect_error))
		return
	_socket_started = true

	_emit_status("Connecting to matchmaker")

func _request_json(path: String, body: Dictionary, use_basic_auth: bool) -> Dictionary:
	if _http_request == null:
		return {}

	var scheme_prefix := "https" if scheme == "wss" else "http"
	var url := "%s://%s:%d%s" % [scheme_prefix, host, port, path]
	var headers := PackedStringArray(["Content-Type: application/json"])
	if use_basic_auth:
		var credentials := Marshalls.utf8_to_base64("%s:" % server_key)
		headers.append("Authorization: Basic %s" % credentials)

	var payload := JSON.stringify(body)
	var request_error := _http_request.request(url, headers, HTTPClient.METHOD_POST, payload)
	if request_error != OK:
		_emit_status("HTTP request failed: %s" % error_string(request_error))
		return {}

	var result: Array = await _http_request.request_completed
	var response_code := int(result[1])
	var response_body: PackedByteArray = result[3]
	if response_code < 200 or response_code >= 300:
		_emit_status("HTTP auth failed with status %d" % response_code)
		return {}

	var text := response_body.get_string_from_utf8()
	return _parse_json_object(text)

func _poll_socket() -> void:
	if _socket == null:
		return
	if not _socket_started:
		return

	_socket.poll()
	match _socket.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if not _connected:
				_connected = true
				_connecting = false
				_emit_status("Nakama socket connected")
				if auto_join_matchmaker and not _matchmaker_started:
					_start_matchmaker()
		WebSocketPeer.STATE_CLOSED:
			if _connected or _connecting:
				_handle_socket_closed()
				return

	while _socket.get_available_packet_count() > 0:
		var packet := _socket.get_packet()
		var text := packet.get_string_from_utf8()
		var message := _parse_json_object(text)
		if not message.is_empty():
			_handle_socket_message(message)

func _handle_socket_closed() -> void:
	_connected = false
	_connecting = false
	_matchmaker_started = false
	_socket_started = false
	match_id = ""
	_state_send_timer = 0.0
	_emit_status("Nakama socket closed")
	for session_id in _remote_players.keys():
		var remote_player: Node = _remote_players[session_id]
		if is_instance_valid(remote_player):
			remote_player.queue_free()
	_remote_players.clear()

func _start_matchmaker() -> void:
	_matchmaker_started = true
	_send_json({
		"cid": str(_next_request_cid()),
		"matchmaker_add": {
			"query": DEFAULT_MATCH_QUERY,
			"min_count": DEFAULT_MATCH_MIN_COUNT,
			"max_count": DEFAULT_MATCH_MAX_COUNT,
			"string_properties": {},
			"numeric_properties": {}
		}
	})

func _send_match_state(state: Dictionary) -> void:
	if match_id.is_empty():
		return

	var state_json := JSON.stringify(state)
	var encoded := Marshalls.utf8_to_base64(state_json)
	_send_json({
		"cid": str(_next_request_cid()),
		"match_data_send": {
			"match_id": match_id,
			"op_code": STATE_OP_CODE,
			"data": encoded
		}
	})

func _handle_socket_message(message: Dictionary) -> void:
	if message.has("error"):
		var error_payload: Dictionary = message["error"]
		match_join_failed.emit(str(error_payload.get("message", "Unknown Nakama error")))
		_emit_status("Nakama error: %s" % str(error_payload.get("message", "Unknown Nakama error")))
		return

	if message.has("matchmaker_matched"):
		_handle_matchmaker_matched(message["matchmaker_matched"])
		return

	if message.has("match"):
		_handle_match_joined(message["match"])
		return

	if message.has("match_presence_event"):
		_handle_match_presence_event(message["match_presence_event"])
		return

	if message.has("match_data"):
		_handle_match_data(message["match_data"])
		return

func _handle_matchmaker_matched(payload: Dictionary) -> void:
	var received_match_id := str(payload.get("match_id", ""))
	var join_token := str(payload.get("token", ""))
	if received_match_id.is_empty() and join_token.is_empty():
		match_join_failed.emit("Matchmaker returned no match id or token")
		return

	_emit_status("Joining matched game")
	var join_payload: Dictionary = {"cid": str(_next_request_cid()), "match_join": {}}
	if not received_match_id.is_empty():
		join_payload["match_join"]["match_id"] = received_match_id
	else:
		join_payload["match_join"]["token"] = join_token
	_send_json(join_payload)

func _handle_match_joined(payload: Dictionary) -> void:
	match_id = str(payload.get("match_id", ""))
	match_joined.emit(match_id)
	_emit_status("Joined match %s" % match_id)

	if user_id.is_empty():
		_emit_status("WARNING: user_id not set when joining match")
		return

	var presences: Array = payload.get("presences", [])
	for presence in presences:
		if not presence is Dictionary:
			continue
		var session_id := str(presence.get("session_id", ""))
		var presence_user_id := str(presence.get("user_id", ""))
		if session_id.is_empty() or presence_user_id == user_id:
			continue
		_ensure_remote_player(session_id, str(presence.get("username", "")))

func _handle_match_presence_event(payload: Dictionary) -> void:
	var joins: Array = payload.get("joins", [])
	for presence in joins:
		if not presence is Dictionary:
			continue
		var session_id := str(presence.get("session_id", ""))
		var presence_user_id := str(presence.get("user_id", ""))
		if session_id.is_empty() or presence_user_id == user_id:
			continue
		_ensure_remote_player(session_id, str(presence.get("username", "")))

	var leaves: Array = payload.get("leaves", [])
	for presence in leaves:
		if not presence is Dictionary:
			continue
		var session_id := str(presence.get("session_id", ""))
		if session_id.is_empty():
			continue
		_remove_remote_player(session_id)

func _handle_match_data(payload: Dictionary) -> void:
	var presence: Dictionary = payload.get("presence", {})
	if presence.is_empty():
		return

	var sender_user_id := str(presence.get("user_id", ""))
	if sender_user_id == user_id:
		return

	var session_id := str(presence.get("session_id", ""))
	if session_id.is_empty():
		return

	var encoded := str(payload.get("data", ""))
	if encoded.is_empty():
		return

	var decoded_text := _decode_base64_text(encoded)
	if decoded_text.is_empty():
		return

	var state := _parse_json_object(decoded_text)
	if state.is_empty():
		return

	var remote_player := _ensure_remote_player(session_id, str(presence.get("username", "")))
	if remote_player and remote_player.has_method("apply_network_state"):
		remote_player.call("apply_network_state", state)

func _ensure_remote_player(session_id: String, display_name: String) -> Node:
	if _remote_players.has(session_id):
		return _remote_players[session_id]

	var current_scene := get_tree().current_scene
	if current_scene == null:
		return null

	var player_scene := load(PLAYER_SCENE_PATH) as PackedScene
	if player_scene == null:
		return null

	var remote_player := player_scene.instantiate()
	if remote_player == null:
		return null

	remote_player.name = "RemotePlayer_%s" % session_id.replace("-", "_")
	current_scene.add_child(remote_player)

	if remote_player.has_method("configure_remote"):
		remote_player.call("configure_remote", session_id, display_name)
	else:
		remote_player.set("is_local_player", false)

	_remote_players[session_id] = remote_player
	remote_player_joined.emit(session_id)
	return remote_player

func _remove_remote_player(session_id: String) -> void:
	if not _remote_players.has(session_id):
		return

	var remote_player: Node = _remote_players[session_id]
	_remote_players.erase(session_id)
	if is_instance_valid(remote_player):
		remote_player.queue_free()
	remote_player_left.emit(session_id)

func _send_json(payload: Dictionary) -> void:
	if _socket == null or _socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return

	var text := JSON.stringify(payload)
	_socket.send(text.to_utf8_buffer(), WebSocketPeer.WRITE_MODE_TEXT)

func _next_request_cid() -> int:
	var cid := _request_cid
	_request_cid += 1
	return cid

func _parse_json_object(text: String) -> Dictionary:
	var json := JSON.new()
	if json.parse(text) != OK:
		return {}
	var data = json.get_data()
	return data if data is Dictionary else {}

func _decode_base64_text(encoded: String) -> String:
	var raw := Marshalls.base64_to_raw(encoded)
	if raw.is_empty():
		return ""
	return raw.get_string_from_utf8()

func _decode_base64_url(encoded: String) -> String:
	# Convert base64url to standard base64
	var standard_b64 := encoded.replace("-", "+").replace("_", "/")
	# Add padding
	var padding_needed := 4 - (standard_b64.length() % 4)
	if padding_needed < 4:
		standard_b64 += "=".repeat(padding_needed)
	return _decode_base64_text(standard_b64)

func _build_device_id() -> String:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return "gda-%s-%s" % [str(Time.get_unix_time_from_system()), str(rng.randi_range(0, 2147483647))]

func _emit_status(message: String) -> void:
	status_changed.emit(message)
	print(message)
