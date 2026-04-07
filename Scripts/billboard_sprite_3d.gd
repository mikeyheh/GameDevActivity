extends Sprite3D

@export var camera_path: NodePath
@export var lock_to_y_axis: bool = true
@export var yaw_offset_degrees: float = 0.0

var _camera: Camera3D

func _ready() -> void:
	_resolve_camera()

func _process(_delta: float) -> void:
	if _camera == null:
		_resolve_camera()
		if _camera == null:
			return

	var look_target: Vector3 = _camera.global_position
	if lock_to_y_axis:
		look_target.y = global_position.y

	look_at(look_target, Vector3.UP)
	rotation_degrees.y += yaw_offset_degrees

func _resolve_camera() -> void:
	if camera_path != NodePath():
		_camera = get_node_or_null(camera_path) as Camera3D
	if _camera == null:
		_camera = get_viewport().get_camera_3d()
