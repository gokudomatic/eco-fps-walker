extends "walker_core.gd"

const TARGET_DISTANCE=2

var alive=true
var aiming_at_target=false
var can_see_target=false
const action_states=["sleep","move","turn","wait","attack"]

func _ready():
	current_action={
		move=false,
		follow_target=false,
		attack=false
	}

func _init_fsm():
	fsm_action=preload("fsm.gd").new()
	
	_init_fsm_states()
	_init_fsm_move()
	_init_fsm_attack()
	
	fsm_action.set_state("decide")
	fsm_action.connect("state_changed",self,"_action_state_changed")

func _init_fsm_states():
	fsm_action.add_group("main",{move=false,attack=false,follow=false})
	
	fsm_action.add_state("decide",null,"main")
	fsm_action.add_state("wait",{},"main")
	fsm_action.add_state("turn",{},"main")
	fsm_action.add_state("move",{move=true},"main")
	fsm_action.add_state("attack",{move=false,follow=true,attack=true})
	fsm_action.add_state("sleep",{move=false,follow=false,attack=false})

func _init_fsm_move():
	fsm_action.add_link("wait","decide","timeout",[0.2])
	fsm_action.add_link("move","decide","timeout",[2])
	fsm_action.add_link("turn","decide","timeout",[1])
	fsm_action.add_link("sleep","decide","timeout",[5])
	fsm_action.add_link("decide","sleep","condition",[self,"fsm_has_no_target",true])
	fsm_action.add_link("decide","move","condition",[self,"fsm_has_no_target",false])
	

func _init_fsm_attack():
	fsm_action.add_link("attack","decide","timeout",[10])
	fsm_action.add_link("attack","decide","condition",[self,"fsm_attack_finished",true])
	fsm_action.add_link("main","attack","condition",[self,"fsm_can_attack",true])

func _integrate_forces(state):
	if not alive:
		return
	
	can_see_target=get_target() and target_ray.is_colliding() and target_ray.get_collider()==get_target()
	
	._integrate_forces(state)

func fsm_can_attack():
	return get_target() and can_see_target and get_global_transform().origin.distance_to(get_target().get_global_transform().origin)<TARGET_DISTANCE

func fsm_attack_finished():
	return false

func _action_state_changed(state_from,state_to,params):
	
	if state_to=="move":
		calculate_destination()
	
	if action_states.has(state_to):
		current_action.move=params.move
		current_action.follow_target=params.follow
		current_action.attack=params.attack
	
	if state_to=="attack":
		attack()
	
	emit_signal("action_changed",state_to)

func hit():
	die()

func die():
	set_mode(MODE_STATIC) # set ragdoll mode
	set_use_custom_integrator(false)
	alive=false

func attack():
	pass