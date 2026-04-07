extends CharacterBody2D


const SPEED = 150.0
const JUMP_VELOCITY = -250.0
const DODGE_SPEED = 500.0
const DODGE_COOLDOWN = 1.0
const DODGE_INVINCIBILITY_DURATION = 0.5
const FOOTSTEP_LOOP_START = 0.5
const FOOTSTEP_LOOP_END = 1.0

var dodge_cooldown_timer := 0.0
var invincibility_timer := 0.0
var is_dodging := false
var is_invincible := false

@export var is_local_player: bool = true
@export var player_id: String = ""

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var footstep_player: AudioStreamPlayer2D = $AudioStreamPlayer2D

var _footstep_playing := false
var _spawn_position: Vector2 = Vector2.ZERO
var _network_target_position: Vector2 = Vector2.ZERO
var _network_flip_h := false
var _network_animation := "default"

func _ready() -> void:
	_spawn_position = global_position
	_network_target_position = global_position
	if is_local_player:
		add_to_group("local_player")
	else:
		add_to_group("remote_player")
		animated_sprite.play("default")

func _physics_process(delta: float) -> void:
	if not is_local_player:
		return

	if dodge_cooldown_timer > 0.0:
		dodge_cooldown_timer -= delta

	if invincibility_timer > 0.0:
		invincibility_timer -= delta
		is_invincible = true
	else:
		is_invincible = false
		is_dodging = false

	if not is_on_floor():
		velocity += get_gravity() * delta

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	if Input.is_action_just_pressed("ui_shift") and dodge_cooldown_timer <= 0.0:
		var dodge_direction := Input.get_axis("move_left", "move_right")
		if dodge_direction == 0.0:
			dodge_direction = 1.0 if velocity.x >= 0.0 else -1.0
		velocity.x = dodge_direction * DODGE_SPEED
		is_dodging = true
		is_invincible = true
		invincibility_timer = DODGE_INVINCIBILITY_DURATION
		dodge_cooldown_timer = DODGE_COOLDOWN

	if not is_dodging:
		var direction := Input.get_axis("move_left", "move_right")
		if direction > 0:
			animated_sprite.flip_h = false
		elif direction < 0:
			animated_sprite.flip_h = true

		if is_on_floor():
			if direction == 0:
				animated_sprite.play("default")
			else:
				animated_sprite.play("run")
		else:
			animated_sprite.play("jump")

		if direction:
			velocity.x = direction * SPEED
		else:
			velocity.x = move_toward(velocity.x, 0, SPEED)
	else:
		velocity.x = move_toward(velocity.x, 0, DODGE_SPEED * delta / DODGE_INVINCIBILITY_DURATION)
		animated_sprite.play("dash")

	move_and_slide()
	_handle_footsteps(delta)
	_publish_network_state()

func _process(delta: float) -> void:
	if is_local_player:
		return

	global_position = global_position.lerp(_network_target_position, clamp(delta * 12.0, 0.0, 1.0))
	animated_sprite.flip_h = _network_flip_h
	if _network_animation != "" and animated_sprite.animation != _network_animation:
		animated_sprite.play(_network_animation)

func configure_remote(remote_player_id: String, _display_name: String = "") -> void:
	is_local_player = false
	player_id = remote_player_id
	remove_from_group("local_player")
	add_to_group("remote_player")
	animated_sprite.play("default")

func apply_network_state(state: Dictionary) -> void:
	_network_target_position = Vector2(
		float(state.get("x", global_position.x)),
		float(state.get("y", global_position.y))
	)
	_network_flip_h = bool(state.get("flip_h", false))
	_network_animation = str(state.get("animation", "default"))

func respawn() -> void:
	global_position = _spawn_position
	_network_target_position = _spawn_position
	velocity = Vector2.ZERO
	dodge_cooldown_timer = 0.0
	invincibility_timer = 0.0
	is_dodging = false
	is_invincible = false
	animated_sprite.flip_h = false
	animated_sprite.play("default")
	if is_local_player:
		_publish_network_state()

func _publish_network_state() -> void:
	if not is_local_player:
		return

	var network_manager := get_node_or_null("/root/NakamaMultiplayer")
	if network_manager and network_manager.has_method("publish_local_player_state"):
		network_manager.publish_local_player_state(get_network_state())

func get_network_state() -> Dictionary:
	return {
		"x": global_position.x,
		"y": global_position.y,
		"vx": velocity.x,
		"vy": velocity.y,
		"flip_h": animated_sprite.flip_h,
		"animation": animated_sprite.animation,
		"is_dodging": is_dodging,
		"is_invincible": is_invincible,
	}

func _is_on_grass() -> bool:
	for i in get_slide_collision_count():
		var collision = get_slide_collision(i)
		if collision.get_normal().y > -0.5:
			continue
		var collider = collision.get_collider()
		if collider is TileMap:
			var tile_map := collider as TileMap
			var collision_pos = collision.get_position()
			var tile_pos = tile_map.local_to_map(tile_map.to_local(collision_pos))
			for layer in tile_map.get_layers_count():
				var tile_data = tile_map.get_cell_tile_data(layer, tile_pos)
				if tile_data and tile_data.get_custom_data("surface") == "grass":
					return true
	return false

func _handle_footsteps(_delta: float) -> void:
	if not is_local_player:
		return

	var should_play: bool = is_on_floor() and abs(velocity.x) > 0.0 and not is_dodging and _is_on_grass()
	if should_play and not _footstep_playing:
		footstep_player.play(FOOTSTEP_LOOP_START)
		_footstep_playing = true
	elif should_play and _footstep_playing:
		if footstep_player.get_playback_position() >= FOOTSTEP_LOOP_END:
			footstep_player.play(FOOTSTEP_LOOP_START)
	elif not should_play and _footstep_playing:
		footstep_player.stop()
		_footstep_playing = false
