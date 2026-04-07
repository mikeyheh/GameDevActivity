extends Camera3D

@export var target_path: NodePath
@export var follow_speed := 8.0
@export var offset := Vector3(0.0, 2.5, 7.5)
@export var look_at_offset := Vector3(0.0, 0.9, 0.0)

var _target: Node3D

func _ready() -> void:
	_resolve_target()

func _physics_process(delta: float) -> void:
	if _target == null:
		_resolve_target()
		if _target == null:
			return

	var desired_position := _target.global_position + offset
	global_position = global_position.lerp(desired_position, clamp(follow_speed * delta, 0.0, 1.0))
	look_at(_target.global_position + look_at_offset, Vector3.UP)

func _resolve_target() -> void:
	if target_path != NodePath():
		_target = get_node_or_null(target_path) as Node3D
