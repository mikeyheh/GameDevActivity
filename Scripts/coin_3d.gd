extends Area3D

@onready var animation_player: AnimationPlayer = $AnimationPlayer

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	if body is CharacterBody3D:
		var game_manager := get_tree().get_first_node_in_group("game_manager")
		if game_manager and game_manager.has_method("add_point"):
			game_manager.add_point()
		monitoring = false
		animation_player.play("pickup")
