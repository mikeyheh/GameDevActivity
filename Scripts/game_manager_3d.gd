extends Node

var score := 0

@onready var score_label: Label = $"../CanvasLayer/ScoreLabel"

func add_point() -> void:
	score += 1
	score_label.text = "Score: %d" % score
