extends AnimatedSprite2D

@export var speed: float = 60.0

@onready var ray_bottom_left: RayCast2D = get_parent().get_node("BottomLeft")
@onready var ray_bottom_right: RayCast2D = get_parent().get_node("BottomRight")

var _direction: int = 1  # 1 = right, -1 = left
var _turn_cooldown: float = 0.0
var _no_floor_frames: int = 0
const NO_FLOOR_THRESHOLD: int = 6  # physics frames of missing floor before turning

func _physics_process(delta: float) -> void:
	get_parent().position.x += _direction * speed * delta

	if _turn_cooldown > 0.0:
		_turn_cooldown -= delta
		_no_floor_frames = 0
	else:
		# Check for edge ahead (require sustained no-floor to filter tile seams)
		var floor_ray = ray_bottom_right if _direction == 1 else ray_bottom_left
		if not floor_ray.is_colliding():
			_no_floor_frames += 1
		else:
			_no_floor_frames = 0

		if _no_floor_frames >= NO_FLOOR_THRESHOLD:
			_direction = -_direction
			_turn_cooldown = 0.4
			_no_floor_frames = 0

	# Flip sprite to face movement direction
	flip_h = _direction < 0
