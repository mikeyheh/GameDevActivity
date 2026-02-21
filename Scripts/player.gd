extends CharacterBody2D


const SPEED = 200.0
const JUMP_VELOCITY = -250.0
const DODGE_SPEED = 500.0
const DODGE_COOLDOWN = 1.0
const DODGE_INVINCIBILITY_DURATION = 0.5

var dodge_cooldown_timer := 0.0
var invincibility_timer := 0.0
var is_dodging := false
var is_invincible := false


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
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Handle dodge on Shift press with cooldown.
	if Input.is_action_just_pressed("ui_shift") and dodge_cooldown_timer <= 0.0:
		var dodge_direction := Input.get_axis("ui_left", "ui_right")
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
		var direction := Input.get_axis("ui_left", "ui_right")
		if direction:
			velocity.x = direction * SPEED
		else:
			velocity.x = move_toward(velocity.x, 0, SPEED)
	else:
		# Decelerate from dodge over the invincibility window
		velocity.x = move_toward(velocity.x, 0, DODGE_SPEED * delta / DODGE_INVINCIBILITY_DURATION)

	move_and_slide()
