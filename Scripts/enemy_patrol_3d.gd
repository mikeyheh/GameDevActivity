extends CharacterBody3D

@export var speed := 2.5

@onready var ray_bottom_left: RayCast3D = $BottomLeft
@onready var ray_bottom_right: RayCast3D = $BottomRight
@onready var sprite: Sprite3D = $Sprite3D

var _direction := 1
var _turn_cooldown := 0.0
var _no_floor_frames := 0
const NO_FLOOR_THRESHOLD := 4

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * delta

	velocity.x = _direction * speed
	velocity.z = 0.0

	if _turn_cooldown > 0.0:
		_turn_cooldown -= delta
		_no_floor_frames = 0
	else:
		var floor_ray := ray_bottom_right if _direction == 1 else ray_bottom_left
		if not floor_ray.is_colliding():
			_no_floor_frames += 1
		else:
			_no_floor_frames = 0

		if _no_floor_frames >= NO_FLOOR_THRESHOLD:
			_direction = -_direction
			_turn_cooldown = 0.25
			_no_floor_frames = 0

	sprite.flip_h = _direction < 0
	move_and_slide()
