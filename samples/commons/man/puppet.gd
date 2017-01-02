extends Spatial

onready var anim=get_node("AnimationPlayer")
onready var anim_tree=get_node("AnimationTreePlayer")

signal attack_ended
signal attack_hit

func _ready():
	anim_tree.set_active(true)

func play_animation(name):
	if name=="attack":
		anim_tree.transition_node_set_current("transition",1)
		anim_tree.timeseek_node_seek("seek",0)
	else:
		anim_tree.transition_node_set_current("transition",0)

func _on_npc_action_changed( name ):
	play_animation(name)

func attack_finished():
	emit_signal("attack_ended")

func _on_npc_walk_speed_changed( speed ):
	var t=0
	if speed>0.1:
		t=1
	anim_tree.transition_node_set_current("walk",t)
	#anim_tree.blend2_node_set_amount("walk",speed)
	pass

func touch():
	emit_signal("attack_hit")