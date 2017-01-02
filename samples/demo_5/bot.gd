extends "res://addons/eco.fps.walker/basic_guard.gd"

var attack_is_finished=false

func _ready():
	randomize()

func _on_model_attack_ended():
	attack_is_finished=true

func fsm_attack_finished():
	if attack_is_finished:
		attack_is_finished=false
		return true
	else:
		return false

func _on_model_attack_hit():
	get_target().hit()
