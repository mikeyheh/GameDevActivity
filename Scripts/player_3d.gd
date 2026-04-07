extends CharacterBody3D

const SPEED := 6.0
const JUMP_VELOCITY := 7.0
const DODGE_SPEED := 14.0
const DODGE_COOLDOWN := 1.0
const DODGE_INVINCIBILITY_DURATION := 0.5

const FOOTSTEP_LOOP_START := 0.5
const FOOTSTEP_LOOP_END := 1.0

const FRAME_SIZE := Vector2i(32, 32)
const ANIM_IDLE = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)]
const ANIM_RUN = [Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2), Vector2i(3, 2), Vector2i(4, 2), Vector2i(5, 2), Vector2i(6, 2), Vector2i(7, 2)]
const ANIM_DASH = [Vector2i(2, 5), Vector2i(3, 5), Vector2i(4, 5), Vector2i(5, 5), Vector2i(6, 5), Vector2i(7, 5)]
const ANIM_JUMP_FRAME := Vector2i(2, 5)
const IDLE_FPS := 5.0
const RUN_FPS := 10.0
const DASH_FPS := 12.0

var dodge_cooldown_timer := 0.0
var invincibility_timer := 0.0
var is_dodging := false
var is_invincible := false
var _footstep_playing := false
var _anim_time := 0.0
var _base_texture: Texture2D
var _frame_cache: Dictionary = {}

@onready var sprite: Sprite3D = $Sprite3D
@onready var footstep_player: AudioStreamPlayer3D = $AudioStreamPlayer3D

func _ready() -> void:
	_base_texture = sprite.texture

func _physics_process(delta: float) -> void:
	if dodge_cooldown_timer > 0.0:
		dodge_cooldown_timer -= delta

	if invincibility_timer > 0.0:
		invincibility_timer -= delta
		is_invincible = true
	else:
		is_invincible = false
		is_dodging = false

	if not is_on_floor():
		velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * delta

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
		if direction != 0.0:
			velocity.x = direction * SPEED
			sprite.flip_h = direction > 0.0
		else:
			velocity.x = move_toward(velocity.x, 0.0, SPEED)
	else:
		velocity.x = move_toward(velocity.x, 0.0, DODGE_SPEED * delta / DODGE_INVINCIBILITY_DURATION)

	velocity.z = 0.0
	move_and_slide()
	_update_animation(delta)
	_handle_footsteps()


func _handle_footsteps() -> void:
	var should_play: bool = is_on_floor() and absf(velocity.x) > 0.2 and not is_dodging
	if should_play and not _footstep_playing:
		footstep_player.play(FOOTSTEP_LOOP_START)
		_footstep_playing = true
	elif should_play and _footstep_playing:
		if footstep_player.get_playback_position() >= FOOTSTEP_LOOP_END:
			footstep_player.play(FOOTSTEP_LOOP_START)
	elif not should_play and _footstep_playing:
		footstep_player.stop()
		_footstep_playing = false


func _update_animation(delta: float) -> void:
	_anim_time += delta

	if not is_on_floor():
		sprite.texture = _frame_texture(ANIM_JUMP_FRAME)
		return

	if is_dodging:
		sprite.texture = _frame_texture(_frame_from_sequence(ANIM_DASH, DASH_FPS))
		return

	if absf(velocity.x) > 0.2:
		sprite.texture = _frame_texture(_frame_from_sequence(ANIM_RUN, RUN_FPS))
	else:
		sprite.texture = _frame_texture(_frame_from_sequence(ANIM_IDLE, IDLE_FPS))


func _frame_from_sequence(frames: Array, fps: float) -> Vector2i:
	if frames.is_empty():
		return Vector2i.ZERO
	var frame_index := int(floor(_anim_time * fps)) % frames.size()
	return frames[frame_index]


func _frame_texture(frame_coord: Vector2i) -> AtlasTexture:
	if _frame_cache.has(frame_coord):
		return _frame_cache[frame_coord] as AtlasTexture

	var atlas_tex := AtlasTexture.new()
	atlas_tex.atlas = _base_texture
	atlas_tex.region = Rect2(frame_coord * FRAME_SIZE, FRAME_SIZE)
	_frame_cache[frame_coord] = atlas_tex
	return atlas_tex
