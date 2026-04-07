extends Area3D

@onready var timer: Timer = $Timer

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	timer.timeout.connect(_on_timer_timeout)

func _on_body_entered(body: Node) -> void:
	if body is CharacterBody3D and body.is_in_group("player"):
		print("You Died!")
		monitoring = false
		timer.start()

func _on_timer_timeout() -> void:
	get_tree().reload_current_scene()
