extends CharacterBody2D


const SPEED = 150.0
const JUMP_VELOCITY = -250.0
const DODGE_SPEED = 500.0
const DODGE_COOLDOWN = 1.0
const DODGE_INVINCIBILITY_DURATION = 0.5

var dodge_cooldown_timer := 0.0
var invincibility_timer := 0.0
var is_dodging := false
var is_invincible := false

@onready var animated_sprite = $AnimatedSprite2D
@onready var footstep_player: AudioStreamPlayer2D = $AudioStreamPlayer2D

# Seconds into the audio file where the loop section starts and ends
const FOOTSTEP_LOOP_START = 0.5
const FOOTSTEP_LOOP_END = 1.0  # Set this just before the end sounds bad
var _footstep_playing := false

func _physics_process(delta: float) -> void:
	# Tick down timers
	if dodge_cooldown_timer > 0.0:
		dodge_cooldown_timer -= delta

	if invincibility_timer > 0.0:
		invincibility_timer -= delta
		is_invincible = true
	else:
		is_invincible = false
		is_dodging = false

	# Add the gravity.
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Handle jump.
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Handle dodge on Shift press with cooldown.
	if Input.is_action_just_pressed("ui_shift") and dodge_cooldown_timer <= 0.0:
		var dodge_direction := Input.get_axis("move_left", "move_right")
		if dodge_direction == 0.0:
			dodge_direction = 1.0 if velocity.x >= 0.0 else -1.0
		velocity.x = dodge_direction * DODGE_SPEED
		is_dodging = true
		is_invincible = true
		invincibility_timer = DODGE_INVINCIBILITY_DURATION
		dodge_cooldown_timer = DODGE_COOLDOWN

	# Get the input direction and handle the movement/deceleration.
	# Skip normal movement control while actively dodging.
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
		# Decelerate from dodge over the invincibility window
		velocity.x = move_toward(velocity.x, 0, DODGE_SPEED * delta / DODGE_INVINCIBILITY_DURATION)
		animated_sprite.play("dash")

	move_and_slide()
	_handle_footsteps(delta)


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
			# Search all layers since grass tiles may not be on layer 0
			for layer in tile_map.get_layers_count():
				var tile_data = tile_map.get_cell_tile_data(layer, tile_pos)
				if tile_data and tile_data.get_custom_data("surface") == "grass":
					return true
	return false


func _handle_footsteps(_delta: float) -> void:
	var should_play: bool = is_on_floor() and abs(velocity.x) > 0.0 and not is_dodging and _is_on_grass()
	if should_play and not _footstep_playing:
		footstep_player.play(FOOTSTEP_LOOP_START)
		_footstep_playing = true
	elif should_play and _footstep_playing:
		# Loop back before the end of the file to avoid the abrupt ending
		if footstep_player.get_playback_position() >= FOOTSTEP_LOOP_END:
			footstep_player.play(FOOTSTEP_LOOP_START)
	elif not should_play and _footstep_playing:
		footstep_player.stop()
		_footstep_playing = false


