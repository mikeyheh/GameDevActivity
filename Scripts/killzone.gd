extends Area2D

@onready var timer = $Timer

var _pending_body: Node = null

func _ready():
    body_entered.connect(_on_body_entered)
    timer.timeout.connect(_on_timer_timeout)

func _on_body_entered(body):
    if not body.is_in_group("local_player"):
        return

    _pending_body = body
    print("You Died!")
    timer.start()

func _on_timer_timeout():
    if _pending_body and is_instance_valid(_pending_body) and _pending_body.has_method("respawn"):
        _pending_body.respawn()
    else:
        get_tree().reload_current_scene()
    _pending_body = null