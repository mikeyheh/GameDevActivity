extends Area2D

@onready var timer = $Timer

func _ready():
    body_entered.connect(_on_body_entered)
    timer.timeout.connect(_on_timer_timeout)

func _on_body_entered(body):
    print("You Died!")
    timer.start()

func _on_timer_timeout():
    get_tree().reload_current_scene()